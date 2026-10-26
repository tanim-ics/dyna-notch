import XCTest
@testable import DynaNotchCore

final class FormatTests: XCTestCase {
    func testTime() {
        XCTAssertEqual(Format.time(0), "0:00")
        XCTAssertEqual(Format.time(5), "0:05")
        XCTAssertEqual(Format.time(187), "3:07")
        XCTAssertEqual(Format.time(187.9), "3:07")
        XCTAssertEqual(Format.time(3599), "59:59")
        XCTAssertEqual(Format.time(3600), "1:00:00")
        XCTAssertEqual(Format.time(3723), "1:02:03")
    }

    func testTimeInvalid() {
        XCTAssertEqual(Format.time(.nan), "0:00")
        XCTAssertEqual(Format.time(-12), "0:00")
        XCTAssertEqual(Format.time(.infinity), "0:00")
        XCTAssertEqual(Format.time(-.infinity), "0:00")
    }

    func testPercent() {
        XCTAssertEqual(Format.percent(0), "0%")
        XCTAssertEqual(Format.percent(0.5), "50%")
        XCTAssertEqual(Format.percent(0.996), "100%")
        XCTAssertEqual(Format.percent(1), "100%")
        XCTAssertEqual(Format.percent(1.7), "100%")
        XCTAssertEqual(Format.percent(-0.2), "0%")
        XCTAssertEqual(Format.percent(.nan), "0%")
    }

    func testRelativeMinutes() {
        XCTAssertEqual(Format.relativeMinutes(-3), "now")
        XCTAssertEqual(Format.relativeMinutes(0), "now")
        XCTAssertEqual(Format.relativeMinutes(1), "in 1 min")
        XCTAssertEqual(Format.relativeMinutes(5), "in 5 min")
        XCTAssertEqual(Format.relativeMinutes(59), "in 59 min")
        XCTAssertEqual(Format.relativeMinutes(60), "in 1 h")
        XCTAssertEqual(Format.relativeMinutes(80), "in 1 h 20 min")
        XCTAssertEqual(Format.relativeMinutes(120), "in 2 h")
    }

    func testClockRange() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = Date(timeIntervalSince1970: 9 * 3600)
        let end = Date(timeIntervalSince1970: 10 * 3600 + 30 * 60)
        let s = Format.clockRange(start: start, end: end, calendar: cal, locale: Locale(identifier: "en_US_POSIX"))
        XCTAssertTrue(s.contains(" – "), s)
        let parts = s.components(separatedBy: " – ")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("9"), s)
        XCTAssertTrue(parts[1].contains("30"), s)
    }
}

final class MediaKeyEventTests: XCTestCase {
    func testSoundUpDown() {
        let e = MediaKeyEvent(data1: (0 << 16) | (0x0A << 8))
        XCTAssertEqual(e.rawKeyCode, 0)
        XCTAssertEqual(e.key, .soundUp)
        XCTAssertTrue(e.isDown)
        XCTAssertFalse(e.isRepeat)
    }

    func testKeyUp() {
        let e = MediaKeyEvent(data1: (1 << 16) | (0x0B << 8))
        XCTAssertEqual(e.key, .soundDown)
        XCTAssertFalse(e.isDown)
    }

    func testRepeat() {
        let e = MediaKeyEvent(data1: (2 << 16) | (0x0A << 8) | 0x1)
        XCTAssertEqual(e.key, .brightnessUp)
        XCTAssertTrue(e.isDown)
        XCTAssertTrue(e.isRepeat)
    }

    func testAllKnownCodes() {
        let codes: [(Int, MediaKey)] = [(0, .soundUp), (1, .soundDown), (2, .brightnessUp), (3, .brightnessDown),
                                        (7, .mute), (16, .play), (17, .next), (18, .previous), (19, .fast),
                                        (20, .rewind), (21, .illuminationUp), (22, .illuminationDown)]
        for (code, key) in codes {
            XCTAssertEqual(MediaKeyEvent(data1: (code << 16) | (0x0A << 8)).key, key)
        }
    }

    func testUnknownCode() {
        let e = MediaKeyEvent(data1: (5 << 16) | (0x0A << 8))
        XCTAssertEqual(e.rawKeyCode, 5)
        XCTAssertNil(e.key)
    }

