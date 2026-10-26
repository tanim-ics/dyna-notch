import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import DynaNotchCore

final class NotchMetricsTests: XCTestCase {
    func testFallback() {
        XCTAssertEqual(NotchMetrics.fallback, NotchMetrics(width: 185, height: 32, hasPhysicalNotch: false))
    }

    func testPhysicalNotchUsesAuxWidths() {
        let m = NotchMetrics.compute(screenWidth: 1512, safeAreaTop: 38, leftAuxWidth: 662, rightAuxWidth: 662,
                                     menuBarHeight: 37)
        XCTAssertEqual(m, NotchMetrics(width: 188, height: 38, hasPhysicalNotch: true))
    }

    func testPhysicalNotchMissingAuxFallsBackTo185() {
        let m = NotchMetrics.compute(screenWidth: 1512, safeAreaTop: 32, leftAuxWidth: nil, rightAuxWidth: 600,
                                     menuBarHeight: 24)
        XCTAssertEqual(m.width, 185)
        XCTAssertEqual(m.height, 32)
        XCTAssertTrue(m.hasPhysicalNotch)
    }

    func testPhysicalNotchOutOfRangeFallsBack() {
        let tooWide = NotchMetrics.compute(screenWidth: 1512, safeAreaTop: 32, leftAuxWidth: 100, rightAuxWidth: 100,
                                           menuBarHeight: 24)
        XCTAssertEqual(tooWide.width, 185)
        let tooNarrow = NotchMetrics.compute(screenWidth: 1512, safeAreaTop: 32, leftAuxWidth: 740, rightAuxWidth: 740,
                                             menuBarHeight: 24)
        XCTAssertEqual(tooNarrow.width, 185)
    }

    func testPhysicalNotchRangeBoundsInclusive() {
        let low = NotchMetrics.compute(screenWidth: 1000, safeAreaTop: 32, leftAuxWidth: 460, rightAuxWidth: 460,
                                       menuBarHeight: 24)
        XCTAssertEqual(low.width, 80)
        let high = NotchMetrics.compute(screenWidth: 1000, safeAreaTop: 32, leftAuxWidth: 300, rightAuxWidth: 300,
                                        menuBarHeight: 24)
        XCTAssertEqual(high.width, 400)
    }

    func testNoNotchUsesMenuBarHeightWithMinimum() {
        let tall = NotchMetrics.compute(screenWidth: 2560, safeAreaTop: 0, leftAuxWidth: nil, rightAuxWidth: nil,
                                        menuBarHeight: 30)
        XCTAssertEqual(tall, NotchMetrics(width: 185, height: 30, hasPhysicalNotch: false))
        let short = NotchMetrics.compute(screenWidth: 2560, safeAreaTop: 0, leftAuxWidth: 10, rightAuxWidth: 10,
                                         menuBarHeight: 0)
        XCTAssertEqual(short, NotchMetrics(width: 185, height: 24, hasPhysicalNotch: false))
    }
}

final class IslandLayoutTests: XCTestCase {
    let notch = NotchMetrics(width: 200, height: 32, hasPhysicalNotch: true)
    let t0 = Date(timeIntervalSince1970: 1_000)

    func activity(_ kind: ActivityKind) -> IslandPresentation {
        .activity(LiveActivity(kind: kind, postedAt: t0, expiresAt: t0.addingTimeInterval(2)))
    }

    var hud: IslandPresentation { activity(.hud(.volume, level: 0.5, muted: false)) }

    func testConstants() {
        XCTAssertEqual(IslandLayout.canvasSize, CGSize(width: 720, height: 320))
        XCTAssertEqual(IslandLayout.expandedWidth, 640)
        XCTAssertEqual(IslandLayout.expandedContentHeight, 190)
    }

    func testIdleSize() {
        XCTAssertEqual(IslandLayout.size(for: .idle, notch: notch, hudStyle: .compact), CGSize(width: 212, height: 32))
    }

    func testHiddenSizeIsZero() {
        XCTAssertEqual(IslandLayout.size(for: .hidden, notch: notch, hudStyle: .compact), .zero)
    }

    func testNowPlayingSize() {
        XCTAssertEqual(IslandLayout.size(for: .nowPlaying, notch: notch, hudStyle: .compact),
                       CGSize(width: 200 + 12 + 88, height: 32))
    }

    func testPeekSize() {
        XCTAssertEqual(IslandLayout.size(for: .peek, notch: notch, hudStyle: .compact),
                       CGSize(width: 200 + 16 + 220, height: 68))
    }

    func testExpandedSize() {
        XCTAssertEqual(IslandLayout.size(for: .expanded, notch: notch, hudStyle: .compact),
                       CGSize(width: 640, height: 222))
        let wide = NotchMetrics(width: 500, height: 38, hasPhysicalNotch: true)
        XCTAssertEqual(IslandLayout.size(for: .expanded, notch: wide, hudStyle: .compact),
                       CGSize(width: 500 + 28 + 160, height: 228))
    }

