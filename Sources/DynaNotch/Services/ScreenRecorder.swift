import AppKit
import Combine
import CoreGraphics
import Foundation
import os
import DynaNotchCore

/// Screen recording through `/usr/sbin/screencapture -v` (whole screen) or `-v -i -s` (dragged area).
/// screencapture records until it reads a character on stdin or gets SIGINT ("type any character or ctrl-c to stop"),
/// so stdin is a pipe we keep open and Stop sends SIGINT. Movies go to the screenshot folder, else ~/Movies.
final class ScreenRecorder: ObservableObject {
    static let shared = ScreenRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var startedAt: Date?

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "recorder")
    private var task: Process?
    private var stdinPipe: Pipe?

    private init() {}

    /// Starts a recording (no-op while one is running). Runs screencapture on a background queue.
    func start(area: Bool) {
        guard !isRecording else { return }
        // screencapture runs as our child, so it needs DynaNotch's Screen Recording permission.
        guard CGPreflightScreenCaptureAccess() else {
            logger.info("screen recording permission missing — requesting")
            // First time: the system prompt. Afterwards it stays silent, so open the Settings pane too.
            if !CGRequestScreenCaptureAccess() { Permissions.openScreenRecordingSettings() }
            ScreenRecorder.notify(title: "Allow Screen Recording",
                                  body: "System Settings › Privacy & Security › Screen Recording › DynaNotch",
                                  symbol: "record.circle")
            return
        }
        let directory = QuickActions.customFolder() ?? ScreenRecorder.moviesDirectory
        let url = directory.appendingPathComponent(QuickActions.timestampedName("Screen Recording") + ".mov")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = area ? ["-v", "-i", "-s", url.path] : ["-v", url.path]
        let pipe = Pipe()
        task.standardInput = pipe
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        self.task = task
        stdinPipe = pipe
        isRecording = true
        startedAt = Date()
        // Let the panel collapse first so it is not in the first frames.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, self.task === task else { return }   // stopped before it began
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try task.run()
            } catch {
                self.logger.error("screencapture -v failed: \(error.localizedDescription, privacy: .public)")
                self.finish(url: url)
                return
            }
            self.logger.info("recording started (area: \(area, privacy: .public))")
            if !area {
                ScreenRecorder.notify(title: "Recording Screen", body: "Stop it from ⋯ › Stop Recording",
                                      symbol: "record.circle")
            }
            DispatchQueue.global(qos: .utility).async {
                task.waitUntilExit()
                DispatchQueue.main.async { self.finish(url: url) }   // singleton
            }
        }
    }

    /// Stops the running recording; screencapture writes the movie and exits.
    func stop() {
        guard let task = task else { return }
        if task.isRunning {
            task.interrupt()   // SIGINT = ctrl-c: screencapture finalises the file
            // Still running (e.g. stuck in the selection UI)? Terminate.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak task] in
                if let task = task, task.isRunning { task.terminate() }
            }
        } else {
            finish(url: nil)
        }
    }

    // MARK: Private (main queue)

    private func finish(url: URL?) {
        guard isRecording else { return }
        try? stdinPipe?.fileHandleForWriting.close()
        stdinPipe = nil
        task = nil
        isRecording = false
        startedAt = nil
        guard let url = url, FileManager.default.fileExists(atPath: url.path) else {
            logger.info("recording cancelled or produced no file")
            return
        }
        logger.info("recording saved to \(url.path, privacy: .public)")
        if AppSettings.shared.screenshotToShelf { ShelfService.shared.add(urls: [url]) }
        ScreenRecorder.notify(title: "Recording Saved", body: url.lastPathComponent, symbol: "film")
    }

    private static var moviesDirectory: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies", isDirectory: true)
    }

    /// Posts an app notification island (not gated by the public `dynanotch://notify` toggle).
    /// `category` (userInfo "category", an `AlertCategory` raw value) picks the alert sound; default Notifications.
    static func notify(title: String, body: String, symbol: String, category: AlertCategory? = nil) {
        var info: [String: Any] = ["title": title, "body": body, "symbol": symbol]
        if let category = category { info["category"] = category.rawValue }
        NotificationCenter.default.post(name: .dynaNotchAppNotification, object: nil, userInfo: info)
    }
}

extension Notification.Name {
    /// Services → view model: show a notification island (userInfo: title, body, symbol).
    static let dynaNotchAppNotification = Notification.Name("DynaNotch.appNotification")
}
