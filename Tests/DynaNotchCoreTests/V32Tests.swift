import XCTest
@testable import DynaNotchCore

final class CalculatorTests: XCTestCase {
    private func eval(_ s: String) -> Double? { Calculator.evaluate(s) }

    func testArithmeticAndPrecedence() {
        XCTAssertEqual(eval("1 + 2 * 3"), 7)
        XCTAssertEqual(eval("(1 + 2) * 3"), 9)
        XCTAssertEqual(eval("2 ^ 3 ^ 2"), 512)
        XCTAssertEqual(eval("-2 ^ 2"), 4)
        XCTAssertEqual(eval("10 / 4"), 2.5)
        XCTAssertEqual(eval("7 % 3"), 1)
        XCTAssertEqual(eval("3 × 4 ÷ 2"), 6)
        XCTAssertEqual(eval("3x4"), 12)
        XCTAssertEqual(eval("2+2="), 4)
    }

    func testPercent() {
        XCTAssertEqual(eval("50%"), 0.5)
        XCTAssertEqual(eval("200 * 15%"), 30)
        XCTAssertEqual(eval("200 + 10%"), 220)
        XCTAssertEqual(eval("200 - 10%"), 180)
        XCTAssertEqual(eval("10% + 5"), 5.1)
    }

    func testFunctionsConstantsAndNumbers() {
        XCTAssertEqual(eval("sqrt(16) + abs(-2)"), 6)
        XCTAssertEqual(eval("sqrt 9"), 3)
        XCTAssertEqual(eval("pi")!, Double.pi, accuracy: 1e-12)
        XCTAssertEqual(eval("2e3 + 1"), 2001)
        XCTAssertEqual(eval("1,234 + 1"), 1235)
        XCTAssertEqual(eval("log(1000)")!, 3, accuracy: 1e-12)
        XCTAssertEqual(eval("ln e")!, 1, accuracy: 1e-12)
    }

    func testInvalidInput() {
        XCTAssertNil(eval(""))
        XCTAssertNil(eval("1 / 0"))
        XCTAssertNil(eval("2 +"))
        XCTAssertNil(eval("(1 + 2"))
        XCTAssertNil(eval("hello"))
        XCTAssertNil(eval("rm -rf /"))
        XCTAssertNil(eval("sqrt(-1)"))
    }

    func testFormat() {
        XCTAssertEqual(Calculator.format(12), "12")
        XCTAssertEqual(Calculator.format(0.5), "0.5")
        XCTAssertEqual(Calculator.format(1234567.891), "1,234,567.891")
        XCTAssertEqual(Calculator.format(-0.0000000000001), "0")
        XCTAssertEqual(Calculator.format(1e21), "1e+21")
        XCTAssertEqual(Calculator.format(.infinity), "Error")
    }
}

final class QuickSearchEmojiTests: XCTestCase {
    func testResolveShortcutsAndDefault() {
        let gh = QuickSearch.resolve("gh swift ui", defaultEngineID: "google")
        XCTAssertEqual(gh?.engine?.id, "github")
        XCTAssertEqual(gh?.url.absoluteString, "https://github.com/search?q=swift%20ui")
        let plain = QuickSearch.resolve("what is a notch", defaultEngineID: "duckduckgo")
        XCTAssertEqual(plain?.engine?.id, "duckduckgo")
        XCTAssertEqual(plain?.query, "what is a notch")
        let unknown = QuickSearch.resolve("zz top", defaultEngineID: "nope")
        XCTAssertEqual(unknown?.engine?.id, "google")
        XCTAssertNil(QuickSearch.resolve("   ", defaultEngineID: "google"))
        XCTAssertEqual(QuickSearch.resolve("c++ & rust?", defaultEngineID: "google")?.url.absoluteString,
                       "https://www.google.com/search?q=c%2B%2B%20%26%20rust%3F")
    }

    func testResolveDirectURLs() {
        XCTAssertEqual(QuickSearch.resolve("apple.com", defaultEngineID: "google")?.url.absoluteString, "https://apple.com")
        XCTAssertEqual(QuickSearch.resolve("https://x.org/a?b=1", defaultEngineID: "google")?.url.absoluteString,
                       "https://x.org/a?b=1")
        XCTAssertNil(QuickSearch.resolve("localhost:3000", defaultEngineID: "google")?.engine)
        XCTAssertNotNil(QuickSearch.resolve("version 1.2", defaultEngineID: "google")?.engine)
        XCTAssertNotNil(QuickSearch.resolve("3.14", defaultEngineID: "google")?.engine)
    }

    func testEngineMetadata() {
        XCTAssertEqual(Set(QuickSearch.builtIn.map(\.shortcut)).count, QuickSearch.builtIn.count)
        XCTAssertTrue(QuickSearch.builtIn.allSatisfy { $0.template.contains("%@") })
    }

