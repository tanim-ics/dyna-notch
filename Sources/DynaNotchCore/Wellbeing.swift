import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - Break reminders

public enum BreakKind: String, Equatable, Hashable, CaseIterable, Codable {
    case lookAway, standUp, drinkWater

    public var title: String {
        switch self {
        case .lookAway: return "Look Away"
        case .standUp: return "Stand Up"
        case .drinkWater: return "Drink Water"
        }
    }

    public var message: String {
        switch self {
        case .lookAway: return "20 seconds, 20 feet away"
        case .standUp: return "Stretch your legs"
        case .drinkWater: return "Time for some water"
        }
    }

    public var symbol: String {
        switch self {
        case .lookAway: return "eye.fill"
        case .standUp: return "figure.stand"
        case .drinkWater: return "drop.fill"
        }
    }
}

/// Decides which break reminders are due. Look Away follows the 20-20-20 rule (every 20 min).
public struct BreakScheduler: Equatable {
    public private(set) var lastFired: [BreakKind: Date] = [:]

    public init() {}

    /// Kinds whose interval has passed since they last fired (or since `start` for the first time),
    /// marked as fired at `now`. `intervals` holds minutes per enabled kind; `isQuiet` (locked, Focus, idle)
    /// postpones everything without firing.
    public mutating func due(now: Date, start: Date, intervals: [BreakKind: Int], isQuiet: Bool) -> [BreakKind] {
        guard !isQuiet else { return [] }
        var result: [BreakKind] = []
        for kind in BreakKind.allCases {
            guard let minutes = intervals[kind], minutes > 0 else { continue }
            let since = lastFired[kind] ?? start
            if now.timeIntervalSince(since) >= TimeInterval(minutes * 60) {
                result.append(kind)
                lastFired[kind] = now
            }
        }
        return result
    }

    /// After the user was away (locked / asleep), restart every interval from `now`.
    public mutating func reset(now: Date) {
        for kind in BreakKind.allCases { lastFired[kind] = now }
    }
}

// MARK: - Pomodoro stats

public struct PomodoroStats: Equatable, Codable {
    /// Start-of-day → completed focus sessions that day.
    public private(set) var sessionsByDay: [Date: Int] = [:]

    public init() {}

    public mutating func recordSession(at date: Date, calendar: Calendar = .current) {
        sessionsByDay[calendar.startOfDay(for: date), default: 0] += 1
    }

    public func today(now: Date, calendar: Calendar = .current) -> Int {
        sessionsByDay[calendar.startOfDay(for: now)] ?? 0
    }

    public var total: Int { sessionsByDay.values.reduce(0, +) }

    /// Consecutive days with at least one session, ending today (or yesterday if today has none yet).
    public func streak(now: Date, calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: now)
        if (sessionsByDay[day] ?? 0) == 0 {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while (sessionsByDay[day] ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}

// MARK: - Battery history

public struct BatterySample: Equatable, Codable {
    public var date: Date
    public var level: Int
    public var charging: Bool

    public init(date: Date, level: Int, charging: Bool) {
        self.date = date
        self.level = level
        self.charging = charging
    }
}

public struct BatteryHistory: Equatable, Codable {
    public private(set) var samples: [BatterySample] = []
    /// Minimum spacing between stored samples (a changed charging state is always stored).
    public var interval: TimeInterval = 300
    public var retention: TimeInterval = 30 * 86400

    public init() {}

    @discardableResult
    public mutating func append(_ sample: BatterySample) -> Bool {
        if let last = samples.last {
            guard sample.date > last.date else { return false }
            let spaced = sample.date.timeIntervalSince(last.date) >= interval
            guard spaced || sample.charging != last.charging else { return false }
        }
        samples.append(sample)
        let cutoff = sample.date.addingTimeInterval(-retention)
        if let first = samples.first, first.date < cutoff {
            samples.removeAll { $0.date < cutoff }
        }
        return true
    }

    public func samples(since: Date) -> [BatterySample] {
        samples.filter { $0.date >= since }
    }
}

// MARK: - Screen time

/// Time spent per app (by bundle id) per day, from frontmost-app switches.
public struct ScreenTimeLedger: Equatable, Codable {
    /// Start-of-day → bundle id → seconds.
    public private(set) var days: [Date: [String: TimeInterval]] = [:]
    public var names: [String: String] = [:]

    public init() {}

    /// Adds `from..<to` for `app`, split across midnights. Ignores negative / absurd (> 1 h) spans.
    public mutating func record(app: String, name: String? = nil, from: Date, to: Date, calendar: Calendar = .current) {
        guard to > from, to.timeIntervalSince(from) <= 3600 else { return }
        if let name = name { names[app] = name }
        var start = from
        while start < to {
            let day = calendar.startOfDay(for: start)
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? to
            let end = min(to, nextDay)
            days[day, default: [:]][app, default: 0] += end.timeIntervalSince(start)
            start = end
        }
    }

    /// Apps used on the day of `now`, most used first.
    public func top(on now: Date, limit: Int = 5, calendar: Calendar = .current) -> [(app: String, seconds: TimeInterval)] {
        let day = days[calendar.startOfDay(for: now)] ?? [:]
        return day.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit).map { ($0.key, $0.value) }
    }

    public func total(on now: Date, calendar: Calendar = .current) -> TimeInterval {
        (days[calendar.startOfDay(for: now)] ?? [:]).values.reduce(0, +)
    }

    public mutating func prune(keepDays: Int, now: Date, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: calendar.startOfDay(for: now)) else { return }
        days = days.filter { $0.key >= cutoff }
    }
}

