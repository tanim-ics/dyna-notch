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
    private var alarmTimer: AnyCancellable?
    private var alarmStartedAt: Date?
    private var cancellables = Set<AnyCancellable>()
    /// A ringing alarm gives up by itself after this long.
    private static let alarmMaxDuration: TimeInterval = 120

    private init() {
        engine.repeatCountdown = AppSettings.shared.repeatTimer
        AppSettings.shared.$repeatTimer
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in self?.engine.repeatCountdown = on }
            .store(in: &cancellables)
        AppSettings.shared.$repeatAlarm
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] on in if !on { self?.stopAlarm() } }
            .store(in: &cancellables)
    }

    func applyConfig(_ config: PomodoroConfig) {
        engine.config = config
    }

    func startCountdown(minutes: Double, label: String) {
        stopAlarm()
        engine.startCountdown(seconds: minutes * 60, label: label, now: Date())
        updateTicker()
    }

    func startPomodoro() {
        stopAlarm()
        engine.startPomodoro(now: Date())
        updateTicker()
    }

    func startStopwatch() {
        stopAlarm()
        engine.startStopwatch(now: Date())
        updateTicker()
    }

    func toggle() {
        engine.toggle(now: Date())
        updateTicker()
    }

    /// With settings.repeatAlarm the finish sound repeats every 2 s until `stopAlarm()`
    /// (the island calls it when the finished activity is clicked or the panel opens; it also gives up after 2 min).
    @Published private(set) var isAlarmRinging = false
    func stopAlarm() {
        alarmTimer?.cancel()
        alarmTimer = nil
        alarmStartedAt = nil
        if isAlarmRinging { isAlarmRinging = false }
    }

    func reset() {
        stopAlarm()
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

    private func startAlarm() {
        alarmStartedAt = Date()
        if !isAlarmRinging { isAlarmRinging = true }
        guard alarmTimer == nil else { return }
        alarmTimer = Timer.publish(every: 2, tolerance: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self = self else { return }
                guard AppSettings.shared.repeatAlarm, AppSettings.shared.timerSound,
                      let started = self.alarmStartedAt,
                      now.timeIntervalSince(started) < TimerService.alarmMaxDuration else {
                    self.stopAlarm()
                    return
                }
                AlertSoundPlayer.play(.timers)
            }
    }

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
            if case .phaseFinished = event, !AppSettings.shared.pomodoroAutoContinue {
                // Hold the next phase at its very start until the user resumes it.
                engine.pause(now: engine.state?.startedAt ?? now)
            }
            events.send(event)
            // The first sound comes with the island's "timer finished" activity (Settings → Popups → Sounds);
            // Repeat Alarm keeps ringing every 2 s after it.
            if AppSettings.shared.timerSound && AppSettings.shared.repeatAlarm { startAlarm() }
        }
        tick.send(now)
        updateTicker()
    }
}
