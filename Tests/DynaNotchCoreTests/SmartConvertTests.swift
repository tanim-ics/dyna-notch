import XCTest
@testable import DynaNotchCore

final class SmartConvertTests: XCTestCase {
    private let rates = CurrencyRates(base: "EUR", date: "2026-10-30", rates: ["USD": 1.1, "GBP": 0.85, "CHF": 0.95])
    private let us = Locale(identifier: "en_US")
    private let vienna = TimeZone(identifier: "Europe/Vienna") ?? .current
    // 2026-11-01 10:00 UTC (a Sunday; Vienna is UTC+1 in winter)
    private let now = Date(timeIntervalSince1970: 1_793_527_200)

    private func run(_ text: String, home: String = "EUR", rates: CurrencyRates? = nil) -> SmartConversion? {
        SmartConvert.convert(text, context: ConvertContext(homeCurrency: home, rates: rates ?? self.rates,
                                                           timeZone: vienna, now: now, locale: us))
    }

    func testParseNumber() {
        XCTAssertEqual(SmartConvert.parseNumber("1,299.99"), 1299.99)
        XCTAssertEqual(SmartConvert.parseNumber("1.299,99"), 1299.99)
        XCTAssertEqual(SmartConvert.parseNumber("42,50"), 42.5)
        XCTAssertEqual(SmartConvert.parseNumber("1,299"), 1299)
        XCTAssertEqual(SmartConvert.parseNumber("0.125"), 0.125)
        XCTAssertEqual(SmartConvert.parseNumber("1.000.000"), 1_000_000)
        XCTAssertNil(SmartConvert.parseNumber("abc"))
    }

    func testCurrency() {
        XCTAssertEqual(run("$110")?.result, "€100")
        XCTAssertEqual(run("€100")?.result, "$110")              // already home → USD
        XCTAssertEqual(run("100 GBP")?.result, "€117.65")
        XCTAssertEqual(run("CHF 19")?.result, "€20")
        XCTAssertEqual(run("€10", home: "USD")?.result, "$11")
        XCTAssertEqual(run("$10", home: "USD")?.result, "€9.09")
        XCTAssertEqual(run("$110")?.kind, .currency)
        XCTAssertNil(SmartConvert.convert("$110", context: ConvertContext(homeCurrency: "EUR", rates: nil)))
        XCTAssertTrue(SmartConvert.looksLikeCurrency("1.299,99 €"))
        XCTAssertFalse(SmartConvert.looksLikeCurrency("hello"))
    }

    func testUnits() {
        XCTAssertEqual(run("5 mi")?.result, "8.05 km")
        XCTAssertEqual(run("10km")?.result, "6.21 mi")
        XCTAssertEqual(run("212°F")?.result, "100°C")
        XCTAssertEqual(run("20 C")?.result, "68°F")
        XCTAssertEqual(run("1 gal")?.result, "3.79 L")
        XCTAssertEqual(run("2 fl oz")?.result, "59.1 ml")
        XCTAssertEqual(run("150 lbs")?.result, "68 kg")
        XCTAssertEqual(run("100 km/h")?.result, "62.1 mph")
        XCTAssertEqual(run("6 ft")?.kind, .length)
        XCTAssertNil(run("Hello world"))
        XCTAssertNil(run("magic"))
    }

    func testTimeZones() {
        XCTAssertEqual(run("3pm PST")?.result, "00:00 GMT+1 +1 day")
        XCTAssertEqual(run("10:30 UTC")?.result, "11:30 GMT+1")
        XCTAssertNil(run("13pm PST"))
        XCTAssertNil(run("3pm XYZQ"))
    }

    func testNumbers() {
        XCTAssertEqual(run("0x1F")?.result, "31")
        XCTAssertEqual(run("0b1010")?.result, "10")
        XCTAssertEqual(run("1793527200")?.result, "2026-11-01 11:00")
        XCTAssertEqual(run("1793527200000")?.kind, .timestamp)
        XCTAssertNil(run("0664123456"))       // a phone number is not a timestamp
    }

    func testLimits() {
        XCTAssertNil(run(String(repeating: "1", count: 40) + " km"))
        XCTAssertNil(run("5 mi\n6 km"))
    }

    func testRatesParse() {
        let json = #"{"amount":1.0,"base":"EUR","date":"2026-10-30","rates":{"USD":1.0786,"GBP":0.8312}}"#
        let r = CurrencyRates.parse(Data(json.utf8))
        XCTAssertEqual(r?.base, "EUR")
        XCTAssertEqual(r?.date, "2026-10-30")
        XCTAssertEqual(r?.rates["USD"], 1.0786)
        XCTAssertNil(CurrencyRates.parse(Data("{}".utf8)))
    }
}
