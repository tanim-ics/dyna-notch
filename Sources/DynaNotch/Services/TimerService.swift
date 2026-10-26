import AppKit
import Combine
import DynaNotchCore

/// Countdown / Pomodoro / stopwatch, driven by `TimerEngine`. Ticks at 1 Hz while a timer exists.
final class TimerService: ObservableObject {
    static let shared = TimerService()

    @Published private(set) var engine = TimerEngine()
    let events = PassthroughSubject<TimerEvent, Never>()
    /// 1 Hz while a timer is active (for views that show running time).
    let tick = PassthroughSubject<Date, Never>()

    var state: TimerState? { engine.state }

    private var ticker: AnyCancellable?

    private init() {}

    func applyConfig(_ config: PomodoroConfig) {
        engine.config = config
    }

    func startCountdown(minutes: Double, label: String) {
        engine.startCountdown(seconds: minutes * 60, label: label, now: Date())
        updateTicker()
    }

    func startPomodoro() {
        engine.startPomodoro(now: Date())
        updateTicker()
    }

    func startStopwatch() {
        engine.startStopwatch(now: Date())
        updateTicker()
    }

    func toggle() {
        engine.toggle(now: Date())
        updateTicker()
    }

    func reset() {
        engine.reset()
        updateTicker()
    }

    func addMinute() {
        engine.addTime(60, now: Date())
    }

    func skipPhase() {
        if let event = engine.skipPhase(now: Date()) {
            events.send(event)
        }
        updateTicker()
    }

    // MARK: Private

    private func updateTicker() {
        if engine.isActive {
            guard ticker == nil else { return }
            ticker = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] now in self?.onTick(now) }
        } else {
            ticker?.cancel()
            ticker = nil
        }
    }

    private func onTick(_ now: Date) {
        if let event = engine.tick(now: now) {
            events.send(event)
            if AppSettings.shared.timerSound {
                NSSound(named: NSSound.Name("Glass"))?.play()
            }
        }
        tick.send(now)
        updateTicker()
    }
}
