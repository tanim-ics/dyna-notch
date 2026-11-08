import XCTest
@testable import DynaNotchCore

final class LyricsQueryTests: XCTestCase {
    func testCleanArtist() {
        XCTAssertEqual(LyricsQuery.cleanArtist("Kings of Leon - Topic"), "Kings of Leon")
        XCTAssertEqual(LyricsQuery.cleanArtist("TaylorSwiftVEVO"), "TaylorSwift")
        XCTAssertEqual(LyricsQuery.cleanArtist("Daft Punk, Pharrell Williams"), "Daft Punk")
        XCTAssertEqual(LyricsQuery.cleanArtist("Kings of Leon • Can We Please Have Fun"), "Kings of Leon")
        XCTAssertEqual(LyricsQuery.cleanArtist("Simon & Garfunkel"), "Simon")
        XCTAssertEqual(LyricsQuery.cleanArtist(""), "")
    }

    func testCleanTitle() {
        XCTAssertEqual(LyricsQuery.clean(title: "Split Screen", artist: "Kings of Leon").title, "Split Screen")
        XCTAssertEqual(LyricsQuery.clean(title: "Kings of Leon - Split Screen (Official Video)", artist: "Kings of Leon - Topic").title,
                       "Split Screen")
        let parsed = LyricsQuery.clean(title: "Daft Punk - Get Lucky [Official Audio] (feat. Pharrell)", artist: "")
        XCTAssertEqual(parsed.title, "Get Lucky")
        XCTAssertEqual(parsed.artist, "Daft Punk")
        XCTAssertEqual(LyricsQuery.clean(title: "Song (Live at Wembley)", artist: "A").title, "Song")
        XCTAssertEqual(LyricsQuery.clean(title: "Song (Interlude)", artist: "A").title, "Song (Interlude)")
        XCTAssertEqual(LyricsQuery.clean(title: "Song | Lyrics", artist: "A").title, "Song")
        XCTAssertEqual(LyricsQuery.clean(title: "Anti-Hero", artist: "Taylor Swift").title, "Anti-Hero")
        XCTAssertEqual(LyricsQuery.clean(title: "", artist: "").title, "")
    }

    func testBest() {
        let c = [
            LyricsQuery.Candidate(artist: "Paris Texas", duration: 146, hasSynced: true, hasPlain: true),
            LyricsQuery.Candidate(artist: "Kings of Leon", duration: 303, hasSynced: false, hasPlain: true),
            LyricsQuery.Candidate(artist: "Kings Of Leon", duration: 302, hasSynced: true, hasPlain: true),
        ]
        XCTAssertEqual(LyricsQuery.best(c, artist: "Kings of Leon", duration: 303), 2)
        XCTAssertEqual(LyricsQuery.best(c, artist: "", duration: 146), 0)
        XCTAssertEqual(LyricsQuery.best(c, artist: "Kings of Leon", duration: 0), 2)
        XCTAssertNil(LyricsQuery.best(c, artist: "", duration: 500))
        XCTAssertNil(LyricsQuery.best(c, artist: "Nobody", duration: 0, requireArtist: true))
        XCTAssertNil(LyricsQuery.best(c, artist: "Nobody", duration: 0))
        // Same title, other artist, matching length: never used when the player names an artist.
        let sameTitle = [
            LyricsQuery.Candidate(artist: "Halestorm", duration: 222, hasSynced: true, hasPlain: true),
            LyricsQuery.Candidate(artist: "Buckethead & Friends", duration: 264, hasSynced: true, hasPlain: true),
        ]
        XCTAssertNil(LyricsQuery.best(sameTitle, artist: "Kings of Leon", duration: 223))
        XCTAssertNil(LyricsQuery.best(sameTitle, artist: "Kings of Leon", duration: 0))
        XCTAssertEqual(LyricsQuery.best(sameTitle, artist: "", duration: 223), 0)   // no artist sent: length decides
        XCTAssertNil(LyricsQuery.best(sameTitle, artist: "", duration: 0, requireArtist: true))
        XCTAssertNil(LyricsQuery.best([], artist: "", duration: 0))
        let plainOnly = [LyricsQuery.Candidate(artist: "A", duration: 200, hasSynced: false, hasPlain: true)]
        XCTAssertEqual(LyricsQuery.best(plainOnly, artist: "A", duration: 201), 0)
    }
}
