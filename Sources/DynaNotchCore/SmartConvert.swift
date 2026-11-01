import Foundation

/// Exchange rates from Frankfurter (ECB): `rates[code]` = units of `code` per 1 `base`.
public struct CurrencyRates: Equatable, Codable {
    public var base: String
    public var date: String
    public var rates: [String: Double]

    public init(base: String, date: String, rates: [String: Double]) {
        self.base = base
        self.date = date
        self.rates = rates
    }

    /// Frankfurter `/v1/latest` JSON: {"base":"EUR","date":"2026-10-30","rates":{"USD":1.08,…}}.
    public static func parse(_ data: Data) -> CurrencyRates? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = obj["base"] as? String, let raw = obj["rates"] as? [String: Any] else { return nil }
        var rates: [String: Double] = [:]
        for (code, value) in raw {
            if let d = value as? Double { rates[code] = d } else if let n = value as? NSNumber { rates[code] = n.doubleValue }
        }
        guard !rates.isEmpty else { return nil }
        return CurrencyRates(base: base, date: obj["date"] as? String ?? "", rates: rates)
    }

    private func rate(_ code: String) -> Double? { code == base ? 1 : rates[code] }

    public func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let f = rate(from), let t = rate(to), f > 0 else { return nil }
        return amount / f * t
    }

    public var codes: [String] { ([base] + rates.keys).sorted() }
}

public enum ConversionKind: String, Equatable {
    case currency, length, mass, temperature, volume, speed, time, number, timestamp
}

public struct SmartConversion: Equatable {
    public var kind: ConversionKind
    public var source: String
    public var result: String
    public var symbol: String

    public init(kind: ConversionKind, source: String, result: String, symbol: String) {
        self.kind = kind
        self.source = source
        self.result = result
        self.symbol = symbol
    }
}

public struct ConvertContext {
    public var homeCurrency: String
    public var rates: CurrencyRates?
    public var timeZone: TimeZone
    public var now: Date
    public var locale: Locale

    public init(homeCurrency: String, rates: CurrencyRates?, timeZone: TimeZone = .current, now: Date = Date(),
                locale: Locale = .current) {
        self.homeCurrency = homeCurrency
        self.rates = rates
        self.timeZone = timeZone
        self.now = now
        self.locale = locale
    }
}

/// Smart Copy (CONTRACTS §6.13): turns a short copied text into its most useful conversion.
public enum SmartConvert {
    public static let maxLength = 32

    static let currencySymbols: [String: String] = ["€": "EUR", "$": "USD", "US$": "USD", "£": "GBP", "¥": "JPY",
                                                    "₹": "INR", "₩": "KRW", "₺": "TRY", "₽": "RUB", "R$": "BRL",
                                                    "A$": "AUD", "C$": "CAD", "Fr.": "CHF", "kr": "SEK"]
    static let symbolFor: [String: String] = ["EUR": "€", "USD": "$", "GBP": "£", "JPY": "¥", "INR": "₹",
                                              "KRW": "₩", "TRY": "₺", "BRL": "R$", "AUD": "A$", "CAD": "C$"]
    /// Codes accepted without rates loaded (the rates list extends it).
    static let knownCodes: Set<String> = ["EUR", "USD", "GBP", "JPY", "CHF", "INR", "CNY", "AUD", "CAD", "SEK", "NOK",
                                          "DKK", "PLN", "CZK", "HUF", "TRY", "BRL", "MXN", "KRW", "SGD", "HKD", "NZD",
                                          "ZAR", "BDT", "RON", "ILS", "THB", "IDR", "PHP", "MYR", "ISK", "BGN"]

