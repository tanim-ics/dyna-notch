import Foundation
import Combine
import IOKit.pwr_mgt
import os
import DynaNotchCore

/// Keeps the display (and Mac) awake via an IOPM assertion while on.
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()

    @Published private(set) var isOn = false
    /// When a timed Keep Awake ends (nil = until stopped / off).
    @Published private(set) var until: Date?

    private var assertionID: IOPMAssertionID = 0
    private var expiry: DispatchWorkItem?
    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "keepawake")

    private init() {}

    /// Keeps the Mac awake for `duration` seconds (nil = until stopped), then switches off by itself.
    func keepAwake(for duration: TimeInterval?) {
        set(true)
        guard isOn else { return }
        expiry?.cancel()
        expiry = nil
        guard let duration = duration, duration > 0 else {
            until = nil
            return
        }
        until = Date().addingTimeInterval(duration)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.expiry = nil
            self.set(false)
            self.logger.info("keep awake timer ended")
        }
        expiry = work
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + duration, execute: work)   // wall clock: survives sleep
    }

    /// "1h 05m left", or nil when on until stopped / off.
    func remainingText(now: Date = Date()) -> String? {
        guard let until = until else { return nil }
        let seconds = until.timeIntervalSince(now)
        return seconds > 0 ? Format.countdown(seconds) + " left" : nil
    }

    /// Keeps the Mac awake until a clock time (header menu "Until 18:00"). A time that already passed today means
    /// the same time tomorrow; at least one minute.
    func keepAwake(until date: Date) {
        var target = date
        let now = Date()
        while target <= now, let next = Calendar.current.date(byAdding: .day, value: 1, to: target) { target = next }
        keepAwake(for: max(60, target.timeIntervalSince(now)))
        logger.info("keep awake until \(target, privacy: .public)")
    }

    func toggle() {
        set(!isOn)
    }

    func set(_ on: Bool) {
        if !on {
            expiry?.cancel()
            expiry = nil
            if until != nil { until = nil }
        }
        guard on != isOn else { return }
        if on {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     "DynaNotch Keep Awake" as CFString,
                                                     &id)
            guard result == kIOReturnSuccess else {
                logger.error("IOPMAssertionCreateWithName failed: \(result)")
                return
            }
            assertionID = id
            isOn = true
        } else {
            if assertionID != 0 {
                IOPMAssertionRelease(assertionID)
                assertionID = 0
            }
            isOn = false
        }
    }
}
