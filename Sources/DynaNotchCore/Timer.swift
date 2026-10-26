import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum TimerMode: String, Equatable, Codable {
    case countdown, pomodoro, stopwatch
}

public enum PomodoroPhase: String, Equatable, Codable {
    case work, shortBreak, longBreak

    public var title: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }
}

public struct PomodoroConfig: Equatable {
    public var work: TimeInterval
    public var shortBreak: TimeInterval
    public var longBreak: TimeInterval
    public var cyclesBeforeLongBreak: Int

    public init(work: TimeInterval = 1500, shortBreak: TimeInterval = 300, longBreak: TimeInterval = 900,
                cyclesBeforeLongBreak: Int = 4) {
        self.work = work
        self.shortBreak = shortBreak
        self.longBreak = longBreak
        self.cyclesBeforeLongBreak = cyclesBeforeLongBreak
    }

    func duration(of phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: return work
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

public struct TimerState: Equatable {
    public var mode: TimerMode
    public var phase: PomodoroPhase?
    public var label: String
    /// Target length; 0 for the stopwatch.
    public var duration: TimeInterval
    /// Start of the current run; nil while paused.
    public var startedAt: Date?
    /// Elapsed time before the current run.
    public var accumulated: TimeInterval
    public var completedWorkSessions: Int

    public init(mode: TimerMode, phase: PomodoroPhase? = nil, label: String = "", duration: TimeInterval,
                startedAt: Date?, accumulated: TimeInterval = 0, completedWorkSessions: Int = 0) {
        self.mode = mode
        self.phase = phase
        self.label = label
        self.duration = duration
        self.startedAt = startedAt
        self.accumulated = accumulated
        self.completedWorkSessions = completedWorkSessions
    }

    public var isRunning: Bool { startedAt != nil }

    public func elapsed(at now: Date) -> TimeInterval {
        var total = accumulated
        if let start = startedAt { total += max(0, now.timeIntervalSince(start)) }
        return total
    }

    /// Remaining time; the stopwatch reports its elapsed time.
    public func remaining(at now: Date) -> TimeInterval {
        if mode == .stopwatch { return elapsed(at: now) }
        return max(0, duration - elapsed(at: now))
    }

    public func progress(at now: Date) -> Double {
        guard mode != .stopwatch, duration > 0 else { return 0 }
        return min(1, max(0, elapsed(at: now) / duration))
    }

    /// Countdowns round up so "0:00" only shows at the very end.
    public func displayTime(at now: Date) -> String {
        if mode == .stopwatch { return Format.time(elapsed(at: now)) }
        return Format.time(remaining(at: now).rounded(.up))
    }

    /// Absolute finish time of the running countdown / phase.
    func finishDate(now: Date) -> Date? {
        guard mode != .stopwatch, let start = startedAt else { return nil }
        return start.addingTimeInterval(duration - accumulated)
    }
}

public enum TimerEvent: Equatable {
    case countdownFinished(label: String)
    case phaseFinished(from: PomodoroPhase, to: PomodoroPhase)
}

/// Pure countdown / Pomodoro / stopwatch state machine.
public struct TimerEngine: Equatable {
    public var config: PomodoroConfig
    public private(set) var state: TimerState?

    public init(config: PomodoroConfig = PomodoroConfig()) {
        self.config = config
    }

    public var isActive: Bool { state != nil }

    public mutating func startCountdown(seconds: TimeInterval, label: String, now: Date) {
        guard seconds > 0 else { return }
        state = TimerState(mode: .countdown, label: label, duration: seconds, startedAt: now)
    }

    public mutating func startPomodoro(now: Date) {
        state = TimerState(mode: .pomodoro, phase: .work, label: PomodoroPhase.work.title,
                           duration: config.work, startedAt: now)
    }

    public mutating func startStopwatch(now: Date) {
        state = TimerState(mode: .stopwatch, label: "Stopwatch", duration: 0, startedAt: now)
    }

    public mutating func pause(now: Date) {
        guard var s = state, let start = s.startedAt else { return }
        s.accumulated += max(0, now.timeIntervalSince(start))
        s.startedAt = nil
        state = s
    }

    public mutating func resume(now: Date) {
        guard var s = state, s.startedAt == nil else { return }
        s.startedAt = now
        state = s
    }

    public mutating func toggle(now: Date) {
        guard let s = state else { return }
        if s.isRunning { pause(now: now) } else { resume(now: now) }
    }

    public mutating func reset() {
        state = nil
    }

    public mutating func addTime(_ seconds: TimeInterval, now: Date) {
        guard var s = state, s.mode != .stopwatch else { return }
        s.duration = max(1, s.duration + seconds)
        state = s
    }

    public mutating func skipPhase(now: Date) -> TimerEvent? {
        guard let s = state, s.mode == .pomodoro, let phase = s.phase else { return nil }
        return advance(from: phase, completedWork: phase == .work, startAt: now, previous: s)
    }

    public mutating func tick(now: Date) -> TimerEvent? {
        guard let s = state, s.mode != .stopwatch, s.isRunning, s.remaining(at: now) <= 0 else { return nil }
        switch s.mode {
        case .countdown:
            state = nil
            return .countdownFinished(label: s.label)
        case .pomodoro:
            guard let phase = s.phase else { state = nil; return nil }
            let finishedAt = s.finishDate(now: now) ?? now
            return advance(from: phase, completedWork: phase == .work, startAt: min(finishedAt, now), previous: s)
        case .stopwatch:
            return nil
        }
    }

    public func nextDeadline(now: Date) -> Date? {
        state?.finishDate(now: now)
    }

    private mutating func advance(from phase: PomodoroPhase, completedWork: Bool, startAt: Date,
                                  previous: TimerState) -> TimerEvent {
        var sessions = previous.completedWorkSessions
        let next: PomodoroPhase
        if phase == .work {
            if completedWork { sessions += 1 }
            let cycles = max(1, config.cyclesBeforeLongBreak)
            next = (sessions > 0 && sessions % cycles == 0) ? .longBreak : .shortBreak
        } else {
            next = .work
        }
        state = TimerState(mode: .pomodoro, phase: next, label: next.title, duration: config.duration(of: next),
                           startedAt: startAt, completedWorkSessions: sessions)
        return .phaseFinished(from: phase, to: next)
    }
}