// MARK: - Meetings

public enum MeetingLink {
    static let patterns = [
        "https://[a-z0-9.-]*zoom\\.us/(j|my|w)/[^\\s\"'<>]+",
        "https://meet\\.google\\.com/[a-z]{3,4}-[a-z]{3,4}-[a-z]{3,4}[^\\s\"'<>]*",
        "https://teams\\.microsoft\\.com/l/meetup-join/[^\\s\"'<>]+",
        "https://teams\\.live\\.com/meet/[^\\s\"'<>]+",
        "https://[a-z0-9.-]*webex\\.com/[^\\s\"'<>]+",
        "https://[a-z0-9.-]*whereby\\.com/[^\\s\"'<>]+",
        "https://app\\.slack\\.com/huddle/[^\\s\"'<>]+",
        "https://discord\\.(gg|com)/[^\\s\"'<>]+",
    ]

    /// First video-call link found in any of the texts (event URL, location, notes).
    public static func detect(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, range: range), let r = Range(match.range, in: text) {
                    var link = String(text[r])
                    while let last = link.last, ".,;)]".contains(last) { link.removeLast() }
                    if let url = URL(string: link) { return url }
                }
            }
        }
        return nil
    }
}

// MARK: - Accessory battery alerts

public enum AccessoryAlert: Equatable {
    case low(DeviceBattery)
    case full(DeviceBattery)
}

/// Fires once when a device drops to `lowThreshold` or below, and once when it reaches 100 % while charging
/// (re-armed when it climbs back above threshold + 10, or drops below 95).
public struct AccessoryAlertDetector {
    public var lowThreshold: Int
    private var lowFired = Set<String>()
    private var fullFired = Set<String>()
    private var seeded = false

    public init(lowThreshold: Int = 20) {
        self.lowThreshold = lowThreshold
    }

    public mutating func update(_ devices: [DeviceBattery]) -> [AccessoryAlert] {
        var alerts: [AccessoryAlert] = []
        for device in devices where device.kind != .mac {
            guard let level = device.displayLevel else { continue }
            if level <= lowThreshold {
                if !lowFired.contains(device.id) {
                    lowFired.insert(device.id)
                    if seeded { alerts.append(.low(device)) }
                }
            } else if level > lowThreshold + 10 {
                lowFired.remove(device.id)
            }
            if level >= 100 && device.isCharging {
                if !fullFired.contains(device.id) {
                    fullFired.insert(device.id)
                    if seeded { alerts.append(.full(device)) }
                }
            } else if level < 95 {
                fullFired.remove(device.id)
            }
        }
        seeded = true
        return alerts
    }
}

// MARK: - Appearance

public enum MaterialPreset: String, Equatable, Hashable, CaseIterable {
    case graphite, onyx, carbon, frost, satin, mist, clear

    public var title: String { rawValue.capitalized }

    public var subtitle: String {
        switch self {
        case .graphite: return "Neutral dark with a soft blur"
        case .onyx: return "Darkest — the desktop barely reads through"
        case .carbon: return "Deep charcoal for bright desktops"
        case .frost: return "Lighter frosted pane"
        case .satin: return "Soft glass between Graphite and Frost"
        case .mist: return "Bright frost — best over dark wallpapers"
        case .clear: return "Clear glass with a dark backdrop"
        }
    }

    /// Grey level (0 black … 1 white) of the tint laid over the blur.
    public var tintWhite: Double {
        switch self {
        case .graphite: return 0.12
        case .onyx: return 0.0
        case .carbon: return 0.06
        case .frost: return 0.42
        case .satin: return 0.26
        case .mist: return 0.55
        case .clear: return 0.0
        }
    }

    /// Tint opacity at 100 % translucency setting (lower = more desktop shows through).
    public var tintOpacity: Double {
        switch self {
        case .graphite: return 0.5
        case .onyx: return 0.86
        case .carbon: return 0.66
        case .frost: return 0.38
        case .satin: return 0.44
        case .mist: return 0.34
        case .clear: return 0.18
        }
    }

    /// Tint opacity for a translucency setting in 0...1 (1 = see-through as designed, 0 = opaque).
    public func opacity(translucency: Double) -> Double {
        let t = min(1, max(0, translucency))
        return tintOpacity + (1 - tintOpacity) * (1 - t)
    }
}

public enum AnimationStyle: String, Equatable, Hashable, CaseIterable {
    case calm, snappy, bouncy

    public var title: String { rawValue.capitalized }

    /// Spring response (seconds) and damping fraction at 1× speed.
    public var spring: (response: Double, damping: Double) {
        switch self {
        case .calm: return (0.48, 0.86)
        case .snappy: return (0.3, 0.9)
        case .bouncy: return (0.45, 0.68)
        }
    }

    public func response(speed: Double) -> Double {
        spring.response / min(3, max(0.25, speed))
    }
}

public enum TimeFormat: String, Equatable, Hashable, CaseIterable {
    case system, h12, h24

    public var title: String {
        switch self {
        case .system: return "System"
        case .h12: return "12-Hour"
        case .h24: return "24-Hour"
        }
    }

    /// DateFormatter template for hour + minute.
    public var template: String {
        switch self {
        case .system: return "jmm"
        case .h12: return "hmm a"
        case .h24: return "HHmm"
        }
    }
}
