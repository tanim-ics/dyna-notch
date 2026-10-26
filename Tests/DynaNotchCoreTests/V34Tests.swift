import XCTest
@testable import DynaNotchCore

final class HotKeyMapTests: XCTestCase {
    func testDefaultsAndDisplay() {
        let map = HotKeyMap.parse("")
        XCTAssertEqual(map.binding(for: .togglePanel)?.display, "⌃⌥N")
        XCTAssertEqual(map.binding(for: .hide)?.display, "⌥Space")
        XCTAssertEqual(map.binding(for: .emergencyQuit)?.display, "⌃⌥⌘Q")
        XCTAssertNil(map.binding(for: HotKeyMap.tabKey(.timer)))
        XCTAssertEqual(map.serialize(), "")
    }

    func testOverrideClearAndRoundTrip() {
        var map = HotKeyMap.parse("hide=;tab.timer=17:6144")
        XCTAssertNil(map.binding(for: .hide))
        XCTAssertEqual(map.binding(for: "tab.timer"), HotKeyBinding(keyCode: 17, modifiers: 6144))
        map.bindings["togglePanel"] = HotKeyBinding(keyCode: 45, modifiers: 6144 | 256)
        let again = HotKeyMap.parse(map.serialize())
        XCTAssertEqual(again, map)
        XCTAssertEqual(again.conflict(for: HotKeyBinding(keyCode: 17, modifiers: 6144), excluding: "x"), "tab.timer")
    }
}

final class KnockDetectorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testDoubleTap() {
        var d = KnockDetector()
        d.press(at: t0); d.release(at: t0.addingTimeInterval(0.08))
        d.press(at: t0.addingTimeInterval(0.2)); d.release(at: t0.addingTimeInterval(0.27))
        XCTAssertNil(d.settle(now: t0.addingTimeInterval(0.4)))
        XCTAssertEqual(d.settle(now: t0.addingTimeInterval(0.7)), 2)
        XCTAssertNil(d.settle(now: t0.addingTimeInterval(1.0)))
    }

    func testHoldAndInterruptAreNotKnocks() {
        var d = KnockDetector()
        d.press(at: t0); d.release(at: t0.addingTimeInterval(0.6))
        XCTAssertNil(d.settle(now: t0.addingTimeInterval(2)))
        d.press(at: t0.addingTimeInterval(3)); d.interrupt(); d.release(at: t0.addingTimeInterval(3.1))
        XCTAssertNil(d.settle(now: t0.addingTimeInterval(4)))
    }

    func testActionMapRoundTrip() {
        let map = KnockAction.parseMap("1=togglePanel,3=lockScreen,9=clipboard,2=bogus")
        XCTAssertEqual(map, [1: .togglePanel, 3: .lockScreen])
        XCTAssertEqual(KnockAction.serializeMap(map), "1=togglePanel,3=lockScreen")
    }
}

final class WorkspaceTypesTests: XCTestCase {
    func testHomeCards() {
        XCTAssertEqual(HomeCard.parseList(""), HomeCard.defaultList)
        XCTAssertEqual(HomeCard.parseList("weather,bogus,weather,music"), [.weather, .music])
        XCTAssertEqual(HomeCard.slotsUsed([.music, .weather]), 3)
    }

    func testAlertSounds() {
        XCTAssertEqual(AlertSounds.sound(for: .timers, in: ""), "Glass")
        XCTAssertEqual(AlertSounds.sound(for: .battery, in: ""), "None")
        let s = AlertSounds.setting("Hero", for: .battery, in: "timers=Ping")
        XCTAssertEqual(s, "timers=Ping,battery=Hero")
        XCTAssertEqual(AlertSounds.sound(for: .battery, in: s), "Hero")
    }