    func testEmojiCatalog() {
        let all = EmojiCatalog.all
        XCTAssertGreaterThan(all.count, 300)
        XCTAssertEqual(Set(all.map(\.character)).count, all.count)
        XCTAssertTrue(all.contains { $0.character == "😀" && $0.name == "grinning face" })
        XCTAssertTrue(EmojiCatalog.search("thumbs up").contains { $0.character == "👍" })
        XCTAssertTrue(EmojiCatalog.search("CAT").contains { $0.character == "🐈" })
        XCTAssertEqual(EmojiCatalog.search("").count, all.count)
        XCTAssertTrue(EmojiCatalog.search("zzqqx").isEmpty)
        XCTAssertEqual(EmojiGroup.allCases.count, 8)
    }
}

final class WellbeingTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? .current
        return c
    }

    func testBreakScheduler() {
        var s = BreakScheduler()
        let intervals: [BreakKind: Int] = [.lookAway: 20, .standUp: 60]
        XCTAssertEqual(s.due(now: t0 + 1199, start: t0, intervals: intervals, isQuiet: false), [])
        XCTAssertEqual(s.due(now: t0 + 1200, start: t0, intervals: intervals, isQuiet: false), [.lookAway])
        XCTAssertEqual(s.due(now: t0 + 2000, start: t0, intervals: intervals, isQuiet: false), [])
        XCTAssertEqual(s.due(now: t0 + 3600, start: t0, intervals: intervals, isQuiet: true), [])
        XCTAssertEqual(s.due(now: t0 + 3600, start: t0, intervals: intervals, isQuiet: false), [.lookAway, .standUp])
        s.reset(now: t0 + 4000)
        XCTAssertEqual(s.due(now: t0 + 4100, start: t0, intervals: intervals, isQuiet: false), [])
        XCTAssertEqual(BreakKind.drinkWater.symbol, "drop.fill")
    }

    func testPomodoroStats() throws {
        var p = PomodoroStats()
        let day = 86400.0
        p.recordSession(at: t0 - 2 * day, calendar: utc)
        p.recordSession(at: t0 - day, calendar: utc)
        p.recordSession(at: t0, calendar: utc)
        p.recordSession(at: t0 + 60, calendar: utc)
        XCTAssertEqual(p.today(now: t0, calendar: utc), 2)
        XCTAssertEqual(p.total, 4)
        XCTAssertEqual(p.streak(now: t0, calendar: utc), 3)
        XCTAssertEqual(p.streak(now: t0 + day, calendar: utc), 3)      // nothing yet today → count from yesterday
        XCTAssertEqual(p.streak(now: t0 + 3 * day, calendar: utc), 0)
        let decoded = try JSONDecoder().decode(PomodoroStats.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }

    func testBatteryHistory() {
        var h = BatteryHistory()
        XCTAssertTrue(h.append(BatterySample(date: t0, level: 80, charging: false)))
        XCTAssertFalse(h.append(BatterySample(date: t0 + 60, level: 79, charging: false)))
        XCTAssertTrue(h.append(BatterySample(date: t0 + 61, level: 79, charging: true)))   // state change
        XCTAssertTrue(h.append(BatterySample(date: t0 + 400, level: 81, charging: true)))
        XCTAssertFalse(h.append(BatterySample(date: t0 + 10, level: 50, charging: true)))   // out of order
        XCTAssertEqual(h.samples(since: t0 + 61).count, 2)
        h.append(BatterySample(date: t0 + 31 * 86400, level: 50, charging: false))
        XCTAssertEqual(h.samples.count, 1)
    }

    func testScreenTime() {
        var l = ScreenTimeLedger()
        l.record(app: "com.apple.Safari", name: "Safari", from: t0, to: t0 + 600, calendar: utc)
        l.record(app: "com.apple.dt.Xcode", from: t0 + 600, to: t0 + 1800, calendar: utc)
        l.record(app: "com.apple.Safari", from: t0 + 1800, to: t0 + 2100, calendar: utc)
        l.record(app: "bad", from: t0, to: t0 - 5, calendar: utc)
        l.record(app: "sleep", from: t0, to: t0 + 7200, calendar: utc)
        let top = l.top(on: t0, calendar: utc)
        XCTAssertEqual(top.map(\.app), ["com.apple.dt.Xcode", "com.apple.Safari"])
        XCTAssertEqual(top[1].seconds, 900)
        XCTAssertEqual(l.total(on: t0, calendar: utc), 2100)
        XCTAssertEqual(l.names["com.apple.Safari"], "Safari")
        // Spans across midnight are split.
        let midnight = utc.startOfDay(for: t0).addingTimeInterval(86400)
        l.record(app: "night", from: midnight - 300, to: midnight + 300, calendar: utc)
        XCTAssertEqual(l.top(on: midnight, calendar: utc).first?.seconds, 300)
        l.prune(keepDays: 0, now: midnight, calendar: utc)
        XCTAssertEqual(l.total(on: t0, calendar: utc), 0)
    }

    func testMeetingLinks() {
        XCTAssertEqual(MeetingLink.detect(in: [nil, "Join: https://us02web.zoom.us/j/123456?pwd=abc."])?.absoluteString,
                       "https://us02web.zoom.us/j/123456?pwd=abc")
        XCTAssertEqual(MeetingLink.detect(in: ["https://meet.google.com/abc-defg-hij"])?.host, "meet.google.com")
        XCTAssertEqual(MeetingLink.detect(in: ["Room 2", "<https://teams.microsoft.com/l/meetup-join/19%3a>"])?.host,
                       "teams.microsoft.com")
        XCTAssertNil(MeetingLink.detect(in: ["https://example.com/zoom.us/j/1", nil, ""]))
    }

    func testAccessoryAlerts() {
        var d = AccessoryAlertDetector(lowThreshold: 20)
        let mouse = { (level: Int, charging: Bool) in
            DeviceBattery(id: "m", name: "Mouse", kind: .mouse, level: level, isCharging: charging)
        }
        XCTAssertEqual(d.update([mouse(15, false)]), [])                   // first update only seeds
        XCTAssertEqual(d.update([mouse(14, false)]), [])
        XCTAssertEqual(d.update([mouse(35, true)]), [])                    // re-armed above 30
        XCTAssertEqual(d.update([mouse(19, false)]), [.low(mouse(19, false))])
        XCTAssertEqual(d.update([mouse(100, true)]), [.full(mouse(100, true))])
        XCTAssertEqual(d.update([mouse(100, true)]), [])
        let mac = DeviceBattery(id: "mac", name: "Mac", kind: .mac, level: 5)
        XCTAssertEqual(d.update([mac]), [])
    }

    func testAppearanceEnums() {
        XCTAssertEqual(MaterialPreset.allCases.count, 7)
        XCTAssertEqual(MaterialPreset.carbon.opacity(translucency: 1), MaterialPreset.carbon.tintOpacity)
        XCTAssertEqual(MaterialPreset.clear.opacity(translucency: 0), 1)
        XCTAssertEqual(AnimationStyle.snappy.response(speed: 2), 0.15, accuracy: 1e-9)
        XCTAssertEqual(AnimationStyle.calm.response(speed: 100), 0.16, accuracy: 1e-9)
        XCTAssertEqual(TimeFormat.h24.template, "HHmm")
    }
}

