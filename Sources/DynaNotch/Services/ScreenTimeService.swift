import AppKit
import Combine
import DynaNotchCore

struct AppUsage: Identifiable, Equatable {
    var id: String { bundleID }
    let bundleID: String
    let name: String
    let seconds: TimeInterval
}

/// Time per frontmost app today (local only, pauses while locked / asleep / idle > 2 min).
/// Persisted to App Support `screentime.json`, 14 days kept.
final class ScreenTimeService: ObservableObject {
    static let shared = ScreenTimeService()

    @Published private(set) var ledger = ScreenTimeLedger()

    private static let file = "screentime.json"
    private static let idleLimit: TimeInterval = 120
    private static let keepDays = 14

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    /// App currently being timed and when its current span started (nil = not counting).
    private var currentApp: (bundleID: String, name: String)?
    private var spanStart: Date?
    private var unsavedChanges = 0
    private var iconCache: [String: NSImage] = [:]

    private init() {
        if let saved = AppDataStore.loadFile(ScreenTimeLedger.self, file: ScreenTimeService.file) {
            ledger = saved
        }
    }

    func start() {
        guard !started else { return }
        started = true
        UserPresence.shared.start()
        var pruned = ledger
        pruned.prune(keepDays: ScreenTimeService.keepDays, now: Date())
        if pruned != ledger { ledger = pruned }

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.switchTo(app)
            }
            .store(in: &cancellables)

        Timer.publish(every: 10, tolerance: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.flush() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.flush()
                self?.save()
            }
            .store(in: &cancellables)

        switchTo(NSWorkspace.shared.frontmostApplication)
    }

    func clear() {
        ledger = ScreenTimeLedger()
        spanStart = currentApp == nil ? nil : Date()
        save()
    }

    func today(limit: Int = 5) -> [AppUsage] {
        ledger.top(on: Date(), limit: limit).map { entry in
            AppUsage(bundleID: entry.app, name: ledger.names[entry.app] ?? ScreenTimeService.fallbackName(entry.app),
                     seconds: entry.seconds)
        }
    }

    func totalToday() -> TimeInterval {
        ledger.total(on: Date())
    }

    func icon(for bundleID: String) -> NSImage? {
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = image
        return image
    }

    // MARK: Private (main queue)

    private var isCounting: Bool {
        let presence = UserPresence.shared
        return AppSettings.shared.screenTimeEnabled && !presence.isAway && presence.idleSeconds < ScreenTimeService.idleLimit
    }

    private func switchTo(_ app: NSRunningApplication?) {
        flush()
        if let app = app, let bundleID = app.bundleIdentifier {
            currentApp = (bundleID, app.localizedName ?? ScreenTimeService.fallbackName(bundleID))
            spanStart = isCounting ? Date() : nil
        } else {
            currentApp = nil
            spanStart = nil
        }
    }

    /// Records the span since the last flush for the current app, then starts a new span (or pauses).
    private func flush() {
        let now = Date()
        if let app = currentApp, let start = spanStart {
            var updated = ledger
            // While idle, credit nothing beyond the moment the user stopped interacting.
            let idle = UserPresence.shared.idleSeconds
            let end = idle >= ScreenTimeService.idleLimit ? max(start, now.addingTimeInterval(-idle)) : now
            updated.record(app: app.bundleID, name: app.name, from: start, to: end)
            if updated != ledger {
                ledger = updated
                unsavedChanges += 1
            }
        }
        spanStart = (currentApp != nil && isCounting) ? now : nil
        if unsavedChanges >= 6 { save() }   // about once a minute while in use
    }

    private func save() {
        unsavedChanges = 0
        var pruned = ledger
        pruned.prune(keepDays: ScreenTimeService.keepDays, now: Date())
        if pruned != ledger { ledger = pruned }
        AppDataStore.saveFile(pruned, file: ScreenTimeService.file)
    }

    private static func fallbackName(_ bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
