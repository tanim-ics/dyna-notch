import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct TokenUsage: Equatable {
    public var input: Int
    public var output: Int
    public var cacheCreation: Int
    public var cacheRead: Int

    public init(input: Int = 0, output: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
    }

    public static let zero = TokenUsage()

    public var total: Int { input + output + cacheCreation + cacheRead }

    public static func + (l: TokenUsage, r: TokenUsage) -> TokenUsage {
        TokenUsage(input: l.input + r.input, output: l.output + r.output,
                   cacheCreation: l.cacheCreation + r.cacheCreation, cacheRead: l.cacheRead + r.cacheRead)
    }
}

public struct UsageEntry: Equatable {
    public var timestamp: Date
    public var model: String
    public var usage: TokenUsage
    /// message.id + ":" + requestId — Claude Code logs one line per content block of the same message.
    public var dedupeKey: String?

    public init(timestamp: Date, model: String, usage: TokenUsage, dedupeKey: String?) {
        self.timestamp = timestamp
        self.model = model
        self.usage = usage
        self.dedupeKey = dedupeKey
    }
}

enum JSONValue {
    static func int(_ any: Any?) -> Int {
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String, let n = Int(s) { return n }
        return 0
    }

    static func double(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    static func isoDate(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    static func object(line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return obj as? [String: Any]
    }
}

public enum ClaudeUsageParser {
    /// One line of a Claude Code transcript (`~/.claude/projects/**/*.jsonl`); only assistant lines with usage count.
    public static func parse(line: String) -> UsageEntry? {
        // Cheap pre-filter: most lines are user/tool lines.
        guard line.contains("\"usage\""), line.contains("assistant"),
              let dict = JSONValue.object(line: line),
              dict["type"] as? String == "assistant",
              let message = dict["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let timestamp = JSONValue.isoDate(dict["timestamp"]) else { return nil }
        let tokens = TokenUsage(input: JSONValue.int(usage["input_tokens"]),
                                output: JSONValue.int(usage["output_tokens"]),
                                cacheCreation: JSONValue.int(usage["cache_creation_input_tokens"]),
                                cacheRead: JSONValue.int(usage["cache_read_input_tokens"]))
        guard tokens.total > 0 else { return nil }
        let model = message["model"] as? String ?? "unknown"
        if model == "<synthetic>" { return nil }
        var key: String?
        if let id = message["id"] as? String {
            key = id + ":" + (dict["requestId"] as? String ?? "")
        }
        return UsageEntry(timestamp: timestamp, model: model, usage: tokens, dedupeKey: key)
    }
}

public enum ModelPricing {
    struct Rates { let input, output, cacheWrite, cacheRead: Double }

    static func rates(for model: String) -> Rates {
        let m = model.lowercased()
        if m.contains("opus") || m.contains("fable") { return Rates(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5) }
        if m.contains("haiku") { return Rates(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1) }
        return Rates(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)
    }

    /// USD, using per-million-token list prices by model family.
    public static func cost(model: String, usage: TokenUsage) -> Double {
        let r = rates(for: model)
        let perToken = 1.0 / 1_000_000
        return (Double(usage.input) * r.input + Double(usage.output) * r.output
            + Double(usage.cacheCreation) * r.cacheWrite + Double(usage.cacheRead) * r.cacheRead) * perToken
    }
}

public struct UsageBlock: Equatable {
    public var start: Date
    public var end: Date
    public var lastActivity: Date
    public var usage: TokenUsage
    public var cost: Double
    public var entryCount: Int

    public init(start: Date, end: Date, lastActivity: Date, usage: TokenUsage, cost: Double, entryCount: Int) {
        self.start = start
        self.end = end
        self.lastActivity = lastActivity
        self.usage = usage
        self.cost = cost
        self.entryCount = entryCount
    }

    public func isActive(now: Date) -> Bool {
        now < end && now.timeIntervalSince(lastActivity) < end.timeIntervalSince(start)
    }
}

public enum UsageAggregator {
    static func deduped(_ entries: [UsageEntry]) -> [UsageEntry] {
        var seen = Set<String>()
        var out: [UsageEntry] = []
        out.reserveCapacity(entries.count)
        for e in entries {
            if let key = e.dedupeKey {
                if seen.contains(key) { continue }
                seen.insert(key)
            }
            out.append(e)
        }
        return out.sorted { $0.timestamp < $1.timestamp }
    }

    static func hourFloor(_ date: Date) -> Date {
        let t = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: (t / 3600).rounded(.down) * 3600)
    }

    public static func blocks(_ entries: [UsageEntry], duration: TimeInterval = 18000) -> [UsageBlock] {
        var blocks: [UsageBlock] = []
        var current: UsageBlock?
        for e in deduped(entries) {
            if var block = current,
               e.timestamp < block.end,
               e.timestamp.timeIntervalSince(block.lastActivity) <= duration {
                block.usage = block.usage + e.usage
                block.cost += ModelPricing.cost(model: e.model, usage: e.usage)
                block.entryCount += 1
                block.lastActivity = e.timestamp
                current = block
            } else {
                if let block = current { blocks.append(block) }
                let start = hourFloor(e.timestamp)
                current = UsageBlock(start: start, end: start.addingTimeInterval(duration), lastActivity: e.timestamp,
                                     usage: e.usage, cost: ModelPricing.cost(model: e.model, usage: e.usage),
                                     entryCount: 1)
            }
        }
        if let block = current { blocks.append(block) }
        return blocks
    }

    public static func activeBlock(_ entries: [UsageEntry], now: Date) -> UsageBlock? {
        guard let last = blocks(entries).last, last.isActive(now: now) else { return nil }
        return last
    }

    public static func summary(_ entries: [UsageEntry], from: Date, to: Date) -> (usage: TokenUsage, cost: Double, count: Int) {
        var usage = TokenUsage.zero
        var cost = 0.0
        var count = 0
        for e in deduped(entries) where e.timestamp >= from && e.timestamp < to {
            usage = usage + e.usage
            cost += ModelPricing.cost(model: e.model, usage: e.usage)
            count += 1
        }
        return (usage, cost, count)
    }
}

public struct RateWindow: Equatable {
    public var usedPercent: Double
    public var windowMinutes: Int?
    public var resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct CodexRateLimits: Equatable {
    public var primary: RateWindow?
    public var secondary: RateWindow?
    public var observedAt: Date

    public init(primary: RateWindow?, secondary: RateWindow?, observedAt: Date) {
        self.primary = primary
        self.secondary = secondary
        self.observedAt = observedAt
    }
}

public enum CodexUsageParser {
    /// `event_msg` / `token_count` lines of `~/.codex/sessions/**/rollout-*.jsonl`.
    public static func parse(line: String) -> CodexRateLimits? {
        guard line.contains("rate_limits"),
              let dict = JSONValue.object(line: line) else { return nil }
        let payload = dict["payload"] as? [String: Any] ?? dict
        guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let observed = JSONValue.isoDate(dict["timestamp"]) ?? Date(timeIntervalSince1970: 0)
        let primary = window(limits["primary"], observed: observed)
        let secondary = window(limits["secondary"], observed: observed)
        guard primary != nil || secondary != nil else { return nil }
        return CodexRateLimits(primary: primary, secondary: secondary, observedAt: observed)
    }

    static func window(_ any: Any?, observed: Date) -> RateWindow? {
        guard let w = any as? [String: Any], let used = JSONValue.double(w["used_percent"]) else { return nil }
        let minutes = w["window_minutes"].map { JSONValue.int($0) }
        var resets: Date?
        if let at = JSONValue.double(w["resets_at"]) {
            resets = Date(timeIntervalSince1970: at)
        } else if let inSeconds = JSONValue.double(w["resets_in_seconds"]) {
            resets = observed.addingTimeInterval(inSeconds)
        }
        return RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: resets)
    }
}
