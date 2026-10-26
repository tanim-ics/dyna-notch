import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import DynaNotchCore

final class PillSizeTests: XCTestCase {
    private let compact = HUDStyle.compact

    func testDefaultPillIsThickerThanNotch() {
        XCTAssertGreaterThan(IslandLayout.defaultPillHeight, NotchMetrics.fallback.height)
        XCTAssertTrue(IslandLayout.pillHeightRange.contains(IslandLayout.defaultPillHeight))
    }

    func testRestingPillWidthEqualsSetting() {
        let m = IslandLayout.pillMetrics(width: 240, height: 36, notchWidth: 185)
        XCTAssertEqual(IslandLayout.size(for: .idle, notch: m, hudStyle: compact), CGSize(width: 240, height: 36))
        XCTAssertFalse(m.hasPhysicalNotch)
    }

    func testWidthNeverNarrowerThanNotch() {
        // A MacBook Pro notch of ~200 pt: a stored 185 is raised to the notch width.
        let m = IslandLayout.pillMetrics(width: 185, height: 36, notchWidth: 200)
        XCTAssertEqual(IslandLayout.size(for: .idle, notch: m, hudStyle: compact).width, 200)
        for p: IslandPresentation in [.nowPlaying, .lyrics, .timer, .peek] {
            XCTAssertGreaterThanOrEqual(IslandLayout.size(for: p, notch: m, hudStyle: compact).width, 200)
        }
    }

    func testWidthAndHeightClamped() {
        let wide = IslandLayout.pillMetrics(width: 9999, height: 99, notchWidth: 185)
        XCTAssertEqual(IslandLayout.size(for: .idle, notch: wide, hudStyle: compact),
                       CGSize(width: IslandLayout.pillMaxWidth, height: IslandLayout.pillHeightRange.upperBound))
        let thin = IslandLayout.pillMetrics(width: 10, height: 1, notchWidth: 185)
        XCTAssertEqual(IslandLayout.size(for: .idle, notch: thin, hudStyle: compact),
                       CGSize(width: 185, height: IslandLayout.pillHeightRange.lowerBound))
    }

    func testWidthRangeStartsAtNotch() {
        XCTAssertEqual(IslandLayout.pillWidthRange(notchWidth: 198), 198...IslandLayout.pillMaxWidth)
        // A nonsense notch wider than the maximum never inverts the range.
        XCTAssertEqual(IslandLayout.pillWidthRange(notchWidth: 900), IslandLayout.pillMaxWidth...IslandLayout.pillMaxWidth)
    }

    func testClosedPillSizeKeepsOnScreenSize() {
        // Closed Pill Size 85 %: the resting pill still shows exactly the notch width and the set height.
        let m = IslandLayout.pillMetrics(width: 185, height: 36, notchWidth: 185, scale: 0.85)
        let shown = IslandLayout.scaled(IslandLayout.size(for: .idle, notch: m, hudStyle: compact), by: 0.85)
        XCTAssertEqual(shown.width, 185, accuracy: 0.001)
        XCTAssertEqual(shown.height, 36, accuracy: 0.001)
    }

    func testNowPlayingPillAddsSidesToRestingWidth() {
        let m = IslandLayout.pillMetrics(width: 200, height: 40, notchWidth: 185)
        let size = IslandLayout.size(for: .nowPlaying, notch: m, hudStyle: compact)
        XCTAssertEqual(size, CGSize(width: 200 + 2 * IslandLayout.sideWidth(for: .nowPlaying, hudStyle: compact), height: 40))
    }
}

final class DisplayModeExtrasTests: XCTestCase {
    func testEveryDisplayAddsAllButPrimary() {
        XCTAssertEqual(DisplayMode.allDisplays.extraDisplays(all: [1, 2, 3], primary: 2), [1, 3])
        XCTAssertEqual(DisplayMode.allDisplays.extraDisplays(all: [1, 2, 2, 3, 1], primary: 1), [2, 3])
    }

    func testSingleIslandModesAddNothing() {
        for mode in DisplayMode.allCases where mode != .allDisplays {
            XCTAssertEqual(mode.extraDisplays(all: [1, 2, 3], primary: 1), [], "\(mode)")
        }
    }

    func testNoPrimaryOrSingleDisplay() {
        XCTAssertEqual(DisplayMode.allDisplays.extraDisplays(all: [7], primary: 7), [])
        XCTAssertEqual(DisplayMode.allDisplays.extraDisplays(all: [4, 5], primary: nil), [4, 5])
        XCTAssertEqual(DisplayMode.allDisplays.extraDisplays(all: [], primary: 1), [])
    }
}
