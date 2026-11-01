import XCTest
@testable import DynaNotchCore

final class VoiceCommandTests: XCTestCase {
    func testReminders() {
        XCTAssertEqual(VoiceCommand.parse("Remind me to call mum."), .reminder("Call mum"))
        XCTAssertEqual(VoiceCommand.parse("reminder buy milk"), .reminder("Buy milk"))
    }

    func testTimers() {
        XCTAssertEqual(VoiceCommand.parse("timer 10"), .timer(minutes: 10))
        XCTAssertEqual(VoiceCommand.parse("Set a timer for 5 minutes."), .timer(minutes: 5))
        XCTAssertEqual(VoiceCommand.parse("10 minute timer"), .timer(minutes: 10))
        XCTAssertEqual(VoiceCommand.parse("timer 90 seconds"), .timer(minutes: 1.5))
        XCTAssertEqual(VoiceCommand.parse("timer 1 hour"), .timer(minutes: 60))
        XCTAssertEqual(VoiceCommand.parse("timer 2,5 min"), .timer(minutes: 2.5))
    }

    func testNotes() {
        XCTAssertEqual(VoiceCommand.parse("buy oat milk on the way home"), .note("Buy oat milk on the way home"))
        XCTAssertEqual(VoiceCommand.parse("Note the deploy key is in 1Password"), .note("The deploy key is in 1Password"))
        XCTAssertEqual(VoiceCommand.parse("the timer app is great"), .note("The timer app is great"))
    }

    func testLabels() {
        XCTAssertEqual(VoiceCommand.timer(minutes: 10).resultLabel, "Timer 10 min")
        XCTAssertEqual(VoiceCommand.timer(minutes: 0.5).resultLabel, "Timer 30 s")
        XCTAssertEqual(VoiceCommand.note("x").resultLabel, "Note saved")
    }

    func testVoiceKind() {
        let k = ActivityKind.voice(text: "hi", result: nil)
        XCTAssertEqual(k.category, .voice)
        XCTAssertFalse(k.isQuietedDuringFocus)
        XCTAssertEqual(HotKeyAction.voiceNote.title, "Voice Note")
        XCTAssertEqual(KnockAction.voiceNote.title, "Voice Note")
    }
}
