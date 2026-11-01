import Combine
import Foundation
import os
import DynaNotchCore

/// Daily Wrap (CONTRACTS §6.19): at the set time, one card with today's highlights. One scheduled work item, no
/// polling; if you're away then, it waits until you're back.
final class DailyWrapService {
    static let shared = DailyWrapService()

    /// Main queue: the card's lines.
    let wraps = PassthroughSubject<[WrapLine], Never>()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "wrap")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.wrap", qos: .utility)
    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private var scheduled: DispatchWorkItem?
    private var waitingForReturn = false
    private(set) var next: Date?
    private(set) var lastLines: [String] = []

    private init() {}

    var state: [String: Any] {
        ["next": next.map { Int($0.timeIntervalSince1970) } ?? 0, "lastLines": lastLines]
    }

    func start() {
        guard !started else { return }
        started = true
        let settings = AppSettings.shared
        Publishers.CombineLatest3(settings.$dailyWrap, settings.$dailyWrapMinutes, settings.$dailyWrapWeekdays)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _, _ in self?.schedule() }
            .store(in: &cancellables)
        UserPresence.shared.start()
        UserPresence.shared.returned
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self, self.waitingForReturn else { return }
                self.waitingForReturn = false
                self.showNow()
            }
            .store(in: &cancellables)
    }

    /// Builds today's card now (also `dynanotch://wrap`). Commits are counted off the main queue.
    func showNow() {
        let base = currentInput()
        queue.async { [weak self] in
            let commits = DailyWrapService.commitsToday()
            DispatchQueue.main.async {
                guard let self = self else { return }
                var input = base
                input.commits = commits
                let lines = DailyWrap.lines(input)
                self.lastLines = lines.map(\.text)
                if !lines.isEmpty { self.wraps.send(lines) }
            }
        }
    }

    // MARK: Main queue

    private func schedule() {
        scheduled?.cancel()
        scheduled = nil
        let settings = AppSettings.shared
        guard settings.dailyWrap,
              let date = DailyWrap.nextDate(after: Date(), minutes: Int(settings.dailyWrapMinutes),
                                            weekdaysOnly: settings.dailyWrapWeekdays) else {
            next = nil
            return
        }
        next = date
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if UserPresence.shared.isAway { self.waitingForReturn = true } else { self.showNow() }
            self.schedule()
        }
        scheduled = item
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + date.timeIntervalSinceNow, execute: item)
    }

    private func currentInput() -> DailyWrap.Input {
        let screen = ScreenTimeService.shared
        let today = Calendar.current.startOfDay(for: Date())
        let songs = ListeningHistoryService.shared.history.entries
            .filter { $0.playedAt >= today }
            .map { $0.artist.isEmpty ? $0.title : "\($0.title) — \($0.artist)" }
        return DailyWrap.Input(screenSeconds: screen.totalToday(), topApps: screen.today(limit: 3).map(\.name),
                               pomodoros: PomodoroStatsService.shared.stats.today(now: Date()), songs: songs,
                               claudeCost: AIUsageService.shared.claudeToday?.cost, commits: nil)
    }

    // MARK: Commits (utility queue)

    private static let codeFolders = ["Desktop", "Developer", "Projects", "Code", "src"]

    static func commitsToday() -> Int? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var repos: [URL] = []
        for folder in codeFolders {
            let root = home.appendingPathComponent(folder)
            guard let level1 = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles]) else { continue }
            for dir in level1 {
                if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { repos.append(dir); continue }
                let level2 = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles])) ?? []
                repos += level2.filter { fm.fileExists(atPath: $0.appendingPathComponent(".git").path) }
            }
        }
        guard !repos.isEmpty else { return nil }
        let email = run(["config", "--global", "user.email"], in: home)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var total = 0
        for repo in repos.prefix(30) {
            var args = ["rev-list", "--count", "--since=midnight", "--all"]
            if !email.isEmpty { args.append("--author=\(email)") }
            total += Int(run(args, in: repo)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        }
        return total
    }

    private static func run(_ args: [String], in dir: URL) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["-C", dir.path] + args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return task.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }
}
