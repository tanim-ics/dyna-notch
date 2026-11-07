import XCTest
@testable import DynaNotchCore

final class SecurityTests: XCTestCase {
    private let secret = String(repeating: "ab", count: 32)

    // MARK: URL hooks

    func testPublicHooksNeedNoToken() {
        for action in ["notify", "tab", "expand", "collapse", "settings", "timer", "whatsnew", "simulate", "NOTIFY"] {
            XCTAssertTrue(URLHookPolicy.isAllowed(action: action, token: nil, expected: secret), action)
        }
    }

    func testDangerousHooksNeedTheToken() {
        let dangerous = ["set", "ui", "agent", "update", "state", "snapshot", "alchemy", "shelf", "copy", "voice",
                         "convert", "sensor", "focusguard", "lockscreen", "snapshot-settings", "", "unknown"]
        for action in dangerous {
            XCTAssertFalse(URLHookPolicy.isAllowed(action: action, token: nil, expected: secret), action)
            XCTAssertFalse(URLHookPolicy.isAllowed(action: action, token: "wrong", expected: secret), action)
            XCTAssertFalse(URLHookPolicy.isAllowed(action: action, token: String(secret.dropLast()), expected: secret))
            XCTAssertTrue(URLHookPolicy.isAllowed(action: action, token: secret, expected: secret), action)
        }
    }

    func testEmptySecretLocksEverythingButPublicHooks() {
        XCTAssertFalse(URLHookPolicy.isAllowed(action: "set", token: "", expected: ""))
        XCTAssertTrue(URLHookPolicy.isAllowed(action: "notify", token: nil, expected: ""))
    }

    func testConstantTimeEqualAndHex() {
        XCTAssertTrue(URLHookPolicy.constantTimeEqual("abc", "abc"))
        XCTAssertFalse(URLHookPolicy.constantTimeEqual("abc", "abd"))
        XCTAssertFalse(URLHookPolicy.constantTimeEqual("abc", "abcd"))
        XCTAssertEqual(URLHookPolicy.hexToken([0, 15, 255]), "000fff")
    }

    // MARK: File names and paths

    func testSafeFileNameStripsPathParts() {
        XCTAssertEqual(SafeFileName.sanitize("../evil", fallback: "x"), "evil")
        XCTAssertEqual(SafeFileName.sanitize("/etc/passwd", fallback: "x"), "etcpasswd")
        XCTAssertEqual(SafeFileName.sanitize("..", fallback: "x"), "x")
        XCTAssertEqual(SafeFileName.sanitize("", fallback: "panel"), "panel")
        XCTAssertEqual(SafeFileName.sanitize("reg-extra_1.v2", fallback: "x"), "reg-extra_1.v2")
        XCTAssertEqual(SafeFileName.sanitize("ünï cødé", fallback: "x"), "ncd")
        XCTAssertEqual(SafeFileName.sanitize(String(repeating: "a", count: 100), fallback: "x").count, 64)
    }

    func testIsInside() {
        XCTAssertTrue(SafeFileName.isInside("/private/tmp/a/b.json", directory: "/private/tmp"))
        XCTAssertFalse(SafeFileName.isInside("/private/tmp/../etc/hosts", directory: "/private/tmp"))
        XCTAssertFalse(SafeFileName.isInside("/private/tmpfoo/x", directory: "/private/tmp"))
        XCTAssertFalse(SafeFileName.isInside(NSHomeDirectory() + "/.claude/settings.json", directory: "/private/tmp"))
    }

    // MARK: Updates

    private func update(zip: String, sha: String? = String(repeating: "a", count: 64)) -> AvailableUpdate {
        AvailableUpdate(version: "9.0.0", zipURL: URL(string: zip)!, sha256: sha,
                        pageURL: URL(string: "https://github.com/tanim-ics/dyna-notch/releases/tag/v9.0.0")!)
    }

    func testOnlyThisRepositorysReleasesInstall() {
        let good = "https://github.com/tanim-ics/dyna-notch/releases/download/v9.0.0/DynaNotch-9.0.0.zip"
        XCTAssertTrue(UpdateTrust.canInstall(update(zip: good)))
        XCTAssertFalse(UpdateTrust.canInstall(update(zip: good, sha: nil)), "no checksum, no install")
        for bad in [
            "http://github.com/tanim-ics/dyna-notch/releases/download/v9/DynaNotch-9.0.0.zip",
            "https://github.com/someone/dyna-notch/releases/download/v9/DynaNotch-9.0.0.zip",
            "https://github.com.evil.com/tanim-ics/dyna-notch/releases/download/v9/x.zip",
            "https://evil.com/tanim-ics/dyna-notch/releases/download/v9/x.zip",
            "https://user@github.com/tanim-ics/dyna-notch/releases/download/v9/x.zip",
            "https://github.com:8443/tanim-ics/dyna-notch/releases/download/v9/x.zip",
            "https://github.com/tanim-ics/dyna-notch/releases/download/../../../someone/x.zip",
            "file:///tmp/DynaNotch-9.0.0.zip",
        ] {
            XCTAssertFalse(UpdateTrust.canInstall(update(zip: bad)), bad)
        }
    }

    func testTrustedPage() {
        XCTAssertTrue(UpdateTrust.isTrustedPage(URL(string: "https://github.com/tanim-ics/dyna-notch/releases/tag/v1")!))
        XCTAssertFalse(UpdateTrust.isTrustedPage(URL(string: "https://evil.com/tanim-ics/dyna-notch/")!))
        XCTAssertFalse(UpdateTrust.isTrustedPage(URL(string: "file:///Applications/Calculator.app")!))
    }

    // MARK: Agent requests

    func testAgentRequestIDs() {
        XCTAssertTrue(AgentRequest.isValidID("1793527200500-4242"))
        for bad in ["", "abc", "../../x", "1-2-3", "-1", "1-", "12a-3", "1/2-3", String(repeating: "1", count: 30) + "-1"] {
            XCTAssertFalse(AgentRequest.isValidID(bad), bad)
        }
        let json = #"{"id":"../../../tmp/x","tool":"Bash","input":{}}"#
        XCTAssertNil(AgentRequest.parse(Data(json.utf8)))
    }
}
