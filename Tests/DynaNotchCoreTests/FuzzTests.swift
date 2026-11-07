import XCTest
@testable import DynaNotchCore

/// Fuzzing (docs/SECURITY.md): every parser that sees outside input — links, Claude Code hooks, network replies,
/// clipboard text, files — gets thousands of hostile inputs. A crash (trap, overflow, out-of-range) fails the run.
/// Seeded, so a failure reproduces; `DYNANOTCH_FUZZ_ITERATIONS` raises the count for longer runs.
final class FuzzTests: XCTestCase {
    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state << 13; state ^= state >> 7; state ^= state << 17
            return state
        }
        mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
    }

    private var iterations: Int {
        Int(ProcessInfo.processInfo.environment["DYNANOTCH_FUZZ_ITERATIONS"] ?? "") ?? 1500
    }

    private static let atoms: [String] = [
        "", " ", "\n", "\r\n", "\t", "\u{0}", "\u{7F}", "\u{202E}", "\u{200B}", "\u{2066}", "\u{FEFF}", "\u{1F600}",
        "é", "ß", "€", "$", "%", "%%", "%25", "%2F", "%00", "/", "..", "../", "\\", "\"", "'", "`", "{", "}", "[", "]",
        "(", ")", "<", ">", "&", "=", "?", "#", ":", ";", ",", ".", "-", "+", "*", "^", "~", "|", "@", "!",
        "0", "1", "-1", "9", "42", "1e308", "1e309", "-1e308", "1e-320", "nan", "NaN", "inf", "-inf", "Infinity",
        "9223372036854775807", "9223372036854775808", "-9223372036854775809", "0x7fffffffffffffff", "0x1F", "0b101",
        "1,5", "1.5", "1.5.5", "12:30", "25:61", "PST", "UTC+14", "km", "mi", "lb", "°F", "°C", "EUR", "USD", "JPY",
        "true", "false", "null", "{}", "[]", "{\"a\":", "[[[[[[", "\"\\u0000\"", "[00:00.00]", "[99:99.99]",
        "[-1:00.00]", "[00:00.00][00:01.00]", "dynanotch://", "https://", "file:///", "zoom.us/j/", "meet.google.com/",
        "remind me to", "timer", "minutes", "hours", "note", "sin(", "sqrt(", "1/0", "0/0", "2^1024", "((((((",
    ]

    private func fuzzString(_ rng: inout Rng) -> String {
        var s = ""
        for _ in 0..<(1 + rng.int(12)) { s += FuzzTests.atoms[rng.int(FuzzTests.atoms.count)] }
        if rng.int(20) == 0 { s += String(repeating: FuzzTests.atoms[rng.int(FuzzTests.atoms.count)], count: rng.int(400)) }
        return s
    }

    private func fuzzJSON(_ rng: inout Rng) -> Data {
        let keys = ["id", "tool", "input", "command", "file_path", "url", "cwd", "session", "createdAt", "event",
                    "tag_name", "html_url", "assets", "name", "browser_download_url", "digest", "draft", "version",
                    "features", "title", "text", "syncedLyrics", "plainLyrics", "instrumental", "rates", "base",
                    "current", "daily", "results", "latitude", "longitude", "temperature_2m", "weather_code"]
        func value(_ depth: Int) -> Any {
            switch rng.int(depth > 3 ? 5 : 7) {
            case 0: return fuzzString(&rng)
            case 1: return [1e308, -1e308, 0, -1, 1.5, Double(Int.max)][rng.int(6)]
            case 2: return rng.int(2) == 0
            case 3: return NSNull()
            case 4: return rng.int(Int(Int32.max)) - Int(Int16.max)
            case 5: return (0..<rng.int(4)).map { _ in value(depth + 1) }
            default:
                var d: [String: Any] = [:]
                for _ in 0..<rng.int(6) { d[keys[rng.int(keys.count)]] = value(depth + 1) }
                return d
            }
        }
        var root: [String: Any] = [:]
        for _ in 0..<(1 + rng.int(8)) { root[keys[rng.int(keys.count)]] = value(0) }
        let data = (try? JSONSerialization.data(withJSONObject: root)) ?? Data()
        if rng.int(8) == 0, !data.isEmpty {   // broken JSON too
            return data.prefix(rng.int(data.count))
        }
        return data
    }

    func testLinkAndHookParsersSurviveGarbage() {
        var rng = Rng(state: 0x5EED_0001)
        for _ in 0..<iterations {
            let s = fuzzString(&rng)
            let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "dynanotch://notify?title=\(encoded)&body=\(encoded)&open=\(encoded)&duration=\(encoded)") {
                _ = NotifyURL.parse(url)
            }
            _ = URLHookPolicy.isPublic(action: s, argument: s)
            _ = URLHookPolicy.timerMinutes(s)
            _ = SafeFileName.sanitize(s, fallback: "x")
            _ = ApprovalText.sanitize(s)
            _ = AgentSummary.detail(tool: s, input: ["command": s, "file_path": s, "url": s])
            _ = AgentSummary.statusDetail(event: "PreToolUse", tool: s, input: ["command": s])
            _ = AgentRequest.isValidID(s)
            _ = DisplaySelection.parse(s)
            _ = PopupTarget.openURL(s)
        }
    }

    func testJSONParsersSurviveGarbage() {
        var rng = Rng(state: 0x5EED_0002)
        let decoder = JSONDecoder()
        for _ in 0..<iterations {
            let data = fuzzJSON(&rng)
            _ = AgentRequest.parse(data)
            _ = AgentSessionStatus.parse(data)
            _ = ReleaseNotes.decode(data)
            _ = LRCLibParser.parse(data)
            _ = CurrencyRates.parse(data)
            _ = OpenMeteoParser.parse(data, locationName: "x", now: Date())
            _ = OpenMeteoParser.parseGeocoding(data)
            if let release = try? decoder.decode(GitHubRelease.self, from: data) {
                _ = UpdateCheck.evaluate(release, current: "3.3.0")
            }
        }
    }

    func testTextParsersSurviveGarbage() {
        var rng = Rng(state: 0x5EED_0003)
        let context = ConvertContext(homeCurrency: "EUR", rates: nil, timeZone: TimeZone(identifier: "UTC") ?? .current,
                                     now: Date(timeIntervalSince1970: 1_800_000_000), locale: Locale(identifier: "en_US"))
        for _ in 0..<iterations {
            let s = fuzzString(&rng)
            _ = SmartConvert.convert(s, context: context)
            _ = SecretDetector.scan(s)
            _ = SmartConvert.parseNumber(s)
            _ = SmartConvert.looksLikeCurrency(s)
            _ = Calculator.evaluate(s)
            _ = LRCParser.parse(s)
            _ = VoiceCommand.parse(s)
            _ = AdapterParser.parse(line: s)
            _ = ClipClassifier.preview(s)
            _ = LinkCleaner.clean(s)
            _ = MeetingLink.detect(in: [s, nil, s])
            _ = ReleaseNotes.fromMarkdown(s, version: s)
            _ = AppVersion(s)
            _ = HotKeyMap.parse(s)
            _ = PanelTab.parseList(s)
            _ = AlertSounds.parse(s)
        }
    }

    func testFormattersSurviveExtremeNumbers() {
        let values: [Double] = [0, -0.0, 1, -1, 59.999, 60, 3599, 3600, 86_400 * 365 * 100, 1e15, 1e18, 9.3e18, 1e300,
                                -1e300, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, .leastNonzeroMagnitude,
                                .infinity, -.infinity, .nan]
        for v in values {
            _ = Format.time(v)
            _ = Format.countdown(v)
            _ = Format.percent(v)
            _ = Format.currency(v)
        }
    }
}
