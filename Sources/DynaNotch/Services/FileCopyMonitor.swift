import AppKit
import Combine
import CoreServices
import Foundation
import os
import DynaNotchCore

/// Finder copies in progress (CONTRACTS §6.12). Finder publishes an `NSProgress` for each copy, but a subscriber only
/// sees copies **into the folder it subscribed to** (macOS 27: `/` and parent folders see nothing). So, while
/// Settings → Popups → File Copies is on, it subscribes to the volume roots and the home folders, and adds folders on
/// the fly from an FSEvents stream (a copy writes into its destination folder at once, and a late subscriber still
/// receives progress that is already published).
final class FileCopyMonitor {
    static let shared = FileCopyMonitor()

    /// Main queue: the merged progress of every copy in flight; fraction 1 once the last one finishes.
    let events = PassthroughSubject<CopySummary, Never>()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "filecopy")
    private static let maxDynamic = 48

    private var started = false
    private var settingObserver: AnyCancellable?
    private var mountObservers: [AnyCancellable] = []
    private var staticSubscriptions: [String: Any] = [:]    // folder path → subscriber token
    private var dynamicSubscriptions: [String: Any] = [:]
    private var dynamicOrder: [String] = []
    private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var names: [ObjectIdentifier: String] = [:]
    private var stream: FSEventStreamRef?
    private var tracker = CopyProgressTracker()
    private var lastLabel = ""
    /// Diagnostics (state.json): progress objects Finder announced to us, and the last one's kind.
    private var announced = 0
    private var lastKind = ""

    private init() {}

    /// state.json `copy`.
    var state: [String: Any] {
        let summary = tracker.summary(now: Date())
        return [
            "active": !tracker.isEmpty,
            "label": summary?.label ?? "",
            "fraction": summary?.fraction ?? 0,
            "subscriptions": staticSubscriptions.count + dynamicSubscriptions.count,
            "watching": stream != nil,
            "announced": announced,
            "lastKind": lastKind,
        ]
    }

    func start() {
        guard !started else { return }
        started = true
        settingObserver = AppSettings.shared.$copyProgress
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in on ? self?.enable() : self?.disable() }
    }

    /// Test hook (`dynanotch://copy?name=&fraction=&left=` / `copy?done=1`): drives the pill without a real copy.
    func simulate(name: String, fraction: Double, secondsLeft: Int?) {
        events.send(CopySummary(label: name, fraction: min(max(fraction, 0), 1), secondsLeft: secondsLeft))
    }

    // MARK: Subscriptions

    private func enable() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var folders = [home]
        for dir: FileManager.SearchPathDirectory in [.desktopDirectory, .documentDirectory, .downloadsDirectory,
                                                     .moviesDirectory, .musicDirectory, .picturesDirectory] {
            if let url = fm.urls(for: dir, in: .userDomainMask).first { folders.append(url) }
        }
        folders += volumeRoots()
        for url in folders { subscribe(url, dynamic: false) }

        let center = NSWorkspace.shared.notificationCenter
        mountObservers = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification].map { name in
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refreshVolumes() }
        }
        startStream(home: home)
    }

    private func disable() {
        mountObservers = []
        stopStream()
        for token in staticSubscriptions.values { Progress.removeSubscriber(token) }
        for token in dynamicSubscriptions.values { Progress.removeSubscriber(token) }
        staticSubscriptions = [:]
        dynamicSubscriptions = [:]
        dynamicOrder = []
        observations = [:]
        names = [:]
        tracker = CopyProgressTracker()
    }

    /// Every volume under /Volumes (external drives, disk images, network shares), hidden ones included.
    private func volumeRoots() -> [URL] {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        return volumes.filter { $0.path.hasPrefix("/Volumes/") }
    }

    private func refreshVolumes() {
        let roots = Set(volumeRoots().map(\.path))
        for (path, token) in staticSubscriptions where path.hasPrefix("/Volumes/") && !roots.contains(path) {
            Progress.removeSubscriber(token)
            staticSubscriptions[path] = nil
        }
        for path in roots { subscribe(URL(fileURLWithPath: path), dynamic: false) }
        // FSEvents streams don't cross into other volumes: restart with the current roots.
        stopStream()
        startStream(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    private func subscribe(_ url: URL, dynamic: Bool) {
        let path = url.standardizedFileURL.path
        guard staticSubscriptions[path] == nil, dynamicSubscriptions[path] == nil else {
            if dynamic, let index = dynamicOrder.firstIndex(of: path) {   // keep recently active folders
                dynamicOrder.remove(at: index)
                dynamicOrder.append(path)
            }
            return
        }
        let token = Progress.addSubscriber(forFileURL: URL(fileURLWithPath: path, isDirectory: true)) { [weak self] progress in
            DispatchQueue.main.async { self?.track(progress) }
            return { [weak self] in
                DispatchQueue.main.async { self?.untrack(progress) }
            }
        }
        if dynamic {
            dynamicSubscriptions[path] = token
            dynamicOrder.append(path)
            if dynamicOrder.count > FileCopyMonitor.maxDynamic {
                let oldest = dynamicOrder.removeFirst()
                if let old = dynamicSubscriptions.removeValue(forKey: oldest) { Progress.removeSubscriber(old) }
            }
        } else {
            staticSubscriptions[path] = token
        }
    }

    // MARK: Progress

    private func track(_ progress: Progress) {
        // Finder's progress proxies leave `fileOperationKind` nil; the value is only in `userInfo`.
        let raw = progress.userInfo[.fileOperationKindKey]
        let kind = (raw as? Progress.FileOperationKind)?.rawValue ?? (raw as? String) ?? progress.fileOperationKind?.rawValue
        announced += 1
        lastKind = kind ?? "none"
        guard kind == Progress.FileOperationKind.copying.rawValue
                || kind == Progress.FileOperationKind.duplicating.rawValue else { return }
        let id = ObjectIdentifier(progress)
        guard observations[id] == nil else { return }
        let url = progress.userInfo[.fileURLKey] as? URL ?? progress.fileURL
        names[id] = url?.lastPathComponent ?? ""
        observations[id] = progress.observe(\.fractionCompleted, options: [.initial]) { [weak self] p, _ in
            let fraction = p.fractionCompleted
            DispatchQueue.main.async { self?.update(id, fraction: fraction) }
        }
    }

    private func untrack(_ progress: Progress) {
        let id = ObjectIdentifier(progress)
        guard observations.removeValue(forKey: id) != nil else { return }
        names[id] = nil
        tracker.remove(id: "\(id.hashValue)")
        if tracker.isEmpty {
            _ = tracker.shouldPublish(fraction: 1, now: Date())
            events.send(CopySummary(label: lastLabel, fraction: 1, secondsLeft: nil))
        } else {
            publish()
        }
    }

    private func update(_ id: ObjectIdentifier, fraction: Double) {
        guard observations[id] != nil else { return }
        tracker.update(id: "\(id.hashValue)", name: names[id] ?? "", fraction: fraction, now: Date())
        publish()
    }

    private func publish() {
        let now = Date()
        guard let summary = tracker.summary(now: now), summary.fraction < 1,
              tracker.shouldPublish(fraction: summary.fraction, now: now) else { return }
        lastLabel = summary.label
        events.send(summary)
    }

    // MARK: FSEvents

    private func startStream(home: URL) {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info = info else { return }
            let monitor = Unmanaged<FileCopyMonitor>.fromOpaque(info).takeUnretainedValue()
            let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
            monitor.foldersChanged(Array(list.prefix(count)))
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagIgnoreSelf)
        guard let newStream = FSEventStreamCreate(nil, callback, &context,
                                                  ([home.path] + volumeRoots().map(\.path)) as CFArray,
                                                  FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else {
            logger.error("FSEventStreamCreate failed")
            return
        }
        FSEventStreamSetExclusionPaths(newStream, [home.appendingPathComponent("Library").path] as CFArray)
        FSEventStreamSetDispatchQueue(newStream, DispatchQueue.main)
        FSEventStreamStart(newStream)
        stream = newStream
    }

    private func stopStream() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    /// Main queue (the stream's queue): subscribe to folders where something was just written.
    private func foldersChanged(_ paths: [String]) {
        for path in paths {
            let components = path.split(separator: "/")
            guard !components.contains(where: { $0.hasPrefix(".") }) else { continue }
            subscribe(URL(fileURLWithPath: path, isDirectory: true), dynamic: true)
        }
    }
}
