import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import DynaNotchCore

final class V3DataTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15T08:00:00Z, on the hour

    // MARK: Clipboard

    func testClipClassifier() {
        XCTAssertEqual(ClipClassifier.kind(for: "https://example.com/a?b=1"), .link)
        XCTAssertEqual(ClipClassifier.kind(for: " www.apple.com "), .link)
        XCTAssertEqual(ClipClassifier.kind(for: "see https://x.com"), .text)
        XCTAssertEqual(ClipClassifier.kind(for: "#5E5CE6"), .color)
        XCTAssertEqual(ClipClassifier.kind(for: "#fff"), .color)
        XCTAssertEqual(ClipClassifier.kind(for: "#ggg"), .text)
        XCTAssertEqual(ClipClassifier.kind(for: "#12345"), .text)
        XCTAssertEqual(ClipClassifier.kind(for: ""), .text)
    }

    func testClipPreview() {
        XCTAssertEqual(ClipClassifier.preview("  a \n\n b\t c  "), "a b c")
        XCTAssertEqual(ClipClassifier.preview(String(repeating: "x", count: 500)).count, 200)
    }

    func testLinkCleaner() {
        XCTAssertEqual(LinkCleaner.clean("https://a.com/p?utm_source=x&id=3&fbclid=abc"), "https://a.com/p?id=3")
        XCTAssertEqual(LinkCleaner.clean("https://a.com/p?utm_source=x&UTM_medium=y"), "https://a.com/p")
        XCTAssertEqual(LinkCleaner.clean("https://youtu.be/abc?si=XYZ&t=10"), "https://youtu.be/abc?t=10")
        XCTAssertEqual(LinkCleaner.clean("https://example.com/?si=keep"), "https://example.com/?si=keep")
        XCTAssertEqual(LinkCleaner.clean("https://open.spotify.com/track/1?si=abc"), "https://open.spotify.com/track/1")
        XCTAssertEqual(LinkCleaner.clean("https://a.com/p?gclid=1#frag"), "https://a.com/p#frag")
        XCTAssertEqual(LinkCleaner.clean("hello ?utm_source=x"), "hello ?utm_source=x")
        XCTAssertEqual(LinkCleaner.clean("https://a.com/p"), "https://a.com/p")
    }

    func testHistoryDedupeAndPin() {
        var h = ClipboardHistory(limit: 3)
        h.add(ClipItem(kind: .text, text: "a", date: t0))
        h.add(ClipItem(kind: .text, text: "b", date: t0 + 1))
        h.add(ClipItem(kind: .text, text: "   ", date: t0 + 2))
        XCTAssertEqual(h.items.map(\.text), ["b", "a"])
        let aID = h.items[1].id
        h.togglePin(id: aID)
        XCTAssertEqual(h.items.map(\.text), ["a", "b"])
        h.add(ClipItem(kind: .text, text: "a", date: t0 + 3))
        XCTAssertEqual(h.items.first?.id, aID)
        XCTAssertEqual(h.items.first?.pinned, true)
        XCTAssertEqual(h.items.count, 2)
    }

    func testHistoryEviction() {
        var h = ClipboardHistory(limit: 2)
        h.add(ClipItem(kind: .text, text: "pinned", date: t0))
        h.togglePin(id: h.items[0].id)
        h.add(ClipItem(kind: .text, text: "1", date: t0 + 1))
        let evicted = h.add(ClipItem(kind: .text, text: "2", date: t0 + 2))
        XCTAssertEqual(evicted.map(\.text), ["1"])
        XCTAssertEqual(h.items.map(\.text), ["pinned", "2"])
    }

    func testHistoryImagesDedupeByHash() {
        var h = ClipboardHistory()
        h.add(ClipItem(kind: .image, text: "hash1", date: t0, imageFile: "a.png"))
        let evicted = h.add(ClipItem(kind: .image, text: "hash1", date: t0 + 1, imageFile: "b.png"))
        XCTAssertEqual(h.items.count, 1)
        XCTAssertEqual(h.items[0].imageFile, "a.png")
        XCTAssertEqual(evicted.map(\.imageFile), ["b.png"])
    }

    func testHistorySearchClearRemove() {
        var h = ClipboardHistory()
        h.add(ClipItem(kind: .text, text: "Crème brûlée", date: t0))
        h.add(ClipItem(kind: .text, text: "other", date: t0, sourceApp: "Safari"))
        XCTAssertEqual(h.search("creme").count, 1)
        XCTAssertEqual(h.search("safari").count, 1)
        XCTAssertEqual(h.search("  ").count, 2)
        h.togglePin(id: h.items[1].id)
        XCTAssertEqual(h.clear().count, 1)
        XCTAssertEqual(h.items.count, 1)
        XCTAssertNotNil(h.remove(id: h.items[0].id))
        XCTAssertNil(h.remove(id: UUID()))
        XCTAssertTrue(h.items.isEmpty)
    }

    func testHistoryCodableRoundTrip() throws {
        var h = ClipboardHistory(limit: 7)
        h.add(ClipItem(kind: .link, text: "https://a.com", date: t0, sourceApp: "Safari"))
        let data = try JSONEncoder().encode(h)
        XCTAssertEqual(try JSONDecoder().decode(ClipboardHistory.self, from: data), h)
    }

    // MARK: Lyrics

    func testLRCParse() {
        let lrc = """
        [ar:Someone]
        [ti:Song]
        [00:12.50]First line
        [00:05.00][00:20.00]Chorus
        [01:02.123]Late
        no tag here
        [00:30]
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.map(\.time), [5, 12.5, 20, 30, 62.123])
        XCTAssertEqual(lines.map(\.text), ["Chorus", "First line", "Chorus", "", "Late"])
    }

    func testLRCOffsetAndIndex() {
        let lines = LRCParser.parse("[offset:+500]\n[00:01.00]a\n[00:03.00]b")
        XCTAssertEqual(lines.map(\.time), [0.5, 2.5])
        XCTAssertNil(LRCParser.currentIndex(at: 0.1, in: lines))
        XCTAssertEqual(LRCParser.currentIndex(at: 0.5, in: lines), 0)
        XCTAssertEqual(LRCParser.currentIndex(at: 2.4, in: lines), 0)
        XCTAssertEqual(LRCParser.currentIndex(at: 99, in: lines), 1)
        XCTAssertNil(LRCParser.currentIndex(at: 5, in: []))
    }

    func testLRCLibParser() {
        let json = #"{"id":1,"instrumental":false,"plainLyrics":"a\nb","syncedLyrics":"[00:01.00]a\n[00:02.00]b"}"#
        let r = LRCLibParser.parse(Data(json.utf8))
        XCTAssertEqual(r?.synced.count, 2)
        XCTAssertEqual(r?.plain, "a\nb")
        let inst = LRCLibParser.parse(Data(#"{"id":2,"instrumental":true,"syncedLyrics":null}"#.utf8))
        XCTAssertEqual(inst?.synced, [])
        XCTAssertNil(LRCLibParser.parse(Data("garbage".utf8)))
        XCTAssertNil(LRCLibParser.parse(Data(#"{"code":404,"message":"not found"}"#.utf8)))
    }

    // MARK: AI usage

    private func line(_ ts: String, id: String, req: String = "r", input: Int = 10, output: Int = 5,
                      model: String = "claude-sonnet-5-5") -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","requestId":"\#(req)","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_creation_input_tokens":100,"cache_read_input_tokens":1000}}}"#
    }

    func testClaudeUsageParser() {
        let e = ClaudeUsageParser.parse(line: line("2027-01-15T08:10:00.123Z", id: "m1"))
        XCTAssertEqual(e?.usage, TokenUsage(input: 10, output: 5, cacheCreation: 100, cacheRead: 1000))
        XCTAssertEqual(e?.usage.total, 1115)
        XCTAssertEqual(e?.dedupeKey, "m1:r")
        XCTAssertEqual(e?.timestamp.timeIntervalSince(t0) ?? 0, 600.123, accuracy: 0.001)
        XCTAssertNil(ClaudeUsageParser.parse(line: #"{"type":"user","message":{"usage":{}}}"#))
        XCTAssertNil(ClaudeUsageParser.parse(line: "not json usage assistant"))
        XCTAssertNotNil(ClaudeUsageParser.parse(line: line("2027-01-15T08:10:00Z", id: "m2")))
    }

    func testModelPricing() {
        let u = TokenUsage(input: 1_000_000, output: 1_000_000)
        XCTAssertEqual(ModelPricing.cost(model: "claude-opus-5-5", usage: u), 90, accuracy: 1e-9)
        XCTAssertEqual(ModelPricing.cost(model: "claude-sonnet-5-5", usage: u), 18, accuracy: 1e-9)
        XCTAssertEqual(ModelPricing.cost(model: "claude-haiku-5-5", usage: u), 6, accuracy: 1e-9)
        XCTAssertEqual(ModelPricing.cost(model: "mystery", usage: TokenUsage(cacheRead: 1_000_000)), 0.3, accuracy: 1e-9)
    }

    func testUsageBlocks() {
        func entry(_ offset: TimeInterval, _ key: String) -> UsageEntry {
            UsageEntry(timestamp: t0 + offset, model: "claude-sonnet", usage: TokenUsage(input: 100), dedupeKey: key)
        }
        let entries = [entry(1800, "a"), entry(1800, "a"), entry(3600 * 4, "b"), entry(3600 * 5.6, "c"),
                       entry(3600 * 20, "d")]
        let blocks = UsageAggregator.blocks(entries)
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0].start, t0)
        XCTAssertEqual(blocks[0].end, t0 + 18000)
        XCTAssertEqual(blocks[0].entryCount, 2)
        XCTAssertEqual(blocks[0].usage.input, 200)
        XCTAssertEqual(blocks[1].start, t0 + 18000)
        XCTAssertEqual(blocks[2].start, t0 + 72000)
        XCTAssertEqual(UsageAggregator.activeBlock(entries, now: t0 + 3600 * 21)?.entryCount, 1)
        XCTAssertNil(UsageAggregator.activeBlock(entries, now: t0 + 3600 * 26))
        let s = UsageAggregator.summary(entries, from: t0, to: t0 + 3600 * 6)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.usage.input, 300)
    }

    func testCodexParser() {
        let l = #"{"timestamp":"2027-01-15T08:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_in_seconds":600},"secondary":{"used_percent":40,"window_minutes":10080,"resets_at":1800003600}}}}"#
        let r = CodexUsageParser.parse(line: l)
        XCTAssertEqual(r?.primary, RateWindow(usedPercent: 12.5, windowMinutes: 300, resetsAt: t0 + 600))
        XCTAssertEqual(r?.secondary?.resetsAt, t0 + 3600)
        XCTAssertEqual(r?.observedAt, t0)
        XCTAssertNil(CodexUsageParser.parse(line: #"{"payload":{"rate_limits":{}}}"#))
        XCTAssertNil(CodexUsageParser.parse(line: "{}"))
    }

    // MARK: Weather

    func testOpenMeteoParser() {
        let json = #"{"current":{"temperature_2m":19.4,"weather_code":2,"is_day":1},"daily":{"temperature_2m_max":[21.0],"temperature_2m_min":[12.0]}}"#
        let w = OpenMeteoParser.parse(Data(json.utf8), locationName: "Innsbruck", now: t0)
        XCTAssertEqual(w, WeatherSnapshot(temperature: 19.4, high: 21, low: 12, code: 2, isDay: true,
                                          locationName: "Innsbruck", fetchedAt: t0))
        XCTAssertEqual(w?.summary, "Partly Cloudy")
        XCTAssertEqual(w?.symbolName, "cloud.sun.fill")
        XCTAssertNil(OpenMeteoParser.parse(Data("{}".utf8), locationName: "", now: t0))
        let geo = OpenMeteoParser.parseGeocoding(Data(#"{"results":[{"latitude":47.26,"longitude":11.39,"name":"Innsbruck"}]}"#.utf8))
        XCTAssertEqual(geo?.name, "Innsbruck")
        XCTAssertEqual(geo?.latitude ?? 0, 47.26, accuracy: 1e-9)
        XCTAssertNil(OpenMeteoParser.parseGeocoding(Data(#"{"generationtime_ms":0.1}"#.utf8)))
    }

    func testWeatherCodes() {
        XCTAssertEqual(WeatherCode.symbol(code: 0, isDay: false), "moon.stars.fill")
        XCTAssertEqual(WeatherCode.symbol(code: 95, isDay: true), "cloud.bolt.rain.fill")
        XCTAssertEqual(WeatherCode.summary(code: 73), "Snow")
        XCTAssertEqual(TemperatureUnit.fahrenheit.symbol, "°F")
    }

    // MARK: System / formatting

    func testCPUAndRate() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 150, system: 75, idle: 925, nice: 0)
        XCTAssertEqual(SystemMath.cpuUsage(previous: a, current: b), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SystemMath.cpuUsage(previous: a, current: a), 0)
        XCTAssertEqual(SystemMath.cpuUsage(previous: b, current: a), 0)
        XCTAssertEqual(SystemMath.rate(previous: 1000, current: 3000, interval: 2), 1000)
        XCTAssertEqual(SystemMath.rate(previous: 3000, current: 1000, interval: 2), 0)
        XCTAssertEqual(SystemMath.rate(previous: 0, current: 10, interval: 0), 0)
    }

    func testByteFormatting() {
        XCTAssertEqual(Format.bytes(0), "0 B")
        XCTAssertEqual(Format.bytes(512), "512 B")
        XCTAssertEqual(Format.bytes(1500), "1.5 KB")
        XCTAssertEqual(Format.bytes(12_000_000), "12 MB")
        XCTAssertEqual(Format.bytes(1_240_000_000), "1.2 GB")
        XCTAssertEqual(Format.bytes(9_990), "10 KB")
        XCTAssertEqual(Format.bytes(.nan), "0 B")
        XCTAssertEqual(Format.rate(2_500), "2.5 KB/s")
    }

    func testTokenCountdownCurrency() {
        XCTAssertEqual(Format.tokens(950), "950")
        XCTAssertEqual(Format.tokens(12_345), "12.3K")
        XCTAssertEqual(Format.tokens(4_500_000), "4.5M")
        XCTAssertEqual(Format.tokens(250_000), "250K")
        XCTAssertEqual(Format.tokens(-5), "0")
        XCTAssertEqual(Format.countdown(30), "<1m")
        XCTAssertEqual(Format.countdown(14 * 60 + 5), "14m")
        XCTAssertEqual(Format.countdown(2 * 3600 + 5 * 60), "2h 05m")
        XCTAssertEqual(Format.currency(3.456), "$3.46")
        XCTAssertEqual(Format.currency(-1), "$0.00")
    }

    func testTodoCodable() throws {
        let item = TodoItem(text: "Ship v3", createdAt: t0)
        let data = try JSONEncoder().encode([item])
        XCTAssertEqual(try JSONDecoder().decode([TodoItem].self, from: data), [item])
    }
}