    func testHUDCompactSize() {
        XCTAssertEqual(IslandLayout.sideWidth(for: hud, hudStyle: .compact), 72)
        XCTAssertEqual(IslandLayout.size(for: hud, notch: notch, hudStyle: .compact),
                       CGSize(width: 200 + 12 + 144, height: 32))
    }

    func testHUDExpandedStyleSize() {
        XCTAssertEqual(IslandLayout.sideWidth(for: hud, hudStyle: .expanded), 60)
        XCTAssertEqual(IslandLayout.size(for: hud, notch: notch, hudStyle: .expanded),
                       CGSize(width: 200 + 16 + 120, height: 66))
    }

    func testActivitySideWidths() {
        let cases: [(ActivityKind, CGFloat)] = [
            (.charging(level: 0.5, isCharging: true, pluggedIn: true), 64),
            (.lowBattery(level: 0.1), 64),
            (.bluetooth(name: "AirPods", device: .airpods, battery: 80, connected: true), 84),
            (.focus(name: "Work", symbol: "briefcase.fill", enabled: true), 72),
            (.calendar(title: "Standup", minutesUntil: 5), 96),
        ]
        for (kind, side) in cases {
            for style in HUDStyle.allCases {
                let p = activity(kind)
                XCTAssertEqual(IslandLayout.sideWidth(for: p, hudStyle: style), side, "\(kind)")
                XCTAssertEqual(IslandLayout.size(for: p, notch: notch, hudStyle: style),
                               CGSize(width: 212 + 2 * side, height: 32), "\(kind)")
            }
        }
    }

    func testNonCompactSideWidthsAreZero() {
        for p in [IslandPresentation.idle, .expanded, .hidden] {
            XCTAssertEqual(IslandLayout.sideWidth(for: p, hudStyle: .compact), 0)
        }
        XCTAssertEqual(IslandLayout.sideWidth(for: .nowPlaying, hudStyle: .compact), 44)
        XCTAssertEqual(IslandLayout.sideWidth(for: .peek, hudStyle: .expanded), 110)
    }

    func testRadii() {
        XCTAssertEqual(IslandLayout.radii(for: .idle, hudStyle: .compact), IslandRadii(top: 6, bottom: 9))
        XCTAssertEqual(IslandLayout.radii(for: .hidden, hudStyle: .compact), IslandRadii(top: 6, bottom: 9))
        XCTAssertEqual(IslandLayout.radii(for: .nowPlaying, hudStyle: .compact), IslandRadii(top: 6, bottom: 11))
        XCTAssertEqual(IslandLayout.radii(for: .peek, hudStyle: .compact), IslandRadii(top: 8, bottom: 16))
        XCTAssertEqual(IslandLayout.radii(for: .expanded, hudStyle: .compact), IslandRadii(top: 14, bottom: 28))
        XCTAssertEqual(IslandLayout.radii(for: hud, hudStyle: .compact), IslandRadii(top: 6, bottom: 11))
        XCTAssertEqual(IslandLayout.radii(for: hud, hudStyle: .expanded), IslandRadii(top: 8, bottom: 16))
        let charging = activity(.charging(level: 1, isCharging: false, pluggedIn: true))
        XCTAssertEqual(IslandLayout.radii(for: charging, hudStyle: .expanded), IslandRadii(top: 6, bottom: 11))
    }

    func testCanvasRect() {
        XCTAssertEqual(IslandLayout.canvasRect(for: CGSize(width: 300, height: 40)),
                       CGRect(x: 210, y: 0, width: 300, height: 40))
        XCTAssertEqual(IslandLayout.canvasRect(for: .zero), CGRect(x: 360, y: 0, width: 0, height: 0))
    }

    func testScreenRect() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(IslandLayout.screenRect(for: CGSize(width: 212, height: 32), screenFrame: screen),
                       CGRect(x: 650, y: 950, width: 212, height: 32))
        let secondary = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(IslandLayout.screenRect(for: CGSize(width: 100, height: 30), screenFrame: secondary),
                       CGRect(x: 1512 + 960 - 50, y: 850, width: 100, height: 30))
    }

    func testPanelFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(IslandLayout.panelFrame(screenFrame: screen), CGRect(x: 396, y: 662, width: 720, height: 320))
        let offset = CGRect(x: -1920, y: 100, width: 1920, height: 1200)
        XCTAssertEqual(IslandLayout.panelFrame(screenFrame: offset),
                       CGRect(x: -960 - 360, y: 980, width: 720, height: 320))
    }

    func testHUDStyleTitles() {
        XCTAssertEqual(HUDStyle.compact.title, "Compact")
        XCTAssertEqual(HUDStyle.expanded.title, "Expanded")
    }
}
