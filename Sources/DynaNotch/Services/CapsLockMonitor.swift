import AppKit
import Combine

/// Caps Lock state by polling the modifier flags (no Accessibility permission needed).
final class CapsLockMonitor {
    static let shared = CapsLockMonitor()

    let changes = PassthroughSubject<Bool, Never>()
    private(set) var isOn = false

    private var timer: AnyCancellable?

    private init() {}

    func start() {
        guard timer == nil else { return }
        isOn = NSEvent.modifierFlags.contains(.capsLock)
        timer = Timer.publish(every: 0.25, tolerance: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let on = NSEvent.modifierFlags.contains(.capsLock)
        guard on != isOn else { return }
        isOn = on
        changes.send(on)
    }
}
