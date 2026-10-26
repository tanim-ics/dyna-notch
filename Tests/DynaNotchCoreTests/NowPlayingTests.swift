import XCTest
@testable import DynaNotchCore

final class NowPlayingSnapshotTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 5_000)

    func testEmpty() {
        XCTAssertTrue(NowPlayingSnapshot.empty.isEmpty)
        XCTAssertFalse(NowPlayingSnapshot(title: "x").isEmpty)
    }

    func testTrackKey() {
        let s = NowPlayingSnapshot(title: "T", artist: "A", album: "B")
        XCTAssertEqual(s.trackKey, "T\u{1F}A\u{1F}B")
        XCTAssertNotEqual(s.trackKey, NowPlayingSnapshot(title: "T", artist: "AB").trackKey)
    }

    func testElapsedWhilePlaying() {
        let s = NowPlayingSnapshot(title: "x", duration: 200, elapsed: 10, timestamp: t0, playbackRate: 1, isPlaying: true)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(5)), 15, accuracy: 1e-9)
    }

    func testElapsedUsesRate() {
        let s = NowPlayingSnapshot(title: "x", duration: 200, elapsed: 10, timestamp: t0, playbackRate: 2, isPlaying: true)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(5)), 20, accuracy: 1e-9)
    }

    func testElapsedZeroRateWhilePlayingUsesOne() {
        let s = NowPlayingSnapshot(title: "x", duration: 200, elapsed: 10, timestamp: t0, playbackRate: 0, isPlaying: true)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(5)), 15, accuracy: 1e-9)
    }

    func testElapsedPausedIsFrozen() {
        let s = NowPlayingSnapshot(title: "x", duration: 200, elapsed: 10, timestamp: t0, playbackRate: 1, isPlaying: false)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(50)), 10)
    }

    func testElapsedClamped() {
        let s = NowPlayingSnapshot(title: "x", duration: 100, elapsed: 90, timestamp: t0, playbackRate: 1, isPlaying: true)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(50)), 100)
        XCTAssertEqual(s.elapsed(at: t0.addingTimeInterval(-500)), 0)
        let live = NowPlayingSnapshot(title: "x", duration: 0, elapsed: 90, timestamp: t0, playbackRate: 1, isPlaying: true)
        XCTAssertEqual(live.elapsed(at: t0.addingTimeInterval(50)), 140, accuracy: 1e-9)
    }

    func testProgress() {
        let s = NowPlayingSnapshot(title: "x", duration: 200, elapsed: 50, timestamp: t0, isPlaying: false)
        XCTAssertEqual(s.progress(at: t0), 0.25, accuracy: 1e-9)
        let playing = NowPlayingSnapshot(title: "x", duration: 100, elapsed: 90, timestamp: t0, playbackRate: 1, isPlaying: true)
        XCTAssertEqual(playing.progress(at: t0.addingTimeInterval(100)), 1)
        XCTAssertEqual(NowPlayingSnapshot(title: "x", duration: 0, elapsed: 50).progress(at: t0), 0)
        XCTAssertEqual(NowPlayingSnapshot(title: "x", duration: -3, elapsed: 50).progress(at: t0), 0)
    }
}

final class AdapterParserTests: XCTestCase {
    func snapshot(_ line: String, file: StaticString = #filePath, line l: UInt = #line) -> NowPlayingSnapshot? {
        guard case .nowPlaying(let s) = AdapterParser.parse(line: line) else {
            XCTFail("expected nowPlaying for \(line)", file: file, line: l)
            return nil
        }
        return s
    }

