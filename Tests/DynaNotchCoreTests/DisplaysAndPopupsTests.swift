import XCTest
import CoreGraphics
@testable import DynaNotchCore

final class DisplaysAndPopupsTests: XCTestCase {
    // MARK: Display selection

    func testParseAndSerializeRoundTrip() {
        XCTAssertEqual(DisplaySelection.parse(""), [])
        XCTAssertEqual(DisplaySelection.parse(" 1-2-3 , ,4-5-6"), ["1-2-3", "4-5-6"])
        XCTAssertEqual(DisplaySelection.serialize(["b", "a"]), "a,b")
        XCTAssertEqual(DisplaySelection.key(vendor: 7789, model: 30_000, serial: 0), "7789-30000-0")
    }

    func testToggleHidesAndShows() {
        let connected = ["lg", "dell", "builtin"]
        var stored = DisplaySelection.toggled("", key: "lg", show: false, connected: connected)
        XCTAssertEqual(stored, "lg")
        stored = DisplaySelection.toggled(stored, key: "dell", show: false, connected: connected)
        XCTAssertEqual(DisplaySelection.parse(stored), ["lg", "dell"])
        stored = DisplaySelection.toggled(stored, key: "lg", show: true, connected: connected)
        XCTAssertEqual(stored, "dell")
    }

    func testToggleKeepsTheLastDisplayOn() {
        let stored = DisplaySelection.toggled("dell", key: "lg", show: false, connected: ["lg", "dell"])
        XCTAssertEqual(stored, "dell", "the last display showing the island can't be switched off")
    }

    func testAllowedFallsBackToEveryDisplayWhenAllHidden() {
        let displays: [(id: UInt32, key: String)] = [(1, "builtin"), (2, "lg"), (3, "dell")]
        XCTAssertEqual(DisplaySelection.allowed(displays, hidden: ["lg"]), [1, 3])
        XCTAssertEqual(DisplaySelection.allowed(displays, hidden: ["lg", "dell", "builtin"]), [1, 2, 3])
        XCTAssertEqual(DisplaySelection.allowed(displays, hidden: []), [1, 2, 3])
    }

    func testExtraDisplaysHonourHiddenDisplays() {
        let displays: [(id: UInt32, key: String)] = [(1, "builtin"), (2, "lg"), (3, "dell")]
        XCTAssertEqual(DisplayMode.allDisplays.extraDisplays(all: displays, primary: 1, hidden: ["lg"]), [3])
        XCTAssertEqual(DisplayMode.allDisplays.extraDisplays(all: displays, primary: 1, hidden: []), [2, 3])
        XCTAssertEqual(DisplayMode.main.extraDisplays(all: displays, primary: 1, hidden: []), [])
    }

    // MARK: Full screen

    private let lg = (id: UInt32(2), bounds: CGRect(x: 0, y: 0, width: 3440, height: 1440))
    private let mac = (id: UInt32(1), bounds: CGRect(x: 1928, y: 1440, width: 1512, height: 982))

    func testZoomedWindowWithOtherAppsBehindIsNotFullScreen() {
        // Menu bar auto-hides on the LG: Brave and Thunderbird both fill it, which a real full-screen Space can't do.
        let windows = [
            FullscreenHeuristic.Window(pid: 10, bounds: lg.bounds),
            FullscreenHeuristic.Window(pid: 11, bounds: lg.bounds),
            FullscreenHeuristic.Window(pid: 12, bounds: CGRect(x: 1928, y: 1472, width: 1512, height: 950)),
        ]
        XCTAssertEqual(FullscreenHeuristic.fullscreenDisplays(windows: windows, displays: [lg, mac]), [])
    }

    func testSingleAppFillingADisplayIsFullScreen() {
        let windows = [
            FullscreenHeuristic.Window(pid: 10, bounds: lg.bounds),
            FullscreenHeuristic.Window(pid: 10, bounds: CGRect(x: 100, y: 100, width: 400, height: 300)),
            FullscreenHeuristic.Window(pid: 12, bounds: CGRect(x: 1928, y: 1472, width: 1512, height: 950)),
        ]
        XCTAssertEqual(FullscreenHeuristic.fullscreenDisplays(windows: windows, displays: [lg, mac]), [2])
    }

    func testWindowsOnOtherDisplaysOrTinyDoNotCount() {
        let windows = [
            FullscreenHeuristic.Window(pid: 10, bounds: CGRect(x: 1, y: 0, width: 3440, height: 1441)),
            FullscreenHeuristic.Window(pid: 13, bounds: CGRect(x: 50, y: 50, width: 1, height: 1)),
            FullscreenHeuristic.Window(pid: 14, bounds: CGRect(x: 3440, y: 0, width: 1440, height: 2560)),
        ]
        XCTAssertEqual(FullscreenHeuristic.fullscreenDisplays(windows: windows, displays: [lg, mac]), [2])
    }

    // MARK: Bluetooth popups

    func testBluetoothFilterSkipsUnclassifiedAndNamelessDevices() {
        var filter = BluetoothAlertFilter(cooldown: 20)
        let now = Date()
        XCTAssertFalse(filter.shouldShow(address: "a", kind: .generic, name: "Grinder’s Grinder", now: now))
        XCTAssertFalse(filter.shouldShow(address: "b", kind: .headphones, name: "", now: now))
        XCTAssertTrue(filter.shouldShow(address: "c", kind: .airpodsPro, name: "AirPods Pro", now: now))
    }

