import Combine
import Foundation
import IOKit
import IOKit.ps
import os
import DynaNotchCore

/// Internal battery state via IOPowerSources. Desktop Macs (no internal battery) keep `info == nil` and emit nothing.
final class BatteryService: ObservableObject {
    static let shared = BatteryService()

    @Published private(set) var info: BatteryInfo?
    let events = PassthroughSubject<PowerEvent, Never>()
    /// Fires once when the Mac reaches `settings.fullChargeLevel` while plugged in and `settings.fullChargeActivity`
    /// is on (re-armed after unplugging or dropping 5 % below that level).
    let fullyCharged = PassthroughSubject<BatteryInfo, Never>()

    private let logger = Logger(subsystem: "com.tanim.dynanotch", category: "battery")
    private var started = false
    private var detector = PowerEventDetector(thresholds: BatteryService.thresholds(AppSettings.shared.lowBatteryThreshold))
    private var thresholdObserver: AnyCancellable?
    private var fullChargeArmed = false
    private var fullChargeSeeded = false
    private var runLoopSource: CFRunLoopSource?
    private var timer: AnyCancellable?

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        let callback: IOPowerSourceCallbackType = { context in
            guard let context = context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { service.refresh() }
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let unmanaged = IOPSNotificationCreateRunLoopSource(callback, context) {
            let source = unmanaged.takeRetainedValue()
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        } else {
            logger.error("IOPSNotificationCreateRunLoopSource failed")
        }

        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
        thresholdObserver = AppSettings.shared.$lowBatteryThreshold
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] threshold in self?.rebuildDetector(threshold) }
        refresh()
        DrainMonitor.shared.start()
    }

    // MARK: Private (main queue)

    private static func thresholds(_ threshold: Int) -> [Int] {
        threshold > 10 ? [threshold, 10] : [threshold]
    }

    /// New threshold: a fresh detector, seeded with the current reading so changing it does not fire immediately.
    private func rebuildDetector(_ threshold: Int) {
        detector = PowerEventDetector(thresholds: BatteryService.thresholds(threshold))
        if let info = info { _ = detector.update(info) }
    }

    /// Fires `fullyCharged` once when the level reaches `settings.fullChargeLevel` (80…100 %) while plugged in;
    /// re-armed after unplugging or dropping 5 % below the target.
    private func checkFullCharge(_ info: BatteryInfo) {
        let target = Double(min(max(AppSettings.shared.fullChargeLevel, 80), 100)) / 100
        let full = info.isPluggedIn && info.level >= target - 0.005
        defer { fullChargeSeeded = true }
        if full {
            // Already at the target at launch: do not announce.
            if fullChargeArmed && fullChargeSeeded && AppSettings.shared.fullChargeActivity {
                fullyCharged.send(info)
            }
            fullChargeArmed = false
        } else if !info.isPluggedIn || info.level < target - 0.05 {
            fullChargeArmed = true
        }
    }

    private func refresh() {
        guard let newInfo = BatteryService.readInternalBattery() else {
            if info != nil { info = nil }
            return
        }
        if info != newInfo { info = newInfo }
        let newEvents = detector.update(newInfo)
        for event in newEvents { events.send(event) }
        checkFullCharge(newInfo)
    }

    private static func readInternalBattery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            if let present = description[kIOPSIsPresentKey] as? Bool, !present { continue }

            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
            let level = maximum > 0 ? min(max(current / maximum, 0), 1) : 0
            let isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            let state = description[kIOPSPowerSourceStateKey] as? String
            let pluggedIn = state == kIOPSACPowerValue

            var toEmpty: Int?
            if let minutes = (description[kIOPSTimeToEmptyKey] as? NSNumber)?.intValue, minutes > 0, !pluggedIn {
                toEmpty = minutes
            }
            var toFull: Int?
            if let minutes = (description[kIOPSTimeToFullChargeKey] as? NSNumber)?.intValue, minutes > 0, isCharging {
                toFull = minutes
            }
            return BatteryInfo(level: level, isCharging: isCharging, isPluggedIn: pluggedIn,
                               minutesToEmpty: toEmpty, minutesToFull: toFull)
        }
        return nil
    }
}
