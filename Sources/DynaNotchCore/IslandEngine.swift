import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum IslandPresentation: Equatable {
    case hidden, idle, nowPlaying, peek, activity(LiveActivity), expanded, timer, lyrics

    /// nowPlaying, peek, activity, timer, lyrics
    public var isCompactLike: Bool {
        switch self {
        case .nowPlaying, .peek, .activity, .timer, .lyrics: return true
        case .hidden, .idle, .expanded: return false
        }
    }
}

public enum SwipeDirection: String, Equatable {
    case left, right, up, down
}

/// Pure state machine deciding what the island shows.
public struct IslandEngine: Equatable {
    public private(set) var activities: [LiveActivity] = []
    public var isExpanded: Bool = false
    public var isNowPlayingActive: Bool = false
    /// Full-screen hide.
    public var isSuppressed: Bool = false
    public private(set) var peekUntil: Date?
    /// A countdown / Pomodoro / stopwatch is running or paused.
    public var isTimerActive: Bool = false
    /// A synced lyric line is available (only honoured with compact now playing).
    public var hasLyricLine: Bool = false
    public var prefersTimerOverMusic: Bool = true

    public init() {}

    /// Same category replaces the existing (still live) activity **keeping its id**.
    @discardableResult
    public mutating func post(_ kind: ActivityKind, now: Date, duration: TimeInterval? = nil) -> LiveActivity {
        let life = duration ?? kind.defaultDuration
        let expires = now.addingTimeInterval(life)
        if let index = activities.firstIndex(where: { $0.kind.category == kind.category }) {
            if activities[index].expiresAt > now {
                activities[index].kind = kind
                activities[index].postedAt = now
                activities[index].expiresAt = expires
                return activities[index]
            }
            // Expired but not yet pruned: start a fresh activity (new id → new transition).
            activities.remove(at: index)
        }
        let activity = LiveActivity(kind: kind, postedAt: now, expiresAt: expires)
        activities.append(activity)
        return activity
    }

    public mutating func dismissCurrent(now: Date) {
        guard let current = currentActivity(now: now) else { return }
        activities.removeAll { $0.id == current.id }
    }

    public mutating func dismissAll() {
        activities.removeAll()
    }

    public mutating func startPeek(now: Date, duration: TimeInterval) {
        peekUntil = now.addingTimeInterval(duration)
    }

    public mutating func cancelPeek() {
        peekUntil = nil
    }

    /// Drops expired activities and a finished peek.
    public mutating func prune(now: Date) {
        activities.removeAll { $0.expiresAt <= now }
        if let until = peekUntil, until <= now {
            peekUntil = nil
        }
    }

    /// Highest priority live activity; ties → newest postedAt.
    public func currentActivity(now: Date) -> LiveActivity? {
        var best: LiveActivity?
        for activity in activities where activity.expiresAt > now {
            guard let current = best else { best = activity; continue }
            let p = activity.kind.priority, q = current.kind.priority
            if p > q || (p == q && activity.postedAt > current.postedAt) {
                best = activity
            }
        }
        return best
    }

    public func presentation(now: Date, showNowPlayingCompact: Bool) -> IslandPresentation {
        if isExpanded { return .expanded }
        if let activity = currentActivity(now: now) { return .activity(activity) }
        if isSuppressed { return .hidden }
        if let until = peekUntil, until > now, isNowPlayingActive { return .peek }
        if isTimerActive && prefersTimerOverMusic { return .timer }
        if isNowPlayingActive && showNowPlayingCompact { return hasLyricLine ? .lyrics : .nowPlaying }
        if isTimerActive { return .timer }
        return .idle
    }

    /// Earliest future expiresAt / peekUntil.
    public func nextDeadline(now: Date) -> Date? {
        var candidates = activities.map(\.expiresAt).filter { $0 > now }
        if let until = peekUntil, until > now { candidates.append(until) }
        return candidates.min()
    }
}

extension ActivityKind {
    /// Settings → Popups → Quiet During Focus: these popups are dropped while a Focus mode is on.
    /// Low battery, finished timers, privacy (camera / mic), charging and the Focus change itself still show.
    public var isQuietedDuringFocus: Bool {
        switch self {
        case .hud, .toggle, .bluetooth, .download, .notification, .calendar:
            return true
        case .charging, .lowBattery, .focus, .timerFinished, .sensor:
            return false
        }
    }
}