    func testBluetoothFilterCoolsDownFlappingDevices() {
        var filter = BluetoothAlertFilter(cooldown: 20)
        let now = Date()
        XCTAssertTrue(filter.shouldShow(address: "x", kind: .headphones, name: "XM6", now: now))
        XCTAssertFalse(filter.shouldShow(address: "x", kind: .headphones, name: "XM6", now: now.addingTimeInterval(5)))
        XCTAssertTrue(filter.shouldShow(address: "y", kind: .mouse, name: "MX", now: now.addingTimeInterval(5)))
        XCTAssertTrue(filter.shouldShow(address: "x", kind: .headphones, name: "XM6", now: now.addingTimeInterval(25)))
    }

    // MARK: Popup targets and buttons

    func testCategoryTargets() {
        XCTAssertEqual(PopupTarget.forCategory(.timers), .tab(.timer))
        XCTAssertEqual(PopupTarget.forCategory(.calendar), .tab(.calendar))
        XCTAssertEqual(PopupTarget.forCategory(.devices), .tab(.system))
        XCTAssertEqual(PopupTarget.forCategory(.aiUsage), .tab(.aiUsage))
        XCTAssertNil(PopupTarget.forCategory(.notifications))
        if case .url(let url)? = PopupTarget.forCategory(.downloads) {
            XCTAssertEqual(url.lastPathComponent, "Downloads")
        } else {
            XCTFail("downloads should open the Downloads folder")
        }
    }

    func testOpenURLAllowsOnlyWebAndFileLinks() {
        XCTAssertEqual(PopupTarget.openURL("https://example.com/a")?.host, "example.com")
        XCTAssertNotNil(PopupTarget.openURL("file:///tmp/x.txt"))
        XCTAssertNil(PopupTarget.openURL("dynanotch://notify?title=x"))
        XCTAssertNil(PopupTarget.openURL("javascript:alert(1)"))
        XCTAssertNil(PopupTarget.openURL(nil))
        XCTAssertNil(PopupTarget.openURL(""))
    }

    func testNotifyParsesOpen() throws {
        let url = try XCTUnwrap(URL(string: "dynanotch://notify?title=Build&body=done&open=https://ci.example.com/1"))
        XCTAssertEqual(NotifyURL.parse(url)?.openURL?.absoluteString, "https://ci.example.com/1")
        let bad = try XCTUnwrap(URL(string: "dynanotch://notify?title=Build&open=ftp://x"))
        XCTAssertNil(NotifyURL.parse(bad)?.openURL)
    }

    func testButtonTitles() {
        XCTAssertEqual(PopupTarget.tab(.calendar).buttonTitle, "Open Calendar")
        XCTAssertEqual(PopupTarget.url(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")).buttonTitle,
                       "Open Activity Monitor")
        XCTAssertEqual(PopupTarget.url(URL(fileURLWithPath: "/Users/x/Downloads")).buttonTitle, "Show in Finder")
        XCTAssertEqual(PopupTarget.url(URL(string: "https://a.b")!).buttonTitle, "Open Link")
    }

    func testHoldsOnHoverAndText() {
        XCTAssertTrue(ActivityKind.notification(title: "a", body: "b", symbol: "").holdsOnHover)
        XCTAssertTrue(ActivityKind.bluetooth(name: "XM6", device: .headphones, battery: 80, connected: true).holdsOnHover)
        XCTAssertFalse(ActivityKind.hud(.volume, level: 0.5, muted: false).holdsOnHover)
        XCTAssertFalse(ActivityKind.agentRequest(id: "1", project: "p", tool: "t", detail: "d").holdsOnHover)
        XCTAssertEqual(ActivityKind.notification(title: "a", body: "b", symbol: "").popupText?.symbol, "bell.fill")
        XCTAssertEqual(ActivityKind.bluetooth(name: "XM6", device: .headphones, battery: 80, connected: true)
            .popupText?.body, "Connected · 80 %")
        XCTAssertEqual(ActivityKind.calendar(title: "Standup", minutesUntil: 5).popupText?.body, "Starts in 5 min")
        XCTAssertEqual(ActivityKind.timerFinished(label: "Tea").defaultPopupTarget, .tab(.timer))
        XCTAssertNil(ActivityKind.notification(title: "a", body: "b", symbol: "").defaultPopupTarget)
        // Every kind that holds has text to show.
        for kind: ActivityKind in [.lowBattery(level: 0.1), .download(name: "f", finished: true),
                                   .vitals(title: "Hot", detail: "d", symbol: "flame")] {
            XCTAssertTrue(kind.holdsOnHover)
            XCTAssertNotNil(kind.popupText)
        }
    }

    func testPopupButtonHitZones() {
        let w: CGFloat = 400, h: CGFloat = 160
        XCTAssertEqual(PopupButton.button(at: CGPoint(x: 50, y: 145), cardWidth: w, cardHeight: h, hasTarget: true), .dismiss)
        XCTAssertEqual(PopupButton.button(at: CGPoint(x: 350, y: 145), cardWidth: w, cardHeight: h, hasTarget: true), .open)
        XCTAssertEqual(PopupButton.button(at: CGPoint(x: 350, y: 145), cardWidth: w, cardHeight: h, hasTarget: false), .dismiss)
        XCTAssertNil(PopupButton.button(at: CGPoint(x: 200, y: 60), cardWidth: w, cardHeight: h, hasTarget: true))
    }

    func testPopupDetailIsBiggerThanTheCompactNotification() {
        let notch = NotchMetrics.fallback
        let p = IslandPresentation.activity(LiveActivity(kind: .notification(title: "a", body: "b", symbol: ""),
                                                         postedAt: Date(), expiresAt: Date()))
        let compact = IslandLayout.size(for: p, notch: notch, hudStyle: .compact)
        let detail = IslandLayout.popupDetailSize(for: p, notch: notch, hudStyle: .compact)
        XCTAssertGreaterThan(detail.width, compact.width)
        XCTAssertGreaterThan(detail.height, compact.height)
    }
}
