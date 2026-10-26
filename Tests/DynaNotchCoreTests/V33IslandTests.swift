import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import DynaNotchCore

final class V33IslandTests: XCTestCase {
    private let notch = NotchMetrics(width: 185, height: 32, hasPhysicalNotch: false)

    func testUnpluggedChargingIsWider() {
        let now = Date()
        let plugged = IslandPresentation.activity(LiveActivity(kind: .charging(level: 0.5, isCharging: true, pluggedIn: true),
                                                               postedAt: now, expiresAt: now))
        let unplugged = IslandPresentation.activity(LiveActivity(kind: .charging(level: 0.5, isCharging: false, pluggedIn: false),
                                                                 postedAt: now, expiresAt: now))
        XCTAssertEqual(IslandLayout.sideWidth(for: plugged, hudStyle: .compact), 64)
        XCTAssertEqual(IslandLayout.sideWidth(for: unplugged, hudStyle: .compact), IslandLayout.unpluggedSide)
    }

    func testTimerControlsSize() {
        let size = IslandLayout.timerControlsSize(notch: notch)
        XCTAssertEqual(size.width, 185 + 12 + 128)
        XCTAssertEqual(size.height, 32 + IslandLayout.timerControlsExtraHeight)
        XCTAssertGreaterThan(size.height, IslandLayout.size(for: .timer, notch: notch, hudStyle: .compact).height)
    }

    func testPillScaleClamped() {
        let base = CGSize(width: 200, height: 30)
        XCTAssertEqual(IslandLayout.scaled(base, by: 1.2), CGSize(width: 240, height: 36))
        XCTAssertEqual(IslandLayout.scaled(base, by: 3), CGSize(width: 260, height: 39))
        XCTAssertEqual(IslandLayout.scaled(base, by: 0.1), CGSize(width: 160, height: 24))
    }

    func testQuietDuringFocus() {
        XCTAssertTrue(ActivityKind.hud(.volume, level: 0.5, muted: false).isQuietedDuringFocus)
        XCTAssertTrue(ActivityKind.toggle(symbol: "x", label: "Caps", on: true).isQuietedDuringFocus)
        XCTAssertTrue(ActivityKind.bluetooth(name: "A", device: .airpods, battery: nil, connected: true).isQuietedDuringFocus)
        XCTAssertTrue(ActivityKind.download(name: "a", finished: true).isQuietedDuringFocus)
        XCTAssertTrue(ActivityKind.notification(title: "t", body: "b", symbol: "s").isQuietedDuringFocus)
        XCTAssertTrue(ActivityKind.calendar(title: "c", minutesUntil: 5).isQuietedDuringFocus)
        XCTAssertFalse(ActivityKind.lowBattery(level: 0.1).isQuietedDuringFocus)
        XCTAssertFalse(ActivityKind.timerFinished(label: "t").isQuietedDuringFocus)
        XCTAssertFalse(ActivityKind.sensor(.camera, active: true).isQuietedDuringFocus)
    }
}