final class HeaderButtonTests: XCTestCase {
    func testParseDropsUnknownAndDuplicates() {
        XCTAssertEqual(HeaderButtonID.parseList("pin, bogus,pin,lock"), [.pin, .lock])
        XCTAssertEqual(HeaderButtonID.parseList(""), [])
    }

    func testSerializeUsesCanonicalOrder() {
        XCTAssertEqual(HeaderButtonID.serialize([.lock, .battery, .mic]), "battery,mic,lock")
        XCTAssertEqual(HeaderButtonID.parseList(HeaderButtonID.serialize(Set(HeaderButtonID.defaultList))),
                       HeaderButtonID.defaultList)
    }
}

final class PanelTabMigrationTests: XCTestCase {
    func testV3ListGainsNewTabsBeforeSystem() {
        let migrated = PanelTab.parseList(PanelTab.migrate(stored: "home,timer,system,aiUsage", known: nil))
        XCTAssertEqual(migrated.prefix(2), [.home, .timer])
        XCTAssertEqual(migrated.suffix(2), [.system, .aiUsage])
        XCTAssertTrue(migrated.contains(.calculator))
        XCTAssertTrue(migrated.contains(.mirror))
        XCTAssertFalse(migrated.contains(.clipboard))   // removed by the user before, stays removed
    }

    func testKnownTabsAreNotReAdded() {
        let all = PanelTab.serialize(PanelTab.allCases)
        XCTAssertEqual(PanelTab.migrate(stored: "home,notes", known: all), "home,notes")
    }
}

final class V33SettingsTests: XCTestCase {
    func testShelfRetentionExpiry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = ShelfItem(path: "/tmp/a", addedAt: now.addingTimeInterval(-7200))
        let fresh = ShelfItem(path: "/tmp/b", addedAt: now.addingTimeInterval(-60))
        XCTAssertEqual(ShelfRetention.hour.expired([old, fresh], now: now), [old])
        XCTAssertEqual(ShelfRetention.untilCleared.expired([old, fresh], now: now), [])
        XCTAssertEqual(ShelfRetention.week.expired([old, fresh], now: now), [])
    }

    func testEnumsRoundTrip() {
        for scope in FullscreenScope.allCases { XCTAssertEqual(FullscreenScope(rawValue: scope.rawValue), scope) }
        XCTAssertEqual(ShelfRetention.day.seconds, 86_400)
    }
}
