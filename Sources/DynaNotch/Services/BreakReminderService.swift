import Foundation
import Combine
import DynaNotchCore

/// Look-away / stand-up / drink-water nudges (posted as notification activities by the view model).
/// Checks every 30 s; quiet while the screen is locked / asleep, the user is idle > 5 min or an app is full screen.
final class BreakReminderService {
    static let shared = BreakReminderService()

    let reminders = PassthroughSubject<BreakKind, Never>()

    private var scheduler = BreakScheduler()
    private var startDate = Date()
    private var started = false
    private var wasIdle = false
    private var cancellables = Set<AnyCancellable>()

    private static let idleLimit: TimeInterval = 300

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        startDate = Date()
        UserPresence.shared.start()

        UserPresence.shared.returned
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.restart() }
            .store(in: &cancellables)

        // Turning a reminder on starts its interval from now.
        let settings = AppSettings.shared
        settings.$breakLookAway.combineLatest(settings.$breakStandUp, settings.$breakDrinkWater)
            .dropFirst()
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.restart() }
            .store(in: &cancellables)

        Timer.publish(every: 30, tolerance: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in self?.check(now: now) }
            .store(in: &cancellables)
    }

    // MARK: Private (main queue)

    private func restart() {
        let now = Date()
        startDate = now
        scheduler.reset(now: now)
    }

    private func intervals() -> [BreakKind: Int] {
        let settings = AppSettings.shared
        var result: [BreakKind: Int] = [:]
        if settings.breakLookAway { result[.lookAway] = 20 }
        if settings.breakStandUp { result[.standUp] = settings.standUpMinutes }
        if settings.breakDrinkWater { result[.drinkWater] = settings.drinkWaterMinutes }
        return result
    }

    private func check(now: Date) {
        let intervals = self.intervals()
        guard !intervals.isEmpty else { return }
        let presence = UserPresence.shared
        let idle = presence.idleSeconds > BreakReminderService.idleLimit
        // Coming back from a long idle stretch counts as a break: restart the clocks.
        if wasIdle && !idle { restart() }
        wasIdle = idle
        let quiet = presence.isAway || idle || FullscreenDetector.shared.isFullscreen
        for kind in scheduler.due(now: now, start: startDate, intervals: intervals, isQuiet: quiet) {
            reminders.send(kind)
        }
    }
}
