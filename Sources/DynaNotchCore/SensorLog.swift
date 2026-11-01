import Foundation

/// When the camera / microphone was on, and for which app (CONTRACTS §6.16).
public struct SensorUsageLog: Equatable, Codable {
    public struct Session: Equatable, Codable {
        public var sensor: String
        public var app: String
        public var start: Date
        public var end: Date?

        public var duration: TimeInterval? { end.map { $0.timeIntervalSince(start) } }
    }

    public static let limit = 50
    /// Newest first.
    public private(set) var sessions: [Session] = []

    public init() {}

    public mutating func begin(_ sensor: SensorKind, app: String, at date: Date) {
        if let open = sessions.firstIndex(where: { $0.sensor == sensor.rawValue && $0.end == nil }) {
            if sessions[open].app.isEmpty { sessions[open].app = app }
            return
        }
        sessions.insert(Session(sensor: sensor.rawValue, app: app, start: date, end: nil), at: 0)
        if sessions.count > SensorUsageLog.limit { sessions.removeLast(sessions.count - SensorUsageLog.limit) }
    }

    public mutating func end(_ sensor: SensorKind, at date: Date) {
        guard let open = sessions.firstIndex(where: { $0.sensor == sensor.rawValue && $0.end == nil }) else { return }
        sessions[open].end = max(date, sessions[open].start)
    }

    public mutating func clear() { sessions = [] }

    /// Drops one app's sessions (test cleanup).
    public mutating func forget(app: String) { sessions.removeAll { $0.app == app } }
}

/// Your share of speaking time in a call, from the mic level only (nothing is recorded).
public struct TalkMeter: Equatable {
    public static let threshold: Double = -42
    public static let hangover: TimeInterval = 0.3

    public private(set) var total: TimeInterval = 0
    public private(set) var speaking: TimeInterval = 0
    private var sinceVoice: TimeInterval = .infinity

    public init() {}

    public mutating func add(level: Double, seconds: TimeInterval) {
        guard seconds > 0, seconds.isFinite else { return }
        total += seconds
        if level >= TalkMeter.threshold {
            sinceVoice = 0
            speaking += seconds
        } else {
            sinceVoice += seconds
            if sinceVoice <= TalkMeter.hangover { speaking += seconds }   // short pauses between words count
        }
    }

    /// 0…100, nil until 10 s were measured.
    public var share: Int? {
        guard total >= 10 else { return nil }
        return Int((speaking / total * 100).rounded())
    }
}

public enum CallFormat {
    /// "4:05", "1:02:09".
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// "Call 42 min · you spoke 61%".
    public static func recap(seconds: TimeInterval, talkShare: Int?) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let base = "Call \(minutes) min"
        return talkShare.map { "\(base) · you spoke \($0)%" } ?? base
    }
}
