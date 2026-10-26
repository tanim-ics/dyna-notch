import AppKit
import Combine
import os

/// Apple Shortcuts via the `shortcuts` command-line tool.
final class ShortcutsService: ObservableObject {
    struct RunResult: Equatable {
        let name: String
        let success: Bool
        let message: String
        let date: Date
    }

    static let shared = ShortcutsService()

    @Published private(set) var shortcuts: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var running: String?
    /// Outcome of the last run (shown briefly by the tab).
    @Published private(set) var lastResult: RunResult?
    /// Set when `shortcuts list` failed (e.g. the tool is missing).
    @Published private(set) var loadError: String?
    @Published private(set) var lastLoaded: Date?

    private static let toolPath = "/usr/bin/shortcuts"
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "Shortcuts")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.shortcuts", qos: .userInitiated)

    private init() {}

    /// Refreshes the list if it was never loaded or is older than five minutes.
    func refreshIfStale() {
        if let last = lastLoaded, Date().timeIntervalSince(last) < 300 { return }
        refresh()
    }

    func refresh() {
        guard !isLoading else { return }
        guard FileManager.default.isExecutableFile(atPath: Self.toolPath) else {
            loadError = "The shortcuts command-line tool is not available"
            return
        }
        isLoading = true
        queue.async { [weak self] in
            let result = Self.execute(arguments: ["list"])
            let names = result.output
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.lastLoaded = Date()
                if result.status == 0 {
                    self.loadError = nil
                    if sorted != self.shortcuts { self.shortcuts = sorted }
                } else {
                    self.loadError = result.error.isEmpty ? "Could not list shortcuts" : result.error
                    self.logger.error("shortcuts list failed: \(result.error, privacy: .public)")
                }
            }
        }
    }

    func run(_ name: String) {
        guard running == nil else { return }
        running = name
        lastResult = nil
        queue.async { [weak self] in
            let result = Self.execute(arguments: ["run", name])
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.running = nil
                let ok = result.status == 0
                let message: String
                if ok {
                    let out = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = out.isEmpty ? "Done" : String(out.prefix(120))
                } else {
                    message = result.error.isEmpty ? "Failed" : String(result.error.prefix(120))
                    self.logger.error("shortcut \(name, privacy: .public) failed: \(result.error, privacy: .public)")
                }
                self.lastResult = RunResult(name: name, success: ok, message: message, date: Date())
            }
        }
    }

    /// Opens the Shortcuts app (optionally at a shortcut) for editing.
    func openInShortcutsApp(_ name: String? = nil) {
        if let name = name,
           let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "shortcuts://open-shortcut?name=\(encoded)") {
            Self.open(url)
        } else if let url = URL(string: "shortcuts://") {
            Self.open(url)
        }
    }

    func search(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return shortcuts }
        return shortcuts.filter { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    // MARK: - Private

    private static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static func execute(arguments: [String]) -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }
        // Read before waiting so a large output cannot fill the pipe and deadlock.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus,
                String(decoding: outData, as: UTF8.self),
                String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
