import AppKit
import Darwin
import Foundation
import os
import DynaNotchCore

/// Drop Alchemy (CONTRACTS §6.15): turns a file into a cutout, its text, a smaller copy or another format — all on
/// this Mac. New files go next to the original and onto the shelf; text goes to the clipboard.
final class AlchemyService {
    static let shared = AlchemyService()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "alchemy")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.alchemy", qos: .userInitiated)
    private(set) var running = 0          // main queue
    private(set) var last = "none"        // main queue

    private struct Failure: Error { let message: String }

    private init() {}

    /// state.json `alchemy`.
    var state: [String: Any] { ["running": running, "last": last] }

    func run(_ action: AlchemyAction, on url: URL) {
        guard action.accepts(fileExtension: url.pathExtension) else {
            finish(action, url, .failure(Failure(message: "\(action.title) works on images\(action == .text || action == .shrink ? " and PDFs" : "")")))
            return
        }
        running += 1
        queue.async { [weak self] in
            guard let self = self else { return }
            let result: Result<String, Error>
            do {
                result = .success(try self.perform(action, on: url))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { self.finish(action, url, result) }
        }
    }

    // MARK: Main queue

    private func finish(_ action: AlchemyAction, _ url: URL, _ result: Result<String, Error>) {
        if running > 0 { running -= 1 }
        switch result {
        case .success(let output):
            if action == .text {
                ClipboardService.shared.copyText(output)
                let count = output.count
                last = "text \(count) chars from \(url.lastPathComponent)"
                ScreenRecorder.notify(title: count == 0 ? "No text found" : "Text copied",
                                      body: count == 0 ? url.lastPathComponent : "\(count) characters from \(url.lastPathComponent)",
                                      symbol: "text.viewfinder", category: .downloads)
            } else {
                let out = URL(fileURLWithPath: output)
                ShelfService.shared.add(urls: [out])
                last = "\(action.rawValue) → \(out.lastPathComponent)"
                ScreenRecorder.notify(title: action.detail, body: out.lastPathComponent, symbol: action.symbol,
                                      category: .downloads)
            }
        case .failure(let error):
            let message = (error as? Failure)?.message ?? error.localizedDescription
            last = "failed \(action.rawValue): \(message)"
            logger.error("alchemy \(action.rawValue, privacy: .public) failed: \(message, privacy: .private)")
            ScreenRecorder.notify(title: "\(action.title) didn't work", body: message, symbol: "exclamationmark.triangle.fill")
        }
    }

    // MARK: Work (utility queue)

    /// Returns the output path, or the text for `.text`. The file is decoded by `DynaNotchWorker` inside a sandbox
    /// (docs/SECURITY.md): an image or PDF that exploits a decoder can't touch the app or its permissions.
    private func perform(_ action: AlchemyAction, on url: URL) throws -> String {
        let fm = FileManager.default
        let scratch = URL(fileURLWithPath: AlchemyService.realPath(NSTemporaryDirectory()), isDirectory: true)
            .appendingPathComponent("DynaNotchWorker-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        let result = try runWorker(action: action, input: URL(fileURLWithPath: AlchemyService.realPath(url.path)),
                                   scratch: scratch)
        if action == .text { return result }
        let produced = URL(fileURLWithPath: result)
        guard produced.deletingLastPathComponent().standardizedFileURL == scratch.standardizedFileURL,
              fm.fileExists(atPath: produced.path) else { throw Failure(message: "The worker made no file") }
        let folder = url.deletingLastPathComponent()
        let existing = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        let keepsAlpha = action == .shrink && produced.pathExtension == "png"
        guard let name = action.outputName(for: url.lastPathComponent, existing: existing, keepsTransparency: keepsAlpha) else {
            throw Failure(message: "No output name")
        }
        let out = folder.appendingPathComponent(name)
        try fm.moveItem(at: produced, to: out)
        return out.path
    }

    /// Runs the worker (sandboxed when `sandbox-exec` exists) and returns its stdout; 60 s at most.
    private func runWorker(action: AlchemyAction, input: URL, scratch: URL) throws -> String {
        guard let worker = AlchemyService.workerURL else { throw Failure(message: "DynaNotchWorker is missing") }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent("DynaNotchWorker", isDirectory: true) }
            ?? scratch.appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let workerArgs = ["alchemy", action.rawValue, input.path, scratch.path]
        let process = Process()
        let sandbox = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        if FileManager.default.isExecutableFile(atPath: sandbox.path) {
            process.executableURL = sandbox
            process.arguments = WorkerSandbox.arguments(
                worker: AlchemyService.realPath(worker.path), input: input.path, tmp: scratch.path,
                cache: AlchemyService.realPath(cache.path), home: AlchemyService.realPath(NSHomeDirectory()),
                workerArguments: workerArgs)
        } else {
            logger.error("sandbox-exec missing: worker runs unsandboxed (still out of process)")
            process.executableURL = worker
            process.arguments = workerArgs
        }
        var env = ProcessInfo.processInfo.environment
        env["TMPDIR"] = scratch.path + "/"
        process.environment = env
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: killer)
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let errors = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let message = String(decoding: errors.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: message.isEmpty ? "The file couldn't be processed" : message)
        }
        return String(decoding: output, as: UTF8.self)
    }

    /// `Contents/MacOS/DynaNotchWorker` next to the app's executable.
    private static var workerURL: URL? {
        guard let exe = Bundle.main.executableURL else { return nil }
        let url = exe.deletingLastPathComponent().appendingPathComponent("DynaNotchWorker")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// The sandbox compares resolved paths (/var → /private/var, symlinks followed).
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
