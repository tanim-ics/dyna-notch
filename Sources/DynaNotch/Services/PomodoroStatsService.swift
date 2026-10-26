import Foundation
import Combine
import DynaNotchCore

/// Persists completed focus sessions (fed by TimerService phase events) in UserDefaults `dn.data.pomodoroStats`.
final class PomodoroStatsService: ObservableObject {
    static let shared = PomodoroStatsService()

    @Published private(set) var stats = PomodoroStats()

    private static let key = "dn.data.pomodoroStats"
    private var started = false
    private var subscription: AnyCancellable?

    private init() {
        if let saved = AppDataStore.loadDefaults(PomodoroStats.self, key: PomodoroStatsService.key) {
            stats = saved
        }
    }

    func start() {
        guard !started else { return }
        started = true
        subscription = TimerService.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard case .phaseFinished(let from, _) = event, from == .work else { return }
                self?.recordSession()
            }
    }

    func reset() {
        stats = PomodoroStats()
        AppDataStore.saveDefaults(stats, key: PomodoroStatsService.key)
    }

    private func recordSession() {
        var updated = stats
        updated.recordSession(at: Date())
        stats = updated
        AppDataStore.saveDefaults(updated, key: PomodoroStatsService.key)
    }
}
