import AppKit
import Combine
import Foundation
import DynaNotchCore

/// Focus Guard (CONTRACTS §6.17): a distraction app during a Pomodoro focus phase shakes the island and says so.
final class FocusGuardService {
    static let shared = FocusGuardService()

    /// Main queue: shake the island.
    let shakes = PassthroughSubject<Void, Never>()

    private var started = false
    private var cancellables = Set<AnyCancellable>()
    private(set) var tracker = DistractionTracker()

    private init() {}

    var state: [String: Any] {
        ["focusing": FocusGuard.isFocusing(TimerService.shared.state), "distraction": Int(tracker.seconds),
         "current": tracker.current ?? ""]
    }

    func start() {
        guard !started else { return }
        started = true
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in self?.activated(bundleID: app.bundleIdentifier ?? "", name: app.localizedName ?? "") }
            .store(in: &cancellables)
        TimerService.shared.events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self = self, case let .phaseFinished(from, _) = event else { return }
                if from == .work { self.focusEnded() } else { self.tracker.reset() }
            }
            .store(in: &cancellables)
    }

    /// Also the `dynanotch://focusguard?app=` test hook.
    func activated(bundleID: String, name: String) {
        let settings = AppSettings.shared
        guard settings.focusGuard, FocusGuard.isFocusing(TimerService.shared.state) else {
            tracker.leave(at: Date())
            return
        }
        guard FocusGuard.apps(from: settings.focusGuardApps).contains(bundleID.lowercased()) else {
            tracker.leave(at: Date())
            return
        }
        let display = name.isEmpty ? bundleID : name
        tracker.enter(app: display, at: Date())
        shakes.send(())
        let left = TimerService.shared.state.map { Int(($0.remaining(at: Date()) / 60).rounded(.up)) } ?? 0
        ScreenRecorder.notify(title: "Back to focus", body: "\(display) · \(left) min left", symbol: "eye.slash.fill",
                              category: .timers)
    }

    private func focusEnded() {
        tracker.leave(at: Date())
        let minutes = Int((tracker.seconds / 60).rounded())
        if AppSettings.shared.focusGuard, tracker.seconds >= 30 {
            ScreenRecorder.notify(title: "Focus done", body: "\(max(1, minutes)) min in distractions",
                                  symbol: "chart.bar.fill", category: .timers)
        }
        tracker.reset()
    }
}
