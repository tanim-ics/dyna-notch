import XCTest
@testable import DynaNotchCore

final class SensorLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testSessions() {
        var log = SensorUsageLog()
        log.begin(.microphone, app: "", at: t0)
        log.begin(.microphone, app: "Zoom", at: t0.addingTimeInterval(1))   // same session, app filled in
        log.begin(.camera, app: "", at: t0.addingTimeInterval(2))
        log.end(.microphone, at: t0.addingTimeInterval(60))
        log.end(.microphone, at: t0.addingTimeInterval(90))                // no open session: ignored
        XCTAssertEqual(log.sessions.count, 2)
        XCTAssertEqual(log.sessions[0].sensor, "camera")
        XCTAssertNil(log.sessions[0].end)
        XCTAssertEqual(log.sessions[1].app, "Zoom")
        XCTAssertEqual(log.sessions[1].duration, 60)
        for i in 0..<60 { log.begin(.camera, app: "x", at: t0.addingTimeInterval(Double(i))); log.end(.camera, at: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(log.sessions.count, SensorUsageLog.limit)
        log.forget(app: "x")
        XCTAssertTrue(log.sessions.isEmpty)
        let data = try? JSONEncoder().encode(log)
        XCTAssertEqual(data.flatMap { try? JSONDecoder().decode(SensorUsageLog.self, from: $0) }, log)
    }

    func testTalkMeter() {
        var m = TalkMeter()
        for _ in 0..<50 { m.add(level: -20, seconds: 0.1) }   // 5 s speaking
        XCTAssertNil(m.share)                                  // under 10 s
        for _ in 0..<150 { m.add(level: -70, seconds: 0.1) }  // 15 s quiet (first 0.3 s count as hangover)
        XCTAssertEqual(m.share, 26)                            // (5 + 0.2 hangover) / 20
        m.add(level: .nan, seconds: 0)
        XCTAssertEqual(m.total, 20, accuracy: 0.0001)
    }

    func testFormat() {
        XCTAssertEqual(CallFormat.duration(245), "4:05")
        XCTAssertEqual(CallFormat.duration(3729), "1:02:09")
        XCTAssertEqual(CallFormat.recap(seconds: 2520, talkShare: 61), "Call 42 min · you spoke 61%")
        XCTAssertEqual(CallFormat.recap(seconds: 20, talkShare: nil), "Call 1 min")
    }

    func testCallKind() {
        let k = ActivityKind.call(app: "Zoom", startedAt: t0, talkShare: nil)
        XCTAssertEqual(k.category, .call)
        XCTAssertFalse(k.isQuietedDuringFocus)
        XCTAssertLessThan(k.priority, ActivityKind.sensor(.camera, active: true, app: "").priority)
    }
}
