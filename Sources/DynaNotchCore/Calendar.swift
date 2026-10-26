import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct CalendarItem: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var colorHex: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool, location: String? = nil, colorHex: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.colorHex = colorHex
    }
}

public struct CalendarAlertTracker {
    /// Keys (id + start) already returned. A rescheduled event alerts again.
    private var alerted: Set<String> = []

    public init() {}

    /// Timed (non all-day) events with now < start <= now + lead·60 that were not returned before.
    public mutating func due(events: [CalendarItem], now: Date, leadMinutes: Int) -> [CalendarItem] {
        let horizon = now.addingTimeInterval(TimeInterval(max(0, leadMinutes)) * 60)
        var result: [CalendarItem] = []
        for event in events where !event.isAllDay && event.start > now && event.start <= horizon {
            let key = Self.key(event)
            if alerted.insert(key).inserted {
                result.append(event)
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    private static func key(_ item: CalendarItem) -> String {
        "\(item.id)@\(item.start.timeIntervalSince1970)"
    }
}

public enum CalendarFilter {
    /// Not ended, sorted by start (all-day first for today), max `limit`.
    public static func upcoming(_ items: [CalendarItem], now: Date, limit: Int) -> [CalendarItem] {
        guard limit > 0 else { return [] }
        let live = items.filter { $0.end > now }
        // An all-day item that has started (and not ended) is "today's" all-day item.
        func isTodayAllDay(_ item: CalendarItem) -> Bool { item.isAllDay && item.start <= now }
        let sorted = live.sorted { a, b in
            let aa = isTodayAllDay(a), bb = isTodayAllDay(b)
            if aa != bb { return aa }
            if a.start != b.start { return a.start < b.start }
            return a.title < b.title
        }
        return Array(sorted.prefix(limit))
    }
}
