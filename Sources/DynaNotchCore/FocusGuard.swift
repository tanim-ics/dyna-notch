import Foundation

/// Focus Guard (CONTRACTS §6.17): distraction apps during a Pomodoro focus phase.
public enum FocusGuard {
    /// Chat and news apps; browsers are left out (you work in them too).
    public static let defaultApps = "com.tinyspeck.slackmacgap,com.hnc.Discord,ru.keepcoder.Telegram,net.whatsapp.WhatsApp,com.apple.MobileSMS,com.apple.news,com.facebook.archon,com.spotify.client"

    public static func isFocusing(_ state: TimerState?) -> Bool {
        guard let s = state else { return false }
        return s.mode == .pomodoro && s.phase == .work && s.isRunning
    }

    public static func apps(from list: String) -> Set<String> {
        Set(list.split(whereSeparator: { $0 == "," || $0.isNewline || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }
}

/// Time spent in distraction apps during one focus phase.
public struct DistractionTracker: Equatable {
    public private(set) var seconds: TimeInterval = 0
    public private(set) var current: String?
    private var since: Date?

    public init() {}

    public mutating func enter(app: String, at date: Date) {
        leave(at: date)
        current = app
        since = date
    }

    public mutating func leave(at date: Date) {
        if let start = since { seconds += max(0, date.timeIntervalSince(start)) }
        current = nil
        since = nil
    }

    public mutating func reset() { self = DistractionTracker() }
}

/// Focus Soundscapes: noise generated on this Mac.
public enum Soundscape: String, Equatable, CaseIterable {
    case none, rain, brown, pink, fire

    public var title: String {
        switch self {
        case .none: return "Off"
        case .rain: return "Rain"
        case .brown: return "Brown Noise"
        case .pink: return "Pink Noise"
        case .fire: return "Fireplace"
        }
    }

    public var symbol: String {
        switch self {
        case .none: return "speaker.slash.fill"
        case .rain: return "cloud.rain.fill"
        case .brown: return "waveform.path"
        case .pink: return "waveform"
        case .fire: return "flame.fill"
        }
    }
}
