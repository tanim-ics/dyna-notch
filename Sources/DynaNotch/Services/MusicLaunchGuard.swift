import AppKit
import Combine
import os

/// With `settings.preventMusicAutoLaunch`, quits Music.app when macOS launches it on its own (a play key with no
/// player running, headphones connecting) instead of the user opening it.
///
/// Heuristic (deliberately conservative): a launch the user started makes Music the active app right away
/// (Dock, Spotlight, Launchpad, Finder). An automatic launch stays in the background. So Music is quit only if it
/// is still not active and owns no menu bar 1 s *and* 2.5 s after launching. If it ever becomes frontmost in that
/// window, it is left alone for good.
final class MusicLaunchGuard {
    static let shared = MusicLaunchGuard()

    static let musicBundleID = "com.apple.Music"

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "musicguard")
    private var started = false
    private var cancellables = Set<AnyCancellable>()
    /// Process ids of Music launches the user brought to the front (never quit those).
    private var spared = Set<pid_t>()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.launched(app)
            }
            .store(in: &cancellables)
        center.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == MusicLaunchGuard.musicBundleID else { return }
                self?.spared.insert(app.processIdentifier)
            }
            .store(in: &cancellables)
    }

    // MARK: Private (main queue)

    /// Settings → Now Playing → Default music app (bundle id; empty or Music = Apple Music).
    static var defaultPlayerBundleID: String? {
        let id = AppSettings.shared.defaultMusicApp.trimmingCharacters(in: .whitespaces)
        return id.isEmpty || id == musicBundleID ? nil : id
    }

    /// Opens the default music app (used when a play key finds nothing playing). Returns false when none is set or
    /// it is not installed.
    @discardableResult
    func openDefaultPlayer() -> Bool {
        guard let id = MusicLaunchGuard.defaultPlayerBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return false }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            running.activate()
            return true
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            if let error = error {
                self?.logger.error("default player launch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        logger.info("opened default player \(id, privacy: .public)")
        return true
    }

    private func launched(_ app: NSRunningApplication) {
        guard app.bundleIdentifier == MusicLaunchGuard.musicBundleID else { return }
        // With another default music app, an automatic Music launch (play key, nothing playing) is swapped for it.
        let swapToDefault = MusicLaunchGuard.defaultPlayerBundleID != nil
            && NSWorkspace.shared.urlForApplication(withBundleIdentifier: MusicLaunchGuard.defaultPlayerBundleID ?? "") != nil
        guard AppSettings.shared.preventMusicAutoLaunch || swapToDefault else { return }
        let pid = app.processIdentifier
        if app.isActive { spared.insert(pid) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.looksAutomatic(app) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self, self.looksAutomatic(app) else { return }
                let swap = MusicLaunchGuard.defaultPlayerBundleID != nil
                guard AppSettings.shared.preventMusicAutoLaunch || swap else { return }
                self.logger.info("Music.app launched in the background — quitting it")
                app.terminate()
                self.spared.remove(pid)
                if swap { self.openDefaultPlayer() }
            }
        }
    }

    private func looksAutomatic(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        if spared.contains(pid) || app.isTerminated { return false }
        if app.isActive || app.ownsMenuBar {
            spared.insert(pid)
            return false
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            spared.insert(pid)
            return false
        }
        return true
    }
}
