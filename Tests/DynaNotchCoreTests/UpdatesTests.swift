import XCTest
@testable import DynaNotchCore

final class UpdatesTests: XCTestCase {
    private let page = URL(string: "https://github.com/tanim-ics/dyna-notch/releases/tag/v3.3.0")!

    func testVersionParsingAndOrder() {
        XCTAssertEqual(AppVersion("v3.2.0")?.description, "3.2.0")
        XCTAssertEqual(AppVersion("3.3"), AppVersion("3.3.0"))
        XCTAssertEqual(AppVersion("3.3.0-rc1"), AppVersion("3.3.0"))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("dev"))
        XCTAssertNil(AppVersion("3..1"))
        XCTAssertTrue(AppVersion("3.2.0")! < AppVersion("3.10")!)
        XCTAssertTrue(AppVersion("3.2.9")! < AppVersion("3.3.0")!)
        XCTAssertFalse(AppVersion("3.3.0")! < AppVersion("3.3")!)
    }

    func testDecodeDropsBadEntriesAndSortsNewestFirst() {
        let json = """
        [
          {"version": "3.2.0", "features": [{"title": "Old"}]},
          {"version": "nope", "features": [{"title": "Bad"}]},
          {"version": "3.4.0", "features": []},
          "junk",
          {"version": "3.3.0", "headline": "Hi", "features": [{"symbol": "star", "color": "blue", "title": "New", "text": "T"}]}
        ]
        """
        let notes = ReleaseNotes.decode(Data(json.utf8))
        XCTAssertEqual(notes.map(\.version), ["3.3.0", "3.2.0"])
        XCTAssertEqual(notes[0].features[0], FeatureNote(symbol: "star", color: "blue", title: "New", text: "T"))
        XCTAssertEqual(notes[1].features[0].symbol, "sparkles")   // defaults
        XCTAssertEqual(ReleaseNotes.decode(Data("{}".utf8)), [])
    }

    func testBetween() {
        let notes = ["3.4.0", "3.3.0", "3.2.0", "3.1"].map {
            ReleaseNote(version: $0, features: [FeatureNote(title: $0)])
        }
        XCTAssertEqual(ReleaseNotes.between(notes, after: "3.2.0", upTo: "3.4.0").map(\.version), ["3.4.0", "3.3.0"])
        XCTAssertEqual(ReleaseNotes.between(notes, after: nil, upTo: "3.3").map(\.version), ["3.3.0"])
        XCTAssertEqual(ReleaseNotes.between(notes, after: "3.4.0", upTo: "3.4.0"), [])
        XCTAssertEqual(ReleaseNotes.between(notes, after: "garbage", upTo: "3.2.0").map(\.version), ["3.2.0"])
    }

    func testMarkdownFallback() {
        let body = "## DynaNotch 3.3\n- **Smart Copy**: converts amounts\n* Voice Notes\nplain line\n- \n"
        let note = ReleaseNotes.fromMarkdown(body, version: "3.3.0")
        XCTAssertEqual(note?.features.map(\.title), ["Smart Copy", "Voice Notes"])
        XCTAssertEqual(note?.features.first?.text, "converts amounts")
        XCTAssertNil(ReleaseNotes.fromMarkdown("no bullets", version: "1"))
    }

    func testGitHubDecodingAndEvaluate() throws {
        let json = """
        {"tag_name": "v3.3.0", "html_url": "\(page.absoluteString)", "body": "- A", "draft": false,
         "prerelease": false, "assets": [
           {"name": "DynaNotch-3.3.0.zip", "browser_download_url": "https://x/DynaNotch-3.3.0.zip",
            "digest": "sha256:\(String(repeating: "Ab", count: 32))"},
           {"name": "WhatsNew.json", "browser_download_url": "https://x/WhatsNew.json", "digest": null}]}
        """
        let release = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        let update = UpdateCheck.evaluate(release, current: "3.2.0")
        XCTAssertEqual(update?.version, "3.3.0")
        XCTAssertEqual(update?.zipURL.absoluteString, "https://x/DynaNotch-3.3.0.zip")
        XCTAssertEqual(update?.sha256, String(repeating: "ab", count: 32))
        XCTAssertEqual(update?.notesURL?.absoluteString, "https://x/WhatsNew.json")
        XCTAssertNil(UpdateCheck.evaluate(release, current: "3.3.0"))
        XCTAssertNil(UpdateCheck.evaluate(release, current: "3.4"))
        XCTAssertNil(UpdateCheck.evaluate(release, current: "dev"))

        var draft = release
        draft.draft = true
        XCTAssertNil(UpdateCheck.evaluate(draft, current: "3.2.0"))
        var noZip = release
        noZip.assets.removeFirst()
        XCTAssertNil(UpdateCheck.evaluate(noZip, current: "3.2.0"))
        var badDigest = release
        badDigest.assets[0].digest = "md5:abc"
        XCTAssertNil(UpdateCheck.evaluate(badDigest, current: "3.2.0")?.sha256)
    }

    func testShouldShowWhatsNew() {
        XCTAssertFalse(UpdateCheck.shouldShowWhatsNew(lastSeen: nil, current: "3.3.0", hasSeenWelcome: false))
        XCTAssertTrue(UpdateCheck.shouldShowWhatsNew(lastSeen: nil, current: "3.3.0", hasSeenWelcome: true))
        XCTAssertTrue(UpdateCheck.shouldShowWhatsNew(lastSeen: "3.2.0", current: "3.3.0", hasSeenWelcome: true))
        XCTAssertFalse(UpdateCheck.shouldShowWhatsNew(lastSeen: "3.3.0", current: "3.3.0", hasSeenWelcome: true))
        XCTAssertFalse(UpdateCheck.shouldShowWhatsNew(lastSeen: "3.4.0", current: "3.3.0", hasSeenWelcome: true))
    }

    func testIsDue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-90_000), now: now))
        XCTAssertTrue(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(3600), now: now))   // clock went back
    }

    /// The shipped notes file must decode and describe the version in Info.plist — a release reminder.
    func testShippedNotesMatchInfoPlist() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let notes = ReleaseNotes.decode(try Data(contentsOf: root.appendingPathComponent("Packaging/WhatsNew.json")))
        XCTAssertFalse(notes.isEmpty)
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: root.appendingPathComponent("Packaging/Info.plist")), format: nil) as? [String: Any]
        let version = try XCTUnwrap(plist?["CFBundleShortVersionString"] as? String)
        XCTAssertEqual(notes.first?.version, version, "Add a WhatsNew.json entry for \(version)")
        let colors: Set<String> = ["blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "indigo", "gray"]
        for feature in notes.flatMap(\.features) {
            XCTAssertTrue(colors.contains(feature.color), "\(feature.title): unknown colour \(feature.color)")
            XCTAssertFalse(feature.text.isEmpty, "\(feature.title) has no text")
        }
    }
}
