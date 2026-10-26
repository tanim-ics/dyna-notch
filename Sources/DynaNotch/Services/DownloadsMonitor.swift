import Combine
import Foundation
import os
import DynaNotchCore

/// Watches ~/Downloads for browser partial files appearing (started) and completing (finished).
/// Polls once per second while `AppSettings.shared.downloadActivity` is on; listing runs off the main thread.
final class DownloadsMonitor {
    static let shared = DownloadsMonitor()

    let events = PassthroughSubject<(name: String, finished: Bool), Never>()

    private let queue = DispatchQueue(label: "com.tanim.dynanotch.downloads", qos: .utility)
    private var started = false                     // main queue
    private var settingObserver: AnyCancellable?    // main queue
    private var timer: AnyCancellable?              // main queue
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
            timer = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.scheduleScan() }
            scheduleScan()
        } else {
            timer?.cancel()
            timer = nil
        }
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
