import AppKit
import Combine
import os
import DynaNotchCore

/// Knock: with `settings.knockEnabled`, tapping `settings.knockKey` alone 1–3 times (`KnockDetector`) runs the
/// action mapped in `settings.knockActions` through `AppActions`. Global + local `.flagsChanged` / `.keyDown`
/// monitors; the global ones only receive events once DynaNotch has Accessibility (logged once, never fatal) —
/// without it, knocks still work while DynaNotch's own windows are key.
final class KnockMonitor: ObservableObject {
    static let shared = KnockMonitor()

    /// Last recognised tap count (for tests / settings "Try it").
    @Published private(set) var lastKnock: Int = 0
    /// Last action run by a knock (raw value), for tests.
    @Published private(set) var lastAction: String = ""
    @Published private(set) var isRunning = false

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "knock")
    private var detector = KnockDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observers = Set<AnyCancellable>()
    private var started = false
    private var loggedMissingPermission = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let settings = AppSettings.shared
        Publishers.CombineLatest(settings.$knockEnabled.removeDuplicates(), settings.$knockKey.removeDuplicates())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, _ in
                self?.removeMonitors()
                if enabled { self?.installMonitors() }
            }
            .store(in: &observers)
    }

    func stop() {
        observers.removeAll()
        removeMonitors()
        started = false
    }

    /// Runs the action for `count` taps as if the knock had happened (tests, Settings "Try it").
    func simulate(count: Int) {
        recognised(count)
    }

    // MARK: Monitors

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if !Permissions.accessibilityGranted && !loggedMissingPermission {
            loggedMissingPermission = true
            logger.notice("knock: no Accessibility permission — knocks only work while DynaNotch is focused")
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            KnockMonitor.shared.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            KnockMonitor.shared.handle(event)
            return event
        }
        detector = KnockDetector()
        isRunning = true
        logger.info("knock monitor on (\(AppSettings.shared.knockKey.rawValue, privacy: .public))")
    }

    private func removeMonitors() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        globalMonitor = nil
        localMonitor = nil
        detector = KnockDetector()
        isRunning = false
    }

    private static func keyCodes(for key: KnockKey) -> Set<UInt16> {
        switch key {
        case .control: return [59, 62]
        case .option: return [58, 61]
        case .command: return [55, 54]
        case .shift: return [56, 60]
        }
    }

    private static func flag(for key: KnockKey) -> NSEvent.ModifierFlags {
        switch key {
        case .control: return .control
        case .option: return .option
        case .command: return .command
        case .shift: return .shift
        }
    }

    private func handle(_ event: NSEvent) {
        let now = Date()
        let key = AppSettings.shared.knockKey
        switch event.type {
        case .keyDown:
            detector.interrupt()
        case .flagsChanged:
            let all: NSEvent.ModifierFlags = [.control, .option, .command, .shift, .function]
            let flags = event.modifierFlags.intersection(all)
            let mine = KnockMonitor.flag(for: key)
            guard KnockMonitor.keyCodes(for: key).contains(event.keyCode) else {
                // Another modifier changed: a chord, not a knock.
                detector.interrupt()
                return
            }
            if flags.contains(mine) {
                if flags == mine {
                    detector.press(at: now)
                } else {
                    detector.interrupt()
                }
            } else {
                detector.release(at: now)
                let wait = detector.window + 0.05
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.settle() }
            }
        default:
            break
        }
    }

    private func settle() {
        guard let count = detector.settle(now: Date()) else { return }
        recognised(count)
    }

    private func recognised(_ count: Int) {
        lastKnock = count
        let action = KnockAction.parseMap(AppSettings.shared.knockActions)[count] ?? .none
        lastAction = action.rawValue
        logger.info("knock ×\(count) → \(action.rawValue, privacy: .public)")
        AppActions.shared.perform(knock: action)
    }
}
