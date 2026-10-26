import AppKit
import Combine
import os

struct LaunchableApp: Identifiable, Equatable {
    var id: String { bundleID ?? url.path }
    let name: String
    let bundleID: String?
    let url: URL
}

/// Pinned apps (settings.launcherApps), running apps and a searchable list of installed apps.
final class LauncherService: ObservableObject {
    static let shared = LauncherService()

    @Published private(set) var pinned: [LaunchableApp] = []
    @Published private(set) var running: [LaunchableApp] = []
    @Published private(set) var installed: [LaunchableApp] = []

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "Launcher")
    private let scanQueue = DispatchQueue(label: "com.tanim.dynanotch.launcher", qos: .utility)
    private var cancellables = Set<AnyCancellable>()
    private var iconCache: [String: NSImage] = [:]
    private var started = false
    private var isScanning = false
    private var lastScan: Date?

    private init() {}

    /// Idempotent; later calls (e.g. each time the tab appears) re-index installed apps every 10 minutes.
    func start() {
        guard !started else {
            if let last = lastScan, Date().timeIntervalSince(last) > 600 { scanInstalled() }
            return
        }
        started = true

        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didLaunchApplicationNotification,
                                          NSWorkspace.didTerminateApplicationNotification]
        for name in names {
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshRunning() }
                .store(in: &cancellables)
        }
        AppSettings.shared.$launcherApps
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.refreshPinned(value) }
            .store(in: &cancellables)

        refresh()
    }

    func refresh() {
        refreshRunning()
        refreshPinned(AppSettings.shared.launcherApps)
        scanInstalled()
    }

    func search(_ query: String) -> [LaunchableApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let matches = installed.filter { $0.name.lowercased().contains(q) }
        return matches.sorted { lhs, rhs in
            let lp = lhs.name.lowercased().hasPrefix(q)
            let rp = rhs.name.lowercased().hasPrefix(q)
            if lp != rp { return lp }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func launch(_ app: LaunchableApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let name = app.name
        let logger = self.logger
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { _, error in
            if let error = error {
                logger.error("Launching \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func isPinned(_ app: LaunchableApp) -> Bool {
        guard let id = app.bundleID else { return false }
        return pinnedIDs(AppSettings.shared.launcherApps).contains(id)
    }

    func togglePin(_ app: LaunchableApp) {
        guard let id = app.bundleID else { return }
        var ids = pinnedIDs(AppSettings.shared.launcherApps)
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        AppSettings.shared.launcherApps = ids.joined(separator: ",")
    }

    func icon(for app: LaunchableApp) -> NSImage {
        if let cached = iconCache[app.url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        image.size = NSSize(width: 64, height: 64)
        iconCache[app.url.path] = image
        return image
    }

    // MARK: - Private

    private func pinnedIDs(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func refreshPinned(_ value: String) {
        let apps: [LaunchableApp] = pinnedIDs(value).compactMap { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return Self.makeApp(url: url, bundleID: id)
        }
        if apps != pinned { pinned = apps }
    }

    private func refreshRunning() {
        let ownID = Bundle.main.bundleIdentifier
        let apps: [LaunchableApp] = NSWorkspace.shared.runningApplications.compactMap { running in
            guard running.activationPolicy == .regular, let url = running.bundleURL,
                  running.bundleIdentifier != ownID else { return nil }
            let name = running.localizedName ?? url.deletingPathExtension().lastPathComponent
            return LaunchableApp(name: name, bundleID: running.bundleIdentifier, url: url)
        }
        if apps != running { running = apps }
    }

    private func scanInstalled() {
        guard !isScanning else { return }
        isScanning = true
        scanQueue.async { [weak self] in
            let apps = Self.scanApplications()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isScanning = false
                self.lastScan = Date()
                if apps != self.installed { self.installed = apps }
                self.logger.debug("Indexed \(apps.count) applications")
            }
        }
    }

    private static func scanApplications() -> [LaunchableApp] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [URL(fileURLWithPath: "/Applications"),
                     URL(fileURLWithPath: "/System/Applications"),
                     URL(fileURLWithPath: "/System/Applications/Utilities"),
                     URL(fileURLWithPath: "/Applications/Utilities"),
                     home.appendingPathComponent("Applications")]
        var seen = Set<String>()
        var result: [LaunchableApp] = []
        for root in roots {
            for url in appBundles(in: root, depth: 1) {
                let bundleID = Bundle(url: url)?.bundleIdentifier
                let key = bundleID ?? url.path
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                result.append(makeApp(url: url, bundleID: bundleID))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// `.app` bundles directly in `root`, plus one level of plain sub-folders (e.g. "/Applications/Adobe …").
    private static func appBundles(in root: URL, depth: Int) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                        options: [.skipsHiddenFiles]) else { return [] }
        var urls: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                urls.append(entry)
            } else if depth > 0, entry.lastPathComponent != "Utilities",
                      (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                urls.append(contentsOf: appBundles(in: entry, depth: depth - 1))
            }
        }
        return urls
    }

    private static func makeApp(url: URL, bundleID: String?) -> LaunchableApp {
        let name = FileManager.default.displayName(atPath: url.path)
        let clean = name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        return LaunchableApp(name: clean, bundleID: bundleID, url: url)
    }
}
