import AppKit
import Combine
import CryptoKit
import Foundation
import os
import DynaNotchCore

/// In-app updates (CONTRACTS §6.21): asks GitHub for the latest release once a day, offers it in the panel header and
/// the menu bar, and installs it by swapping the app bundle and relaunching. Release notes for the What's New story
/// come from the release's `WhatsNew.json` asset (or the release body).
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(AvailableUpdate, [ReleaseNote])
        case downloading(Double)
        case installing
        case failed(String)

        var name: String {
            switch self {
            case .idle: return "idle"
            case .checking: return "checking"
            case .upToDate: return "upToDate"
            case .available: return "available"
            case .downloading: return "downloading"
            case .installing: return "installing"
            case .failed: return "failed"
            }
        }
    }

    @Published private(set) var status: Status = .idle
    /// The newest update found, kept while it downloads / installs (status no longer carries it then).
    @Published private(set) var update: AvailableUpdate?
    @Published private(set) var updateNotes: [ReleaseNote] = []
    @Published private(set) var lastChecked: Date?

    /// `dynanotch://update/feed?url=` — a test feed instead of GitHub (memory only).
    var feedOverride: URL?

    static let feedURL = URL(string: "https://api.github.com/repos/tanim-ics/dyna-notch/releases/latest")
    static let bundleIdentifier = "com.tanim.dynanotch"

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static let lastCheckKey = "dn.data.lastUpdateCheck"
    private static let notifiedKey = "dn.data.notifiedUpdateVersion"

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "updates")
    private let session: URLSession
    private var cancellables = Set<AnyCancellable>()
    private var timer: DispatchSourceTimer?
    private var started = false
    private var progressObservation: NSKeyValueObservation?

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.httpAdditionalHeaders = ["User-Agent": "DynaNotch/\(UpdateService.currentVersion)",
                                        "Accept": "application/vnd.github+json"]
        session = URLSession(configuration: config)
        lastChecked = UserDefaults.standard.object(forKey: UpdateService.lastCheckKey) as? Date
    }

    func start() {
        guard !started else { return }
        started = true
        AppSettings.shared.$checkForUpdates
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in on ? self?.schedule() : self?.stopTimer() }
            .store(in: &cancellables)
    }

    var state: [String: Any] {
        var state: [String: Any] = [
            "status": status.name,
            "current": UpdateService.currentVersion,
            "latest": update?.version ?? "",
            "lastChecked": lastChecked.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "auto": AppSettings.shared.checkForUpdates,
            "feedOverride": feedOverride?.absoluteString ?? "",
        ]
        if case .failed(let message) = status { state["error"] = message }
        if case .downloading(let fraction) = status { state["progress"] = fraction }
        return state
    }

    // MARK: Checking

    /// Asks the feed now. `manual` checks also report "up to date" and errors in the status.
    func checkNow(manual: Bool = true) {
        switch status {
        case .checking, .downloading, .installing: return
        default: break
        }
        guard let url = feedOverride ?? UpdateService.feedURL else { return }
        status = .checking
        logger.info("checking \(url.absoluteString, privacy: .public)")
        session.dataTask(with: url) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let release = data.flatMap { try? JSONDecoder().decode(GitHubRelease.self, from: $0) }
            DispatchQueue.main.async {
                self?.finishCheck(release: release, code: code, error: error, manual: manual)
            }
        }.resume()
    }

    private func finishCheck(release: GitHubRelease?, code: Int, error: Error?, manual: Bool) {
        let now = Date()
        guard let release = release else {
            let message = error?.localizedDescription ?? (code == 404 ? "No release published yet." : "GitHub answered \(code).")
            logger.error("check failed: \(message, privacy: .public)")
            status = manual ? .failed(message) : .idle
            return
        }
        lastChecked = now
        UserDefaults.standard.set(now, forKey: UpdateService.lastCheckKey)
        guard let found = UpdateCheck.evaluate(release, current: UpdateService.currentVersion) else {
            logger.info("up to date (latest \(release.tagName, privacy: .public))")
            update = nil
            updateNotes = []
            status = .upToDate
            return
        }
        logger.info("update available: \(found.version, privacy: .public)")
        update = found
        loadNotes(for: found) { [weak self] notes in
            guard let self = self else { return }
            self.updateNotes = notes
            self.status = .available(found, notes)
            self.announce(found)
        }
    }

    /// The release's WhatsNew.json, narrowed to versions after the installed one; else the release body's bullets.
    private func loadNotes(for found: AvailableUpdate, completion: @escaping ([ReleaseNote]) -> Void) {
        let fallback: () -> [ReleaseNote] = {
            ReleaseNotes.fromMarkdown(found.body ?? "", version: found.version).map { [$0] }
                ?? [ReleaseNote(version: found.version, features: [
                    FeatureNote(symbol: "sparkles", color: "purple", title: "DynaNotch \(found.version)",
                                text: "A new version is ready with fixes and improvements."),
                ])]
        }
        guard let url = found.notesURL else {
            completion(fallback())
            return
        }
        session.dataTask(with: url) { data, _, _ in
            let all = data.map(ReleaseNotes.decode) ?? []
            let notes = ReleaseNotes.between(all, after: UpdateService.currentVersion, upTo: found.version)
            DispatchQueue.main.async { completion(notes.isEmpty ? fallback() : notes) }
        }.resume()
    }

    /// One notification island per new version.
    private func announce(_ found: AvailableUpdate) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: UpdateService.notifiedKey) != found.version else { return }
        defaults.set(found.version, forKey: UpdateService.notifiedKey)
        AppActions.shared.viewModel?.notify(NotchNotification(
            title: "DynaNotch \(found.version) is here",
            body: "Open the panel and click Update to see what's new.",
            symbol: "arrow.down.circle.fill", duration: 6))
    }

    // MARK: Schedule

    private func schedule() {
        stopTimer()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // First look 20 s after launch, then hourly ticks that only ask GitHub once a day.
        timer.schedule(deadline: .now() + 20, repeating: 3600, leeway: .seconds(600))
        timer.setEventHandler { [weak self] in
            guard let self = self, AppSettings.shared.checkForUpdates,
                  UpdateCheck.isDue(lastCheck: self.lastChecked, now: Date()) else { return }
            self.checkNow(manual: false)
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: Installing

    /// Downloads, verifies and installs the available update, then relaunches. Opens the release page when the app
    /// can't replace itself (read-only location).
    func install() {
        guard let found = update else { return }
        switch status {
        case .downloading, .installing: return
        default: break
        }
        let appURL = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            logger.error("app folder not writable, opening release page")
            NSWorkspace.shared.open(found.pageURL)
            return
        }
        status = .downloading(0)
        logger.info("downloading \(found.zipURL.absoluteString, privacy: .public)")
        let task = session.downloadTask(with: found.zipURL) { [weak self] location, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            var staged: URL?
            if let location = location, code == 200 {
                // The temporary file disappears when this handler returns: keep it.
                let keep = UpdateService.workDirectory().appendingPathComponent(UpdateCheck.zipName(version: found.version))
                try? FileManager.default.removeItem(at: keep)
                if (try? FileManager.default.moveItem(at: location, to: keep)) != nil { staged = keep }
            }
            DispatchQueue.main.async {
                self?.progressObservation = nil
                guard let zip = staged else {
                    self?.fail(error?.localizedDescription ?? "Download failed (\(code)).")
                    return
                }
                self?.verifyAndInstall(zip: zip, update: found, appURL: appURL)
            }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            DispatchQueue.main.async {
                if case .downloading = self?.status { self?.status = .downloading(fraction) }
            }
        }
        task.resume()
    }

    private func verifyAndInstall(zip: URL, update found: AvailableUpdate, appURL: URL) {
        status = .installing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = UpdateService.prepare(zip: zip, update: found)
            DispatchQueue.main.async {
                switch result {
                case .failure(let message):
                    self?.fail(message)
                case .success(let newApp):
                    self?.relaunch(into: newApp, replacing: appURL)
                }
            }
        }
    }

    private enum Prepared {
        case success(URL)
        case failure(String)
    }

    /// Off the main queue: digest, unzip, bundle id, version, signature and its requirement.
    private static func prepare(zip: URL, update found: AvailableUpdate) -> Prepared {
        if let expected = found.sha256 {
            guard let data = try? Data(contentsOf: zip, options: .mappedIfSafe) else { return .failure("Can't read the download.") }
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { return .failure("The download is damaged (checksum mismatch).") }
        }
        let unpack = workDirectory().appendingPathComponent("unpacked")
        try? FileManager.default.removeItem(at: unpack)
        try? FileManager.default.createDirectory(at: unpack, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpack.path]) == 0 else { return .failure("Can't unpack the download.") }
        let newApp = unpack.appendingPathComponent("DynaNotch.app")
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) else {
            return .failure("The download has no DynaNotch.app.")
        }
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else { return .failure("The download is not DynaNotch.") }
        guard let version = info["CFBundleShortVersionString"] as? String,
              AppVersion(version) == AppVersion(found.version) else {
            return .failure("The download has the wrong version.")
        }
        guard run("/usr/bin/codesign", ["--verify", "--strict", "-R=identifier \"\(bundleIdentifier)\"", newApp.path]) == 0 else {
            return .failure("The download's signature doesn't check out.")
        }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        try? FileManager.default.removeItem(at: zip)
        return .success(newApp)
    }

    /// Hands the swap to a detached shell helper (it waits for this process to exit), then quits.
    private func relaunch(into newApp: URL, replacing appURL: URL) {
        let script = UpdateService.workDirectory().appendingPathComponent("install.sh")
        let text = """
        #!/bin/sh
        # DynaNotch updater: wait for the old app to quit, swap the bundle (restore it on failure), relaunch.
        PID="$1"; OLD="$2"; NEW="$3"; BACKUP="$OLD.previous"
        i=0
        while kill -0 "$PID" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.2; i=$((i + 1)); done
        rm -rf "$BACKUP"
        if mv "$OLD" "$BACKUP" && mv "$NEW" "$OLD"; then
            rm -rf "$BACKUP"
        else
            [ -d "$BACKUP" ] && [ ! -d "$OLD" ] && mv "$BACKUP" "$OLD"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
        /usr/bin/open "$OLD"
        """
        do {
            try text.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), appURL.path, newApp.path]
            try process.run()
        } catch {
            fail("Can't start the installer: \(error.localizedDescription)")
            return
        }
        logger.info("installing \(newApp.path, privacy: .public) over \(appURL.path, privacy: .public), quitting")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    private func fail(_ message: String) {
        logger.error("update failed: \(message, privacy: .public)")
        status = .failed(message)
    }

    private static func workDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("DynaNotch/Updates")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