    func testNegativeAndHighBits() {
        // Sign-extended 32-bit value with high bits set must still decode the low 32 bits.
        let raw = Int(Int32(bitPattern: 0xFFFF_0A00 as UInt32))
        let e = MediaKeyEvent(data1: raw)
        XCTAssertEqual(e.rawKeyCode, 0xFFFF)
        XCTAssertNil(e.key)
        XCTAssertTrue(e.isDown)
        let withJunk = MediaKeyEvent(data1: (0x7_0000_0000) | (3 << 16) | (0x0A << 8))
        XCTAssertEqual(withJunk.key, .brightnessDown)
        let negative = MediaKeyEvent(data1: -1)
        XCTAssertEqual(negative.rawKeyCode, 0xFFFF)
        XCTAssertFalse(negative.isDown)
        XCTAssertTrue(negative.isRepeat)
    }
}

final class LevelStepperTests: XCTestCase {
    let s = LevelStepper.step

    func testConstants() {
        XCTAssertEqual(LevelStepper.step, 1.0 / 16.0)
        XCTAssertEqual(LevelStepper.fineStep, 1.0 / 64.0)
    }

    func testStepUpFromMultiple() {
        XCTAssertEqual(LevelStepper.step(0.5, up: true, fine: false), 0.5 + s, accuracy: 1e-12)
        XCTAssertEqual(LevelStepper.step(0, up: true, fine: false), s, accuracy: 1e-12)
    }

    func testStepDownFromMultiple() {
        XCTAssertEqual(LevelStepper.step(0.5, up: false, fine: false), 0.5 - s, accuracy: 1e-12)
    }

    func testSnapsToNextMultiple() {
        XCTAssertEqual(LevelStepper.step(0.51, up: true, fine: false), 9 * s, accuracy: 1e-12)
        XCTAssertEqual(LevelStepper.step(0.51, up: false, fine: false), 8 * s, accuracy: 1e-12)
        XCTAssertEqual(LevelStepper.step(0.3, up: true, fine: false), 5 * s, accuracy: 1e-12)
        XCTAssertEqual(LevelStepper.step(0.3, up: false, fine: false), 4 * s, accuracy: 1e-12)
    }

    func testNearlyMultipleTreatedAsMultiple() {
        let almost = 0.5 - 1e-9
        XCTAssertEqual(LevelStepper.step(almost, up: true, fine: false), 0.5 + s, accuracy: 1e-12)
        XCTAssertEqual(LevelStepper.step(0.5 + 1e-9, up: false, fine: false), 0.5 - s, accuracy: 1e-12)
    }

    func testClamping() {
        XCTAssertEqual(LevelStepper.step(1, up: true, fine: false), 1)
        XCTAssertEqual(LevelStepper.step(0.99, up: true, fine: false), 1)
        XCTAssertEqual(LevelStepper.step(0, up: false, fine: false), 0)
        XCTAssertEqual(LevelStepper.step(0.01, up: false, fine: false), 0)
        XCTAssertEqual(LevelStepper.step(1.5, up: true, fine: true), 1)
        XCTAssertEqual(LevelStepper.step(-0.5, up: false, fine: true), 0)
    }

    func testFine() {
        let f = LevelStepper.fineStep
        XCTAssertEqual(LevelStepper.step(0.5, up: true, fine: true), 0.5 + f, accuracy: 1e-12)
        XCTAssertEqual(LevelStepper.step(0.5, up: false, fine: true), 0.5 - f, accuracy: 1e-12)
        XCTAssertEqual(LevelStepper.step(0.51, up: true, fine: true), 33 * f, accuracy: 1e-12)
    }

    func testRepeatedStepsReachEnds() {
        var level = 0.0
        for _ in 0..<16 { level = LevelStepper.step(level, up: true, fine: false) }
        XCTAssertEqual(level, 1, accuracy: 1e-12)
        for _ in 0..<16 { level = LevelStepper.step(level, up: false, fine: false) }
        XCTAssertEqual(level, 0, accuracy: 1e-12)
    }

    func testLevelReading() {
        XCTAssertEqual(LevelReading(level: 0.5, muted: true), LevelReading(level: 0.5, muted: true))
        XCTAssertNotEqual(LevelReading(level: 0.5, muted: true), LevelReading(level: 0.5, muted: false))
    }
}
