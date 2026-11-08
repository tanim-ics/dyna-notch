import XCTest
@testable import DynaNotchCore

final class VitalsTests: XCTestCase {
    func testCPU() {
        XCTAssertEqual(Vitals.cpuPercent(previous: 0, current: 60_000_000_000, elapsed: 60), 100, accuracy: 0.01)
        XCTAssertEqual(Vitals.cpuPercent(previous: 5, current: 1, elapsed: 60), 0)
        XCTAssertEqual(Vitals.cpuPercent(previous: 0, current: 1, elapsed: 0), 0)
    }

    func testDisk() {
        XCTAssertTrue(Vitals.diskLow(free: 9_000_000_000, total: 1_000_000_000_000))
        XCTAssertTrue(Vitals.diskLow(free: 12_000_000_000, total: 256_000_000_000_000 / 1000))   // < 5 %
        XCTAssertFalse(Vitals.diskLow(free: 100_000_000_000, total: 1_000_000_000_000))
        XCTAssertEqual(Vitals.gigabytes(8_400_000_000), "8.4 GB")
        XCTAssertEqual(Vitals.gigabytes(123_400_000_000), "123 GB")
    }

    func testThermal() {
        XCTAssertNil(Vitals.thermalTitle(1))
        XCTAssertNotNil(Vitals.thermalTitle(2))
        XCTAssertNotNil(Vitals.thermalTitle(3))
    }

    func testRunaway() {
        var t = RunawayTracker()
        XCTAssertEqual(t.update([1: 95, 2: 50]), [])       // first hot sample
        XCTAssertEqual(t.update([1: 99, 2: 95]), [1])      // second in a row → report
        XCTAssertEqual(t.update([1: 99, 2: 97]), [2])      // 1 already reported
        XCTAssertEqual(t.update([1: 10, 2: 97]), [])       // 1 calms down
        XCTAssertEqual(t.update([1: 95, 2: 97]), [])
        XCTAssertEqual(t.update([1: 95, 2: 97]), [1])      // hot again twice → reported again
    }

    func testVitalsKind() {
        let k = ActivityKind.vitals(title: "Hot", detail: "x", symbol: "flame")
        XCTAssertEqual(k.category, .vitals)
        XCTAssertFalse(k.isQuietedDuringFocus)
    }

    func testMemorySeverity() {
        XCTAssertEqual(Vitals.memorySeverity(pressureLevel: 0), 0)
        XCTAssertEqual(Vitals.memorySeverity(pressureLevel: 1), 0)
        XCTAssertEqual(Vitals.memorySeverity(pressureLevel: 2), 1)
        XCTAssertEqual(Vitals.memorySeverity(pressureLevel: 4), 2)
        XCTAssertEqual(Vitals.memorySeverity(pressureLevel: -1), 0)
    }
}
