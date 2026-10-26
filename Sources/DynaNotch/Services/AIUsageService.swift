import Combine
import Darwin
import Foundation
import os
import DynaNotchCore

/// Local Claude Code / Codex usage, parsed from their transcript files on a background queue.
final class AIUsageService: ObservableObject {
    static let shared = AIUsageService()

    @Published private(set) var claudeBlock: UsageBlock?
    @Published private(set) var claudeToday: (usage: TokenUsage, cost: Double, count: Int)?
    @Published private(set) var claudeWeek: (usage: TokenUsage, cost: Double, count: Int)?
    /// Largest token total of any finished 5-hour block (a practical "limit" for the progress bar).
    @Published private(set) var claudeMaxBlockTokens: Int = 0
    @Published private(set) var codex: CodexRateLimits?
    @Published private(set) var hasClaudeData = false
    @Published private(set) var hasCodexData = false
    @Published private(set) var lastUpdated: Date?

    // MARK: Background state (touched only on `queue`)

    private struct FileState {
        var readOffset: UInt64      // bytes consumed so far (including `partial`)
        var partial = Data()        // trailing bytes without a newline yet
        var entries: [UsageEntry] = []
    }

    private struct CodexFileKey: Equatable {
        var path: String
        var size: UInt64
        var modified: Date
    }

