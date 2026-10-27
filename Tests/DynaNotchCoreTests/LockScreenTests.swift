import XCTest
@testable import DynaNotchCore

final class LockScreenTests: XCTestCase {
    func testTrackerReportsOnlyChanges() {
        var tracker = LockTransitionTracker()
        XCTAssertNil(tracker.update(locked: false))
        XCTAssertEqual(tracker.update(locked: true), .locked)
        XCTAssertNil(tracker.update(locked: true))
        XCTAssertTrue(tracker.isLocked)
        XCTAssertEqual(tracker.update(locked: false), .unlocked)
        XCTAssertNil(tracker.update(locked: false))
    }

    func testSummaryWeather() {
        let w = WeatherSnapshot(temperature: 11.6, high: 14.4, low: 6.2, code: 3, isDay: true, locationName: "Innsbruck",
                                fetchedAt: Date())
        let s = LockScreenSummary.make(weather: w, devices: [])
        XCTAssertEqual(s.weather?.temperature, "12°")
        XCTAssertEqual(s.weather?.symbol, "cloud.fill")
        XCTAssertEqual(s.weather?.detail, "Overcast · H 14°  L 6°")
        XCTAssertEqual(s.weather?.place, "Innsbruck")
        XCTAssertFalse(s.isEmpty)
        XCTAssertTrue(LockScreenSummary.make(weather: nil, devices: []).isEmpty)
    }

    func testSummaryDevicesOrderLimitAndAirPods() {
        let devices = [
            DeviceBattery(id: "mac", name: "MacBook Pro", kind: .mac, level: 80, isCharging: true),
            DeviceBattery(id: "A", name: "AirPods Pro", kind: .airpods, left: 60, right: 45, caseLevel: 90),
            DeviceBattery(id: "B", name: "MX Master", kind: .mouse, level: 130),
            DeviceBattery(id: "C", name: "Unknown", kind: .other),
            DeviceBattery(id: "D", name: "Keyboard", kind: .keyboard, level: 20),
        ]
        let s = LockScreenSummary.make(weather: nil, devices: devices)
        XCTAssertEqual(s.devices.map(\.id), ["A", "B", "D"])
        XCTAssertEqual(s.devices[0].level, 45)
        XCTAssertEqual(s.devices[1].level, 100)
        let all = LockScreenSummary.make(weather: nil, devices: devices, maxDevices: 10)
        XCTAssertEqual(all.devices.last?.id, "mac")
        XCTAssertEqual(all.devices.last?.isCharging, true)
        XCTAssertTrue(LockScreenSummary.make(weather: nil, devices: devices, maxDevices: 0).devices.isEmpty)
    }

    func testWidgetsRectCentredBelowClock() {
        let screen = CGRect(x: -500, y: 200, width: 3440, height: 1440)
        let r = LockScreenLayout.widgetsRect(size: CGSize(width: 400, height: 110), screenFrame: screen)
        XCTAssertEqual(r.midX, screen.midX)
        XCTAssertEqual(r.maxY, screen.maxY - (1440 * 0.34).rounded())
        XCTAssertEqual(r.size, CGSize(width: 400, height: 110))
    }

    func testLockSoundCategories() {
        XCTAssertEqual(AlertSounds.defaultSound(for: .screenLock), "Pop")
        XCTAssertEqual(AlertSounds.defaultSound(for: .screenUnlock), "Purr")
        XCTAssertEqual(AlertSounds.sound(for: .screenLock, in: "screenLock=None"), AlertSounds.none)
        XCTAssertEqual(AlertCategory.screenUnlock.title, "Unlock")
    }

    func testLockScreenKeys() {
        for key in [SettingsKey.unlockActivity, SettingsKey.lockScreenWidgets, SettingsKey.lockScreenWeather,
                    SettingsKey.lockScreenBatteries] {
            XCTAssertTrue(SettingsKey.all.contains(key))
        }
    }
}
