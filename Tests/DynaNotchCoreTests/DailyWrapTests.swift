import XCTest
@testable import DynaNotchCore

final class DailyWrapTests: XCTestCase {
    func testLines() {
        let input = DailyWrap.Input(screenSeconds: 22_320, topApps: ["Xcode", "Safari", "Slack", "Mail"], pomodoros: 4,
                                    songs: ["A — X", "B — Y", "B — Y"], claudeCost: 3.456, commits: 7)
        let lines = DailyWrap.lines(input)
        XCTAssertEqual(lines.map(\.text), ["6 h 12 min at the Mac · mostly Xcode, Safari, Slack", "4 Pomodoros finished",
                                           "7 commits", "B — Y · played 2×", "Claude Code $3.46"])
        XCTAssertTrue(DailyWrap.lines(DailyWrap.Input()).isEmpty)
        XCTAssertEqual(DailyWrap.lines(DailyWrap.Input(pomodoros: 1, commits: 0)).map(\.text), ["1 Pomodoro finished"])
    }

    func testNextDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Vienna") ?? .current
        let friday17 = cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 17))!
        let friday19 = cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 19))!
        XCTAssertEqual(DailyWrap.nextDate(after: friday17, minutes: 1080, weekdaysOnly: true, calendar: cal),
                       cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 18)))
        XCTAssertEqual(DailyWrap.nextDate(after: friday19, minutes: 1080, weekdaysOnly: true, calendar: cal),
                       cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 18)))   // Monday
        XCTAssertEqual(DailyWrap.nextDate(after: friday19, minutes: 1080, weekdaysOnly: false, calendar: cal),
                       cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 18)))
    }

    func testDurationText() {
        XCTAssertEqual(DurationText.hm(2700), "45 min")
        XCTAssertEqual(DurationText.hm(7200), "2 h")
        XCTAssertEqual(DurationText.hm(22_320), "6 h 12 min")
    }

    func testWrapKind() {
        let k = ActivityKind.wrap(lines: [WrapLine(symbol: "timer", text: "x")])
        XCTAssertEqual(k.category, .wrap)
        XCTAssertTrue(k.isQuietedDuringFocus)
        let notch = NotchMetrics(width: 185, height: 32, hasPhysicalNotch: true)
        let size = IslandLayout.size(for: .activity(LiveActivity(kind: k, postedAt: Date(), expiresAt: Date())),
                                     notch: notch, hudStyle: .compact)
        XCTAssertEqual(size.height, 32 + 30 + 22)
    }
}