    public static func convert(_ text: String, context: ConvertContext) -> SmartConversion? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= maxLength, !t.contains("\n") else { return nil }
        return number(t, context) ?? currency(t, context) ?? unit(t, context) ?? time(t, context)
    }

    // MARK: Numbers

    /// "1,299.99" / "1.299,99" / "42,50" / "1,299" → Double. A single separator followed by exactly three digits
    /// is grouping.
    public static func parseNumber(_ s: String) -> Double? {
        let allowed = CharacterSet(charactersIn: "0123456789.,-")
        guard !s.isEmpty, s.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              s.contains(where: { $0.isNumber }) else { return nil }
        let lastDot = s.lastIndex(of: "."), lastComma = s.lastIndex(of: ",")
        var cleaned = s
        if let d = lastDot, let c = lastComma {
            let decimal: Character = d > c ? "." : ","
            let group: Character = decimal == "." ? "," : "."
            cleaned = String(s.filter { $0 != group }.map { $0 == decimal ? "." : $0 })
        } else if let sep = lastDot ?? lastComma {
            let ch = s[sep]
            let after = s[s.index(after: sep)...]
            let count = s.filter { $0 == ch }.count
            if count > 1 || (after.count == 3 && s.first != "0") {
                cleaned = s.filter { $0 != ch }
            } else {
                cleaned = s.replacingOccurrences(of: String(ch), with: ".")
            }
        }
        return Double(cleaned)
    }

    static func format(_ value: Double, locale: Locale, maxDigits: Int? = nil) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        let a = abs(value)
        let digits = maxDigits ?? (a >= 100 ? 0 : a >= 10 ? 1 : 2)
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func number(_ t: String, _ c: ConvertContext) -> SmartConversion? {
        let lower = t.lowercased()
        if lower.hasPrefix("0x"), lower.count > 2, let v = UInt64(lower.dropFirst(2), radix: 16) {
            return SmartConversion(kind: .number, source: t, result: "\(v)", symbol: "number")
        }
        if lower.hasPrefix("0b"), lower.count > 2, let v = UInt64(lower.dropFirst(2), radix: 2) {
            return SmartConversion(kind: .number, source: t, result: "\(v)", symbol: "number")
        }
        if t.allSatisfy({ $0.isASCII && $0.isNumber }), t.count == 10 || t.count == 13, t.first == "1",
           let raw = Double(t) {
            let seconds = t.count == 13 ? raw / 1000 : raw
            let f = DateFormatter()
            f.locale = c.locale
            f.timeZone = c.timeZone
            f.dateFormat = "yyyy-MM-dd HH:mm"
            return SmartConversion(kind: .timestamp, source: t, result: f.string(from: Date(timeIntervalSince1970: seconds)),
                                   symbol: "calendar")
        }
        return nil
    }

    // MARK: Currency

    private static func currency(_ t: String, _ c: ConvertContext) -> SmartConversion? {
        var codes = knownCodes
        if let r = c.rates { codes.formUnion(r.codes) }
        var code: String?
        var amountText = t
        // Longest symbols first so "US$" wins over "$".
        for (sym, iso) in currencySymbols.sorted(by: { $0.key.count > $1.key.count }) {
            if t.hasPrefix(sym) { code = iso; amountText = String(t.dropFirst(sym.count)); break }
            if t.hasSuffix(sym) { code = iso; amountText = String(t.dropLast(sym.count)); break }
        }
        if code == nil {
            let parts = t.split(separator: " ").map(String.init)
            if parts.count == 2 {
                if codes.contains(parts[0].uppercased()), parts[0].count == 3 { code = parts[0].uppercased(); amountText = parts[1] }
                else if codes.contains(parts[1].uppercased()), parts[1].count == 3 { code = parts[1].uppercased(); amountText = parts[0] }
            } else if t.count > 3, codes.contains(String(t.suffix(3)).uppercased()),
                      String(t.suffix(3)).allSatisfy({ $0.isLetter }) {
                code = String(t.suffix(3)).uppercased(); amountText = String(t.dropLast(3))
            } else if t.count > 3, codes.contains(String(t.prefix(3)).uppercased()),
                      String(t.prefix(3)).allSatisfy({ $0.isLetter }) {
                code = String(t.prefix(3)).uppercased(); amountText = String(t.dropFirst(3))
            }
        }
        guard let from = code,
              let amount = parseNumber(amountText.trimmingCharacters(in: .whitespaces)) else { return nil }
        let home = c.homeCurrency.uppercased()
        let to = from == home ? (home == "USD" ? "EUR" : "USD") : home
        guard let rates = c.rates, let value = rates.convert(amount, from: from, to: to) else { return nil }
        let number = format(value, locale: c.locale, maxDigits: 2)
        let result = symbolFor[to].map { "\($0)\(number)" } ?? "\(number) \(to)"
        let symbol = to == "EUR" ? "eurosign.circle.fill" : to == "GBP" ? "sterlingsign.circle.fill"
            : to == "JPY" ? "yensign.circle.fill" : "dollarsign.circle.fill"
        return SmartConversion(kind: .currency, source: t, result: result, symbol: symbol)
    }

    /// Whether the text is an amount of money (so the rates are worth fetching).
    public static func looksLikeCurrency(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fake = CurrencyRates(base: "EUR", date: "", rates: Dictionary(uniqueKeysWithValues: knownCodes.map { ($0, 1) }))
        let context = ConvertContext(homeCurrency: "EUR", rates: fake)
        return t.count <= maxLength && currency(t, context) != nil
    }

    // MARK: Units

    private struct UnitRule {
        let names: [String]
        let from: Dimension
        let to: Dimension
        let label: String
        let kind: ConversionKind
        let symbol: String
    }

    private static let unitRules: [UnitRule] = [
        UnitRule(names: ["mi", "mile", "miles"], from: UnitLength.miles, to: UnitLength.kilometers, label: "km", kind: .length, symbol: "ruler"),
        UnitRule(names: ["km", "kilometer", "kilometers", "kilometre", "kilometres"], from: UnitLength.kilometers, to: UnitLength.miles, label: "mi", kind: .length, symbol: "ruler"),
        UnitRule(names: ["ft", "feet", "foot", "'"], from: UnitLength.feet, to: UnitLength.meters, label: "m", kind: .length, symbol: "ruler"),
        UnitRule(names: ["m", "meter", "meters", "metre", "metres"], from: UnitLength.meters, to: UnitLength.feet, label: "ft", kind: .length, symbol: "ruler"),
        UnitRule(names: ["in", "inch", "inches", "\""], from: UnitLength.inches, to: UnitLength.centimeters, label: "cm", kind: .length, symbol: "ruler"),
        UnitRule(names: ["cm"], from: UnitLength.centimeters, to: UnitLength.inches, label: "in", kind: .length, symbol: "ruler"),
        UnitRule(names: ["yd", "yard", "yards"], from: UnitLength.yards, to: UnitLength.meters, label: "m", kind: .length, symbol: "ruler"),
        UnitRule(names: ["lb", "lbs", "pound", "pounds"], from: UnitMass.pounds, to: UnitMass.kilograms, label: "kg", kind: .mass, symbol: "scalemass.fill"),
        UnitRule(names: ["kg", "kilo", "kilos", "kilogram", "kilograms"], from: UnitMass.kilograms, to: UnitMass.pounds, label: "lb", kind: .mass, symbol: "scalemass.fill"),
        UnitRule(names: ["oz", "ounce", "ounces"], from: UnitMass.ounces, to: UnitMass.grams, label: "g", kind: .mass, symbol: "scalemass.fill"),
        UnitRule(names: ["g", "gram", "grams"], from: UnitMass.grams, to: UnitMass.ounces, label: "oz", kind: .mass, symbol: "scalemass.fill"),
        UnitRule(names: ["°f", "f", "fahrenheit", "ºf"], from: UnitTemperature.fahrenheit, to: UnitTemperature.celsius, label: "°C", kind: .temperature, symbol: "thermometer.medium"),
        UnitRule(names: ["°c", "c", "celsius", "ºc"], from: UnitTemperature.celsius, to: UnitTemperature.fahrenheit, label: "°F", kind: .temperature, symbol: "thermometer.medium"),
        UnitRule(names: ["gal", "gallon", "gallons"], from: UnitVolume.gallons, to: UnitVolume.liters, label: "L", kind: .volume, symbol: "drop.fill"),
        UnitRule(names: ["l", "liter", "liters", "litre", "litres"], from: UnitVolume.liters, to: UnitVolume.gallons, label: "gal", kind: .volume, symbol: "drop.fill"),
        UnitRule(names: ["fl oz", "floz"], from: UnitVolume.fluidOunces, to: UnitVolume.milliliters, label: "ml", kind: .volume, symbol: "drop.fill"),
        UnitRule(names: ["ml"], from: UnitVolume.milliliters, to: UnitVolume.fluidOunces, label: "fl oz", kind: .volume, symbol: "drop.fill"),
        UnitRule(names: ["mph"], from: UnitSpeed.milesPerHour, to: UnitSpeed.kilometersPerHour, label: "km/h", kind: .speed, symbol: "speedometer"),
        UnitRule(names: ["km/h", "kmh", "kph"], from: UnitSpeed.kilometersPerHour, to: UnitSpeed.milesPerHour, label: "mph", kind: .speed, symbol: "speedometer"),
    ]

    private static func unit(_ t: String, _ c: ConvertContext) -> SmartConversion? {
        let lower = t.lowercased()
        // Longest unit names first ("fl oz" before "oz", "km/h" before "m").
        let candidates = unitRules.flatMap { rule in rule.names.map { ($0, rule) } }.sorted { $0.0.count > $1.0.count }
        for (name, rule) in candidates where lower.hasSuffix(name) {
            let numberPart = String(lower.dropLast(name.count)).trimmingCharacters(in: .whitespaces)
            // A bare letter unit needs the number right before it ("42 c", "42c"), never inside a word.
            guard !numberPart.isEmpty, let value = parseNumber(numberPart) else { continue }
            let converted = Measurement(value: value, unit: rule.from).converted(to: rule.to).value
            let result = "\(format(converted, locale: c.locale)) \(rule.label)".replacingOccurrences(of: " °", with: "°")
            return SmartConversion(kind: rule.kind, source: t, result: result, symbol: rule.symbol)
        }
        return nil
    }

    // MARK: Time zones

    private static func time(_ t: String, _ c: ConvertContext) -> SmartConversion? {
        let pattern = #"^(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\s+([A-Za-z]{2,5})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = regex.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        func group(_ i: Int) -> String? {
            guard let r = Range(m.range(at: i), in: t) else { return nil }
            return String(t[r])
        }
        guard var hour = group(1).flatMap({ Int($0) }), let abbr = group(4)?.uppercased(),
              let zone = TimeZone(abbreviation: abbr) else { return nil }
        let minute = group(2).flatMap { Int($0) } ?? 0
        if let ampm = group(3)?.lowercased() {
            guard (1...12).contains(hour) else { return nil }
            if ampm.hasPrefix("p"), hour != 12 { hour += 12 }
            if ampm.hasPrefix("a"), hour == 12 { hour = 0 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var sourceCal = Calendar(identifier: .gregorian)
        sourceCal.timeZone = zone
        var parts = sourceCal.dateComponents([.year, .month, .day], from: c.now)
        parts.hour = hour
        parts.minute = minute
        guard let date = sourceCal.date(from: parts) else { return nil }
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = c.timeZone
        let f = DateFormatter()
        f.locale = c.locale
        f.timeZone = c.timeZone
        f.dateFormat = "HH:mm"
        var result = f.string(from: date)
        let dayDiff = localCal.dateComponents([.day], from: localCal.startOfDay(for: sourceCal.startOfDay(for: c.now)),
                                              to: localCal.startOfDay(for: date)).day ?? 0
        let localAbbr = c.timeZone.abbreviation(for: date) ?? c.timeZone.identifier
        result += " \(localAbbr)"
        if dayDiff > 0 { result += " +\(dayDiff) day" } else if dayDiff < 0 { result += " \(dayDiff) day" }
        return SmartConversion(kind: .time, source: t, result: result, symbol: "clock.fill")
    }
}