    func testJSONListAndHistory() {
        let links = [SavedLink(title: "GitHub", url: "https://github.com")]
        XCTAssertEqual(JSONList.decode(JSONList.encode(links), as: SavedLink.self), links)
        XCTAssertEqual(JSONList.decode("garbage", as: SavedLink.self), [])

        var history = ListeningHistory(limit: 2)
        let now = Date()
        history.record(ListenEntry(title: "A", artist: "x", playedAt: now))
        history.record(ListenEntry(title: "A", artist: "x", playedAt: now))   // same as newest → ignored
        XCTAssertEqual(history.entries.count, 1)
        history.toggleBookmark(id: history.entries[0].id)
        history.record(ListenEntry(title: "B", artist: "x", playedAt: now))
        history.record(ListenEntry(title: "C", artist: "x", playedAt: now))
        XCTAssertEqual(history.entries.map(\.title), ["C", "A"])   // B evicted, bookmarked A kept
        history.clear()
        XCTAssertEqual(history.entries.map(\.title), ["A"])
    }

    func testTrafficLedger() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        let day1 = Date(timeIntervalSince1970: 86_400 * 100 + 10)
        var ledger = TrafficLedger()
        ledger.add(received: 100, sent: 10, at: day1, calendar: cal)
        ledger.add(received: 50, sent: 5, at: day1.addingTimeInterval(60), calendar: cal)
        ledger.add(received: 7, sent: 1, at: day1.addingTimeInterval(86_400), calendar: cal)
        XCTAssertEqual(ledger.days.count, 2)
        let total = ledger.total(lastDays: 2, now: day1.addingTimeInterval(86_400), calendar: cal)
        XCTAssertEqual(total.received, 157)
        XCTAssertEqual(ledger.total(lastDays: 1, now: day1.addingTimeInterval(86_400), calendar: cal).sent, 1)
        ledger.prune(keepDays: 0, now: day1.addingTimeInterval(86_400), calendar: cal)
        XCTAssertEqual(ledger.days.count, 1)
    }

    func testRepeatCountdown() {
        var engine = TimerEngine()
        engine.repeatCountdown = true
        let t0 = Date(timeIntervalSince1970: 0)
        engine.startCountdown(seconds: 60, label: "Tea", now: t0)
        XCTAssertEqual(engine.tick(now: t0.addingTimeInterval(61)), .countdownFinished(label: "Tea"))
        XCTAssertTrue(engine.isActive)
        XCTAssertEqual(engine.state?.remaining(at: t0.addingTimeInterval(61)) ?? 0, 59, accuracy: 0.01)
        engine.repeatCountdown = false
        _ = engine.tick(now: t0.addingTimeInterval(125))
        XCTAssertFalse(engine.isActive)
    }

    func testPanelTabMigrationAddsNewTabs() {
        let v32 = "home,nowPlaying,timer,clipboard,shelf,notes,calculator,emoji,quickSearch,launcher,shortcuts,reminders,mirror,system,aiUsage"
        let migrated = PanelTab.parseList(PanelTab.migrate(stored: v32, known: v32))
        XCTAssertTrue(migrated.contains(.calendar))
        XCTAssertTrue(migrated.contains(.quickSettings))
        XCTAssertEqual(migrated.suffix(2), [.system, .aiUsage])
    }
}

final class SunTimesTests: XCTestCase {
    func testSunriseSunsetParsing() throws {
        let json = """
        {"utc_offset_seconds":3600,"current":{"temperature_2m":10,"weather_code":3,"is_day":1},
         "daily":{"temperature_2m_max":[11],"temperature_2m_min":[2],"sunrise":["2026-10-26T07:12"],"sunset":["2026-10-26T17:01"]}}
        """
        let snap = try XCTUnwrap(OpenMeteoParser.parse(Data(json.utf8), locationName: "X", now: Date()))
        XCTAssertEqual(snap.sunrise, OpenMeteoParser.localISO("2026-10-26T06:12", utcOffset: 0))
        XCTAssertNotNil(snap.sunset)
        XCTAssertNil(OpenMeteoParser.localISO("garbage", utcOffset: 0))
    }
}
