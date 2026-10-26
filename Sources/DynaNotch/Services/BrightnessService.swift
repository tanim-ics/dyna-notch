import AppKit
import Combine
import CoreGraphics
import Darwin
import Foundation
import os

/// Built-in display brightness via the private DisplayServices framework (dlopen'd, every call nil-guarded).
/// Changes made elsewhere (Control Center, ambient light) are picked up by a 0.2 s poll on main.
final class BrightnessService {
    static let shared = BrightnessService()

    let changes = PassthroughSubject<Double, Never>()

    private typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "brightness")
    private var handle: UnsafeMutableRawPointer?
    private var getFn: GetBrightnessFn?
    private var setFn: SetBrightnessFn?

    private var started = false
    private var lastLevel: Double?
    private var pollCancellable: AnyCancellable?
    private var screenCancellable: AnyCancellable?
    private var cachedDisplayID: CGDirectDisplayID?

    private init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        handle = dlopen(path, RTLD_NOW)
        if let h = handle {
            if let sym = dlsym(h, "DisplayServicesGetBrightness") {
                getFn = unsafeBitCast(sym, to: GetBrightnessFn.self)
            }
            if let sym = dlsym(h, "DisplayServicesSetBrightness") {
                setFn = unsafeBitCast(sym, to: SetBrightnessFn.self)
            }
        } else {
            logger.error("DisplayServices unavailable")
        }
    }

    /// True when the private symbols loaded and the built-in display reports a brightness.
    var isAvailable: Bool {
        getFn != nil && setFn != nil && read() != nil
    }

    func start() {
        guard !started else { return }
        started = true
        lastLevel = nil
        screenCancellable = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.cachedDisplayID = nil }
        guard getFn != nil else { return }
        // Only needed to notice brightness-key changes when the media-key tap can't see the keys (no Accessibility);
        // with the tap active, it posts the HUD itself and this poll stops.
        tapCancellable = MediaKeyTap.shared.$isActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tapActive in self?.setPolling(!tapActive) }
    }

    private var tapCancellable: AnyCancellable?

    private func setPolling(_ on: Bool) {
        if on {
            guard pollCancellable == nil else { return }
            pollCancellable = Timer.publish(every: 0.5, tolerance: 0.2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.poll() }
            poll()
        } else {
            pollCancellable?.cancel()
            pollCancellable = nil
            lastLevel = read()
        }
    }

    func read() -> Double? {
        guard let getter = getFn else { return nil }
        var value: Float = 0
        let status = getter(displayID(), &value)
        guard status == 0, value.isFinite else { return nil }
        return min(max(Double(value), 0), 1)
    }

    @discardableResult
    func setLevel(_ v: Double) -> Bool {
        guard let setter = setFn else { return false }
        let value = v.isFinite ? min(max(v, 0), 1) : 0
        let ok = setter(displayID(), Float(value)) == 0
        if ok { lastLevel = value }   // do not echo our own change back through `changes`
        return ok
    }

    // MARK: Private

    private func poll() {
        guard let level = read() else { return }
        guard let last = lastLevel else {
            lastLevel = level   // first reading is only recorded
            return
        }
        if abs(level - last) > 0.004 {
            lastLevel = level
            changes.send(level)
        }
    }

    private func displayID() -> CGDirectDisplayID {
        if let cached = cachedDisplayID { return cached }
        var result = CGMainDisplayID()
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            if CGDisplayIsBuiltin(id) != 0 {
                result = id
                break
            }
        }
        cachedDisplayID = result
        return result
    }
}
