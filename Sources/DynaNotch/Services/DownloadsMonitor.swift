import Combine
import Foundation
import os
import DynaNotchCore

/// Watches ~/Downloads for browser partial files appearing (started) and completing (finished).
/// While `AppSettings.shared.downloadActivity` is on, a file-system event source on the folder triggers a re-scan
/// (entries added / removed / renamed); a 30 s poll is only a safety net. Listing runs off the main thread.
final class DownloadsMonitor {
    static let shared = DownloadsMonitor()

    let events = PassthroughSubject<(name: String, finished: Bool), Never>()

    private let queue = DispatchQueue(label: "com.tanim.dynanotch.downloads", qos: .utility)
    private var started = false                     // main queue
    private var settingObserver: AnyCancellable?    // main queue
    private var timer: AnyCancellable?              // main queue
    private var folderSource: DispatchSourceFileSystemObject?   // main queue
    private var scanPending = false                 // queue only
    private var tracker = DownloadTracker()         // queue only

    private static var downloadsURL: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        settingObserver = AppSettings.shared.$downloadActivity
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in self?.setPolling(enabled) }
    }

    // MARK: Private

    private func setPolling(_ on: Bool) {
        if on {
            guard timer == nil else { return }
            queue.async { [weak self] in self?.tracker = DownloadTracker() }   // re-seed: no events for old files
            timer = Timer.publish(every: 30, tolerance: 5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.scheduleScan() }
            watchFolder()
            scheduleScan()
        } else {
            timer?.cancel()
            timer = nil
            folderSource?.cancel()
            folderSource = nil
        }
    }

    /// Directory vnode events: a download starting, being renamed when it finishes, or removed.
    private func watchFolder() {
        let fd = open(DownloadsMonitor.downloadsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                               queue: queue)
        source.setEventHandler { [weak self] in
            // Coalesce bursts (browsers touch the folder several times per download).
            guard let self = self, !self.scanPending else { return }
            self.scanPending = true
            self.queue.asyncAfter(deadline: .now() + 0.3) {
                self.scanPending = false
                self.scan()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        folderSource = source
    }

    private func scheduleScan() {
        queue.async { [weak self] in self?.scan() }
    }

    private func scan() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: DownloadsMonitor.downloadsURL.path) else {
            return
        }
        let result = tracker.update(Set(names))
        guard !result.started.isEmpty || !result.finished.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.timer != nil else { return }
            for name in result.started { self.events.send((name: DownloadNames.finalName(name), finished: false)) }
            for name in result.finished { self.events.send((name: name, finished: true)) }
        }
    }
}