    private typealias Summary = (usage: TokenUsage, cost: Double, count: Int)

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "aiusage")
    private let queue = DispatchQueue(label: "com.tanim.dynanotch.aiusage", qos: .utility)
    private var started = false                       // main queue
    private var timer: AnyCancellable?                // main queue

    private var files: [String: FileState] = [:]
    private var blocks: [UsageBlock] = []
    private var allEntries: [UsageEntry] = []
    private var summaries: (today: Summary, week: Summary)?
    private var summariesComputedAt = Date.distantPast
    private var summariesDay: Date?
    private var codexKeys: [CodexFileKey] = []
    private var codexValue: CodexRateLimits?
    private var isRefreshing = false

    private static let retention: TimeInterval = 8 * 86_400
    private static let codexWindow: TimeInterval = 7 * 86_400
    private static let codexTailBytes: UInt64 = 512 * 1024
    private static let summaryMaxAge: TimeInterval = 5 * 60

    private init() {}

    // MARK: Public API

    func start() {
        guard !started else { return }
        started = true
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        refresh()
    }

    func refresh() {
        queue.async { [weak self] in
            self?.performRefresh()
        }
    }

    // MARK: Refresh (queue)

    private func performRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let claudeChanged = scanClaude(now: now)
        if claudeChanged {
            let cutoff = now.addingTimeInterval(-AIUsageService.retention)
            allEntries = files.values.flatMap { $0.entries }.filter { $0.timestamp >= cutoff }
            blocks = UsageAggregator.blocks(allEntries)
        }

        let startOfDay = Calendar.current.startOfDay(for: now)
        if claudeChanged || summaries == nil || summariesDay != startOfDay
            || now.timeIntervalSince(summariesComputedAt) >= AIUsageService.summaryMaxAge {
            let today = UsageAggregator.summary(allEntries, from: startOfDay, to: .distantFuture)
            let week = UsageAggregator.summary(allEntries, from: now.addingTimeInterval(-7 * 86_400), to: .distantFuture)
            summaries = (today, week)
            summariesComputedAt = now
            summariesDay = startOfDay
        }

        let active: UsageBlock? = blocks.last.flatMap { $0.isActive(now: now) ? $0 : nil }
        let finished = active == nil ? blocks : Array(blocks.dropLast())
        let maxTokens = finished.map { $0.usage.total }.max() ?? 0
        let hasClaude = !allEntries.isEmpty
        let today: Summary? = hasClaude ? summaries?.today : nil
        let week: Summary? = hasClaude ? summaries?.week : nil

        scanCodex(now: now)
        let codexResult = codexValue

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.claudeBlock != active { self.claudeBlock = active }
            if !AIUsageService.same(self.claudeToday, today) { self.claudeToday = today }
            if !AIUsageService.same(self.claudeWeek, week) { self.claudeWeek = week }
            if self.claudeMaxBlockTokens != maxTokens { self.claudeMaxBlockTokens = maxTokens }
            if self.hasClaudeData != hasClaude { self.hasClaudeData = hasClaude }
            if self.codex != codexResult { self.codex = codexResult }
            if self.hasCodexData != (codexResult != nil) { self.hasCodexData = codexResult != nil }
            self.lastUpdated = now
        }
    }

    private static func same(_ a: Summary?, _ b: Summary?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return x.usage == y.usage && x.cost == y.cost && x.count == y.count
        default: return false
        }
    }

    // MARK: Claude Code

    private static func claudeRoots() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var candidates = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            for part in env.split(separator: ",") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let expanded = (trimmed as NSString).expandingTildeInPath
                candidates.append(URL(fileURLWithPath: expanded).appendingPathComponent("projects"))
            }
        }
        var seen = Set<String>()
        var roots: [URL] = []
        for url in candidates {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if seen.insert(resolved.path).inserted { roots.append(resolved) }
        }
        return roots
    }

    /// Returns true when any entry was added or removed.
    private func scanClaude(now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-AIUsageService.retention)
        var current: [String: UInt64] = [:]   // path → size
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        for root in AIUsageService.claudeRoots() {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles],
                                                                  errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= cutoff else { continue }
                current[url.path] = UInt64(max(values.fileSize ?? 0, 0))
            }
        }

        var changed = false
        for path in files.keys where current[path] == nil {
            files.removeValue(forKey: path)
            changed = true
        }
        for (path, size) in current {
            if var state = files[path] {
                if size == state.readOffset { continue }
                if size < state.readOffset {
                    state = FileState(readOffset: 0)   // truncated / rewritten → reparse
                    changed = true
                }
                if readAppended(path: path, size: size, state: &state) { changed = true }
                files[path] = state
            } else {
                var state = FileState(readOffset: 0)
                _ = readAppended(path: path, size: size, state: &state)
                files[path] = state
                changed = true
            }
        }

        if changed {
            for (path, state) in files {
                let kept = state.entries.filter { $0.timestamp >= cutoff }
                if kept.count != state.entries.count { files[path]?.entries = kept }
            }
        }
        return changed
    }

    /// Reads bytes from `readOffset` to EOF, parses complete lines. Returns true when new entries were found.
    private func readAppended(path: String, size: UInt64, state: inout FileState) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let data: Data
        do {
            try handle.seek(toOffset: state.readOffset)
            data = try handle.readToEnd() ?? Data()
        } catch {
            logger.debug("could not read \(path, privacy: .private): \(error.localizedDescription, privacy: .public)")
            return false
        }
        guard !data.isEmpty else { return false }
        state.readOffset += UInt64(data.count)

        var buffer = state.partial
        buffer.append(data)
        var parsed: [UsageEntry] = []
        var consumed = 0
        buffer.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let total = raw.count
            var lineStart = 0
            while lineStart < total {
                guard let hit = memchr(base + lineStart, 0x0A, total - lineStart) else { break }
                let lineEnd = base.distance(to: UnsafeRawPointer(hit))
                if lineEnd > lineStart {
                    let line = UnsafeRawBufferPointer(start: base + lineStart, count: lineEnd - lineStart)
                    if let entry = AIUsageService.parseClaudeLine(line) { parsed.append(entry) }
                }
                lineStart = lineEnd + 1
            }
            consumed = lineStart
        }
        state.partial = consumed < buffer.count ? buffer.subdata(in: consumed..<buffer.count) : Data()
        state.entries.append(contentsOf: parsed)
        let found = !parsed.isEmpty
        return found
    }

    private static func parseClaudeLine(_ bytes: UnsafeRawBufferPointer) -> UsageEntry? {
        let line = String(decoding: bytes, as: UTF8.self)
        // Cheap pre-filter: only assistant messages carry usage.
        guard line.contains("\"usage\"") else { return nil }
        return ClaudeUsageParser.parse(line: line)
    }

    // MARK: Codex

    private func scanCodex(now: Date) {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            codexKeys = []
            codexValue = nil
            return
        }
        let cutoff = now.addingTimeInterval(-AIUsageService.codexWindow)
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var candidates: [CodexFileKey] = []
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                           options: [.skipsHiddenFiles],
                                                           errorHandler: { _, _ in true }) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                guard name.hasPrefix("rollout-"), url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= cutoff else { continue }
                candidates.append(CodexFileKey(path: url.path, size: UInt64(max(values.fileSize ?? 0, 0)), modified: modified))
            }
        }
        candidates.sort { $0.modified > $1.modified }
        let newest = Array(candidates.prefix(5))
        if newest == codexKeys { return }   // nothing changed since last time
        codexKeys = newest

        var result: CodexRateLimits?
        for file in newest {
            if let limits = lastCodexLimits(path: file.path, size: file.size) {
                result = limits
                break
            }
        }
        codexValue = result
    }

    private func lastCodexLimits(path: String, size: UInt64) -> CodexRateLimits? {
        guard size > 0, let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let start = size > AIUsageService.codexTailBytes ? size - AIUsageService.codexTailBytes : 0
        let data: Data
        do {
            try handle.seek(toOffset: start)
            data = try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }
        let text = String(decoding: data, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }   // first line is probably cut
        for line in lines.reversed() where line.contains("rate_limits") {
            if let limits = CodexUsageParser.parse(line: String(line)) { return limits }
        }
        return nil
    }
}
