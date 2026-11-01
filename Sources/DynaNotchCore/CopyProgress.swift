import Foundation

/// What the copy pill shows (CONTRACTS §6.12).
public struct CopySummary: Equatable {
    public var label: String
    public var fraction: Double
    public var secondsLeft: Int?

    public init(label: String, fraction: Double, secondsLeft: Int?) {
        self.label = label
        self.fraction = fraction
        self.secondsLeft = secondsLeft
    }
}

/// Merges the file copies in flight into one pill: the mean fraction, a name or "N items", and a time-left estimate.
public struct CopyProgressTracker: Equatable {
    private struct Item: Equatable {
        var name: String
        var fraction: Double
        var startedAt: Date
    }

    private var items: [String: Item] = [:]
    private var order: [String] = []
    private var lastPostedFraction: Double?
    private var lastPostedAt: Date?

    public init() {}

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    public mutating func update(id: String, name: String, fraction: Double, now: Date) {
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        if var item = items[id] {
            item.fraction = f
            if !name.isEmpty { item.name = name }
            items[id] = item
        } else {
            items[id] = Item(name: name, fraction: f, startedAt: now)
            order.append(id)
        }
    }

    public mutating func remove(id: String) {
        items[id] = nil
        order.removeAll { $0 == id }
        if items.isEmpty {
            lastPostedFraction = nil
            lastPostedAt = nil
        }
    }

    public func summary(now: Date) -> CopySummary? {
        let live = order.compactMap { items[$0] }
        guard let first = live.first else { return nil }
        let fraction = live.map(\.fraction).reduce(0, +) / Double(live.count)
        let label = live.count == 1 ? (first.name.isEmpty ? "1 item" : first.name) : "\(live.count) items"
        let started = live.map(\.startedAt).min() ?? now
        let elapsed = now.timeIntervalSince(started)
        var left: Int?
        if fraction >= 0.03, fraction < 1, elapsed >= 2 {
            left = Int((elapsed * (1 - fraction) / fraction).rounded())
        }
        return CopySummary(label: label, fraction: fraction, secondsLeft: left)
    }

    /// Throttle for the island: post at the start and the end, then on a ≥ 0.5 % change or once a second.
    public mutating func shouldPublish(fraction: Double, now: Date) -> Bool {
        defer {
            lastPostedFraction = fraction
            lastPostedAt = now
        }
        guard let last = lastPostedFraction, let at = lastPostedAt else { return true }
        if fraction >= 1 || fraction <= 0 { return fraction != last }
        return abs(fraction - last) >= 0.005 || now.timeIntervalSince(at) >= 1
    }
}

public enum CopyFormat {
    /// "12 s", "3 min", "1 h 5 min".
    public static func remaining(_ seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "\(s) s" }
        let minutes = Int((Double(s) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "42 %" (whole percent, never 100 % before the copy is done).
    public static func percent(_ fraction: Double) -> String {
        let p = fraction >= 1 ? 100 : min(99, Int((max(0, fraction) * 100).rounded(.down)))
        return "\(p)%"
    }
}
