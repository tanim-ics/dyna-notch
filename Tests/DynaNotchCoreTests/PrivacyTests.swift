import XCTest
@testable import DynaNotchCore
#if canImport(CryptoKit)
import CryptoKit
#endif

final class PrivacyTests: XCTestCase {
    // MARK: Secret detection — caught

    func testDefiniteSecretsAreCaught() {
        let secrets: [(String, SecretKind)] = [
            ("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAA\n-----END OPENSSH PRIVATE KEY-----", .privateKey),
            ("-----BEGIN RSA PRIVATE KEY-----\nMIIEow\n-----END RSA PRIVATE KEY-----", .privateKey),
            ("AKIAIOSFODNN7EXAMPLE", .accessToken),
            ("export GITHUB_TOKEN=ghp_" + String(repeating: "a1B2", count: 9), .accessToken),
            ("github_pat_11ABCDEFG0" + String(repeating: "x", count: 50), .accessToken),
            ("xoxb-123456789012-abcdefABCDEF", .accessToken),
            ("sk-ant-api03-" + String(repeating: "Ab3_", count: 10), .accessToken),
            ("sk-proj-" + String(repeating: "aB3", count: 15), .accessToken),
            ("sk_live_" + String(repeating: "4eC39HqLyjWDarjtT1zdp7dc", count: 1), .accessToken),
            ("AIza" + String(repeating: "Sy", count: 17) + "x", .accessToken),
            ("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U", .accessToken),
            ("Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345", .accessToken),
            ("password: hunter2!", .password),
            ("DB_PASSWORD=s3cr3tValue", .password),
            ("api_key = \"q8Fz2LmN\"", .password),
            ("postgres://admin:Sup3rS3cret@db.example.com:5432/app", .password),
            ("4111 1111 1111 1111", .cardNumber),
            ("5555-5555-5555-4444", .cardNumber),
            ("378282246310005", .cardNumber),
            ("DE89 3704 0044 0532 0130 00", .iban),
            ("GB82WEST12345698765432", .iban),
            ("AT611904300234573201", .iban),
        ]
        for (text, kind) in secrets {
            XCTAssertEqual(SecretDetector.scan(text), .secret(kind), text)
        }
    }

    func testLikelySecretsExpire() {
        XCTAssertEqual(SecretDetector.scan("482913"), .likely(.oneTimeCode))
        XCTAssertEqual(SecretDetector.scan("482 913"), .likely(.oneTimeCode))
        XCTAssertEqual(SecretDetector.scan("12345678"), .likely(.oneTimeCode))
        XCTAssertEqual(SecretDetector.scan("Zx9!qP2#vL7$wR4^tY8&uB1*"), .likely(.randomToken))
        XCTAssertEqual(SecretDetector.likelyLifetime, 120)
    }

    // MARK: Secret detection — ordinary text left alone

    func testOrdinaryTextIsNotFlagged() {
        let normal = [
            "Meeting moved to 3 pm tomorrow, see you there",
            "https://github.com/tanim-ics/dyna-notch/pull/42",
            "/Users/tanim/Desktop/report-2026.pdf",
            "9fceb02d0ae598e95dc970b74767f19372d61af8",                // git SHA
            "550e8400-e29b-41d4-a716-446655440000",                    // UUID
            "+43 660 1234567",                                          // phone number
            "€42.50", "12345", "2026-11-07", "1234 5678 9012 3456",    // fails Luhn
            "let password = readLine()",                                // code, no value
            "The password must be at least 8 characters",
            "func fetchToken() -> String",
            "swift build -c release --product DynaNotch",
            "ThisIsJustALongCamelCaseIdentifierName",                   // low entropy, 2 classes
            String(repeating: "Lorem ipsum dolor sit amet. ", count: 20) + "123456",
            "",
        ]
        for text in normal {
            XCTAssertNil(SecretDetector.scan(text), text)
        }
    }

    func testLongTextOnlyChecksKeysAndTokens() {
        let doc = String(repeating: "Notes from the call. ", count: 15) + "4111 1111 1111 1111"
        XCTAssertNil(SecretDetector.scan(doc), "card-number rule is for short text only")
        let leak = String(repeating: "log line ", count: 40) + "AKIAIOSFODNN7EXAMPLE"
        XCTAssertEqual(SecretDetector.scan(leak), .secret(.accessToken))
    }

    func testClipItemExpiryIsOptionalInOldFiles() throws {
        let old = #"{"id":"6B29FC40-CA47-1067-B31D-00DD010662DA","kind":"text","text":"hi","date":1800000000,"pinned":false}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let item = try decoder.decode(ClipItem.self, from: Data(old.utf8))
        XCTAssertNil(item.expiresAt)
    }

    // MARK: Sealed files

    #if canImport(CryptoKit)
    func testSealRoundTripAndTamper() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("clipboard history with a secret".utf8)
        let sealed = try SealedFile.seal(plain, key: key)
        XCTAssertTrue(SealedFile.isSealed(sealed))
        XCTAssertNil(sealed.range(of: Data("secret".utf8)), "no plaintext on disk")
        let opened = try SealedFile.open(sealed, key: key)
        XCTAssertEqual(opened.plain, plain)
        XCTAssertTrue(opened.wasSealed)
        var tampered = sealed
        tampered[tampered.count - 1] ^= 1
        XCTAssertThrowsError(try SealedFile.open(tampered, key: key))
        XCTAssertThrowsError(try SealedFile.open(sealed, key: SymmetricKey(size: .bits256)), "another Mac's key")
    }

    func testPlainLegacyFilesPassThroughForMigration() throws {
        let legacy = Data("{\"items\":[]}".utf8)
        let opened = try SealedFile.open(legacy, key: SymmetricKey(size: .bits256))
        XCTAssertEqual(opened.plain, legacy)
        XCTAssertFalse(opened.wasSealed)
        XCTAssertFalse(SealedFile.isSealed(Data("DNV1".utf8)), "too short to be a sealed file")
    }

    func testFileKeyIsDeterministicPerKeyPair() throws {
        let a = P256.KeyAgreement.PrivateKey(), b = P256.KeyAgreement.PrivateKey()
        let k1 = SealedFile.fileKey(from: try a.sharedSecretFromKeyAgreement(with: b.publicKey))
        let k2 = SealedFile.fileKey(from: try b.sharedSecretFromKeyAgreement(with: a.publicKey))
        XCTAssertEqual(k1.withUnsafeBytes { Data($0) }, k2.withUnsafeBytes { Data($0) })
    }
    #endif
}