    func testReady() {
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"ready"}"#), .ready)
        XCTAssertEqual(AdapterParser.parse(line: "  {\"type\":\"ready\"}\n"), .ready)
    }

    func testError() {
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"error","message":"MediaRemote missing"}"#),
                       .error("MediaRemote missing"))
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"error"}"#), .error(""))
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"error","message":null}"#), .error(""))
    }

    func testEmptyFlag() {
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"nowPlaying","empty":true}"#), .empty)
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"nowPlaying","empty":"true","title":"x"}"#), .empty)
    }

    func testMissingOrEmptyTitleIsEmpty() {
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"nowPlaying","artist":"A"}"#), .empty)
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"nowPlaying","title":""}"#), .empty)
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"nowPlaying","title":null}"#), .empty)
    }

    func testFullValidLine() {
        let art = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]).base64EncodedString()
        let line = """
        {"type":"nowPlaying","empty":false,"title":"Song","artist":"Artist","album":"Album","duration":215.5,\
        "elapsed":12.25,"rate":1,"timestamp":1700000000.5,"playing":true,"bundle":"com.spotify.client",\
        "parentBundle":null,"artworkId":"abc","artwork":"\(art)"}
        """
        guard let s = snapshot(line) else { return }
        XCTAssertEqual(s.title, "Song")
        XCTAssertEqual(s.artist, "Artist")
        XCTAssertEqual(s.album, "Album")
        XCTAssertEqual(s.duration, 215.5)
        XCTAssertEqual(s.elapsed, 12.25)
        XCTAssertEqual(s.playbackRate, 1)
        XCTAssertEqual(s.timestamp, Date(timeIntervalSince1970: 1_700_000_000.5))
        XCTAssertTrue(s.isPlaying)
        XCTAssertEqual(s.bundleIdentifier, "com.spotify.client")
        XCTAssertEqual(s.artworkIdentifier, "abc")
        XCTAssertEqual(s.artworkData, Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]))
    }

    func testNSNullEverywhere() {
        let line = """
        {"type":"nowPlaying","title":"Only","artist":null,"album":null,"duration":null,"elapsed":null,"rate":null,\
        "timestamp":null,"playing":null,"bundle":null,"parentBundle":null,"artworkId":null,"artwork":null}
        """
        let before = Date()
        guard let s = snapshot(line) else { return }
        XCTAssertEqual(s.title, "Only")
        XCTAssertEqual(s.artist, "")
        XCTAssertEqual(s.album, "")
        XCTAssertEqual(s.duration, 0)
        XCTAssertEqual(s.elapsed, 0)
        XCTAssertFalse(s.isPlaying)
        XCTAssertNil(s.bundleIdentifier)
        XCTAssertNil(s.artworkIdentifier)
        XCTAssertNil(s.artworkData)
        XCTAssertGreaterThanOrEqual(s.timestamp.timeIntervalSince1970, before.timeIntervalSince1970 - 1)
    }

    func testStringsAsNumbers() {
        let line = #"{"type":"nowPlaying","title":"S","duration":"180","elapsed":"3.5","rate":"1.0","timestamp":"1700000000","playing":"false"}"#
        guard let s = snapshot(line) else { return }
        XCTAssertEqual(s.duration, 180)
        XCTAssertEqual(s.elapsed, 3.5)
        XCTAssertEqual(s.playbackRate, 1)
        XCTAssertEqual(s.timestamp, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(s.isPlaying) // explicit "playing" wins over rate
    }

    func testIsPlayingFallsBackToRate() {
        XCTAssertEqual(snapshot(#"{"type":"nowPlaying","title":"S","rate":1}"#)?.isPlaying, true)
        XCTAssertEqual(snapshot(#"{"type":"nowPlaying","title":"S","rate":0}"#)?.isPlaying, false)
        XCTAssertEqual(snapshot(#"{"type":"nowPlaying","title":"S"}"#)?.isPlaying, false)
        XCTAssertEqual(snapshot(#"{"type":"nowPlaying","title":"S","rate":0,"playing":1}"#)?.isPlaying, true)
    }

    func testParentBundlePreferred() {
        let s = snapshot(#"{"type":"nowPlaying","title":"S","bundle":"com.apple.WebKit.GPU","parentBundle":"com.apple.Safari"}"#)
        XCTAssertEqual(s?.bundleIdentifier, "com.apple.Safari")
        let empty = snapshot(#"{"type":"nowPlaying","title":"S","bundle":"com.apple.Music","parentBundle":""}"#)
        XCTAssertEqual(empty?.bundleIdentifier, "com.apple.Music")
        let none = snapshot(#"{"type":"nowPlaying","title":"S","bundle":"","parentBundle":""}"#)
        XCTAssertNil(none?.bundleIdentifier)
    }

    func testInvalidBase64Ignored() {
        let s = snapshot(#"{"type":"nowPlaying","title":"S","artwork":"%%%not base64%%%"}"#)
        XCTAssertNil(s?.artworkData)
        let empty = snapshot(#"{"type":"nowPlaying","title":"S","artwork":""}"#)
        XCTAssertNil(empty?.artworkData)
    }

    func testNumericTitleTolerated() {
        XCTAssertEqual(snapshot(#"{"type":"nowPlaying","title":1999}"#)?.title, "1999")
    }

    func testGarbageIsUnknown() {
        XCTAssertEqual(AdapterParser.parse(line: "not json"), .unknown)
        XCTAssertEqual(AdapterParser.parse(line: "{\"type\":\"nowPl"), .unknown)
        XCTAssertEqual(AdapterParser.parse(line: "[1,2,3]"), .unknown)
        XCTAssertEqual(AdapterParser.parse(line: "42"), .unknown)
        XCTAssertEqual(AdapterParser.parse(line: #"{"title":"no type"}"#), .unknown)
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":"bogus"}"#), .unknown)
        XCTAssertEqual(AdapterParser.parse(line: #"{"type":null}"#), .unknown)
    }

    func testEmptyLineIsUnknown() {
        XCTAssertEqual(AdapterParser.parse(line: ""), .unknown)
        XCTAssertEqual(AdapterParser.parse(line: "   \n"), .unknown)
    }
}
