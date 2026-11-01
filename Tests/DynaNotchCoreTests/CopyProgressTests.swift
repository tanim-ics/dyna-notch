import XCTest
@testable import DynaNotchCore

final class CopyProgressTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testSingleCopyLabelFractionAndEstimate() {
        var tracker = CopyProgressTracker()
        XCTAssertNil(tracker.summary(now: t0))
        tracker.update(id: "a", name: "Holiday.mov", fraction: 0, now: t0)
        tracker.update(id: "a", name: "", fraction: 0.25, now: t0.addingTimeInterval(10))
        let s = tracker.summary(now: t0.addingTimeInterval(10))
        XCTAssertEqual(s?.label, "Holiday.mov")
        XCTAssertEqual(s?.fraction, 0.25)
        XCTAssertEqual(s?.secondsLeft, 30)
    }

    func testNoEstimateTooEarly() {
        var tracker = CopyProgressTracker()
        tracker.update(id: "a", name: "x", fraction: 0.5, now: t0)
        XCTAssertNil(tracker.summary(now: t0.addingTimeInterval(1))?.secondsLeft)
        tracker.update(id: "a", name: "x", fraction: 0.01, now: t0)
        XCTAssertNil(tracker.summary(now: t0.addingTimeInterval(10))?.secondsLeft)
    }

    func testSeveralCopiesMergeAndRemove() {
        var tracker = CopyProgressTracker()
        tracker.update(id: "a", name: "A", fraction: 0.2, now: t0)
        tracker.update(id: "b", name: "B", fraction: 0.6, now: t0)
        tracker.update(id: "c", name: "C", fraction: 7, now: t0)   // clamped to 1
        let s = tracker.summary(now: t0)
        XCTAssertEqual(s?.label, "3 items")
        XCTAssertEqual(s?.fraction ?? 0, 0.6, accuracy: 0.0001)
        tracker.remove(id: "c")
        tracker.remove(id: "b")
        XCTAssertEqual(tracker.summary(now: t0)?.label, "A")
        tracker.remove(id: "a")
        XCTAssertTrue(tracker.isEmpty)
    }

    func testThrottle() {
        var tracker = CopyProgressTracker()
        XCTAssertTrue(tracker.shouldPublish(fraction: 0.1, now: t0))
        XCTAssertFalse(tracker.shouldPublish(fraction: 0.102, now: t0.addingTimeInterval(0.1)))
        XCTAssertTrue(tracker.shouldPublish(fraction: 0.11, now: t0.addingTimeInterval(0.2)))
        XCTAssertTrue(tracker.shouldPublish(fraction: 0.111, now: t0.addingTimeInterval(1.5)))
        XCTAssertTrue(tracker.shouldPublish(fraction: 1, now: t0.addingTimeInterval(1.6)))
        XCTAssertFalse(tracker.shouldPublish(fraction: 1, now: t0.addingTimeInterval(1.7)))
    }

    func testFormat() {
        XCTAssertEqual(CopyFormat.remaining(12), "12 s")
        XCTAssertEqual(CopyFormat.remaining(170), "3 min")
        XCTAssertEqual(CopyFormat.remaining(3900), "1 h 5 min")
        XCTAssertEqual(CopyFormat.remaining(7200), "2 h")
        XCTAssertEqual(CopyFormat.percent(0.999), "99%")
        XCTAssertEqual(CopyFormat.percent(0.42), "42%")
        XCTAssertEqual(CopyFormat.percent(1), "100%")
    }

    func testCopyActivityKind() {
        let k = ActivityKind.fileCopy(name: "x", fraction: 0.4, secondsLeft: nil)
        XCTAssertEqual(k.category, .fileCopy)
        XCTAssertFalse(k.isQuietedDuringFocus)
        XCTAssertLessThan(k.priority, ActivityKind.toggle(symbol: "", label: "", on: true).priority)
        XCTAssertEqual(ActivityKind.fileCopy(name: "x", fraction: 1, secondsLeft: nil).defaultDuration, 1.5)
    }
}
