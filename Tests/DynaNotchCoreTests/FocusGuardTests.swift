import XCTest
@testable import DynaNotchCore

final class FocusGuardTests: XCTestCase {
    func testIsFocusing() {
        var engine = TimerEngine(config: PomodoroConfig(work: 1500, shortBreak: 300, longBreak: 900, cyclesBeforeLongBreak: 4))
        XCTAssertFalse(FocusGuard.isFocusing(engine.state))
        engine.startPomodoro(now: Date())
        XCTAssertTrue(FocusGuard.isFocusing(engine.state))
        engine.toggle(now: Date())   // paused
        XCTAssertFalse(FocusGuard.isFocusing(engine.state))
    }

    func testApps() {
        XCTAssertEqual(FocusGuard.apps(from: " com.A.b, com.c\ncom.d "), ["com.a.b", "com.c", "com.d"])
        XCTAssertTrue(FocusGuard.apps(from: FocusGuard.defaultApps).contains("com.tinyspeck.slackmacgap"))
    }

    func testTracker() {
        let t0 = Date(timeIntervalSince1970: 0)
        var t = DistractionTracker()
        t.enter(app: "Slack", at: t0)
        t.enter(app: "Discord", at: t0.addingTimeInterval(60))   // switching counts the first
        t.leave(at: t0.addingTimeInterval(90))
        t.leave(at: t0.addingTimeInterval(500))                   // nothing open
        XCTAssertEqual(t.seconds, 90)
        XCTAssertNil(t.current)
        t.reset()
        XCTAssertEqual(t.seconds, 0)
    }

    func testSoundscape() {
        XCTAssertEqual(Soundscape(rawValue: "rain")?.title, "Rain")
        XCTAssertEqual(Soundscape.allCases.count, 5)
    }
}
