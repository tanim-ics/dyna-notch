import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import DynaNotchCore

final class V34IslandTests: XCTestCase {
    private let notch = NotchMetrics(width: 185, height: 32, hasPhysicalNotch: true)

    func testFixedSizingUsesMaxHeight() {
        XCTAssertEqual(IslandLayout.expandedContentHeight(tab: .shelf, sizing: .fixed, maxHeight: 250), 250)
        XCTAssertEqual(IslandLayout.expandedContentHeight(tab: .shelf, sizing: .fixed, maxHeight: 999), 320)
        XCTAssertEqual(IslandLayout.expandedContentHeight(tab: .shelf, sizing: .fixed, maxHeight: 10), 150)
    }

    func testFitContentClampsToMax() {
        XCTAssertEqual(IslandLayout.expandedContentHeight(tab: .shelf, sizing: .fitContent, maxHeight: 320), 160)
        XCTAssertEqual(IslandLayout.expandedContentHeight(tab: .clipboard, sizing: .fitContent, maxHeight: 200), 200)
        XCTAssertEqual(IslandLayout.expandedContentHeight(tab: .clipboard, sizing: .fitContent, maxHeight: 320), 240)
        for tab in PanelTab.allCases {
            let h = IslandLayout.expandedContentHeight(tab: tab, sizing: .fitContent, maxHeight: 320)
            XCTAssertTrue(IslandLayout.panelMaxHeightRange.contains(h), "\(tab)")
        }
    }

    func testExpandedSizeClampsWidth() {
        XCTAssertEqual(IslandLayout.expandedSize(notch: notch, width: 700, contentHeight: 190),
                       CGSize(width: 700, height: 222))
        XCTAssertEqual(IslandLayout.expandedSize(notch: notch, width: 2000, contentHeight: 190).width, 820)
        XCTAssertEqual(IslandLayout.expandedSize(notch: notch, width: 100, contentHeight: 190).width, 520)
        let wide = NotchMetrics(width: 400, height: 38, hasPhysicalNotch: true)
        XCTAssertEqual(IslandLayout.expandedSize(notch: wide, width: 520, contentHeight: 150).width, 400 + 28 + 160)
    }

    func testCanvasGrowsOnlyWhenNeeded() {
        XCTAssertEqual(IslandLayout.canvasSize(panelWidth: 640, panelMaxHeight: 190, notchHeight: 32), IslandLayout.canvasSize)
        let big = IslandLayout.canvasSize(panelWidth: 820, panelMaxHeight: 320, notchHeight: 38)
        XCTAssertEqual(big, CGSize(width: 900, height: 398))
        let rect = IslandLayout.canvasRect(for: CGSize(width: 820, height: 358), canvas: big)
        XCTAssertEqual(rect.minX, 40)
        let frame = IslandLayout.panelFrame(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), canvas: big)
        XCTAssertEqual(frame, CGRect(x: 306, y: 584, width: 900, height: 398))
    }
}
