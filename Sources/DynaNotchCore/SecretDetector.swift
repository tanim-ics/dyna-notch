import Foundation

/// Clipboard text that shouldn't be kept in history (docs/SECURITY.md §6). Definite secrets are never stored;
/// likely ones (one-time codes, random-looking tokens) are kept for `likelyLifetime` and then removed.
public enum SecretKind: String, Equatable, CaseIterable {
    case privateKey, accessToken, password, cardNumber, iban, oneTimeCode, randomToken

    public var title: String {
        switch self {
        case .privateKey: return "private key"
        case .accessToken: return "access token"
        case .password: return "password"
        case .cardNumber: return "card number"
        case .iban: return "IBAN"
        case .oneTimeCode: return "one-time code"
        case .randomToken: return "random token"
        }
    }
}

public enum SecretVerdict: Equatable {
    case secret(SecretKind)
    case likely(SecretKind)
}

public enum SecretDetector {
    public static let likelyLifetime: TimeInterval = 120
    /// Long text (documents, logs) is only checked for keys and tokens, not for codes or numbers.
    static let shortTextLimit = 200

    public static func scan(_ text: String) -> SecretVerdict? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isPrivateKey(trimmed) { return .secret(.privateKey) }
        if matchesAny(trimmed, tokenPatterns) { return .secret(.accessToken) }
        if matchesAny(trimmed, passwordPatterns) { return .secret(.password) }
        guard trimmed.count <= shortTextLimit else { return nil }
        if isCardNumber(trimmed) { return .secret(.cardNumber) }
        if isIBAN(trimmed) { return .secret(.iban) }
        if isOneTimeCode(trimmed) { return .likely(.oneTimeCode) }
        if isRandomToken(trimmed) { return .likely(.randomToken) }
        return nil
    }

    // MARK: Rules

    static func isPrivateKey(_ s: String) -> Bool {
        s.contains("-----BEGIN") && (s.contains("PRIVATE KEY-----") || s.contains("PRIVATE KEY BLOCK-----"))
    }

    static let tokenPatterns: [String] = [
        #"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#,                         // AWS access key id
        #"\bgh[pousr]_[A-Za-z0-9]{36,}\b"#,                      // GitHub tokens
        #"\bgithub_pat_[A-Za-z0-9_]{40,}\b"#,
        #"\bglpat-[A-Za-z0-9_-]{20,}\b"#,                        // GitLab
        #"\bxox[abposr]-[A-Za-z0-9-]{10,}\b"#,                   // Slack
        #"\bsk-ant-[A-Za-z0-9_-]{20,}"#,                         // Anthropic
        #"\bsk-(proj-)?[A-Za-z0-9_-]{32,}"#,                     // OpenAI
        #"\b[rs]k_live_[A-Za-z0-9]{16,}\b"#,                     // Stripe
        #"\bAIza[0-9A-Za-z_-]{35}\b"#,                           // Google API key
        #"\bnpm_[A-Za-z0-9]{36}\b"#,                             // npm
        #"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#,   // JWT
        #"(?i)\bbearer\s+[A-Za-z0-9._~+/-]{20,}=*"#,
    ]

    static let passwordPatterns: [String] = [
        // key = value (DB_PASSWORD=…, "api_key": "…"); a value that is code (readLine(), getenv(…)) doesn't count
        #"(?i)(?<![a-z0-9])(pass(word)?|passwd|pwd|secret|api[_-]?key|access[_-]?token|client[_-]?secret)["']?\s*[:=]\s*["']?[^\s"'()]{4,}(?=[\s"',;]|$)"#,
        #"\b[a-z][a-z0-9+.-]*://[^\s:/@]+:[^\s@/]{3,}@[^\s]+"#,    // scheme://user:password@host
    ]

    static func matchesAny(_ s: String, _ patterns: [String]) -> Bool {
        patterns.contains { s.range(of: $0, options: .regularExpression) != nil }
    }

    /// The whole text is a 13–19 digit number (spaces / dashes allowed) that passes the Luhn check.
    static func isCardNumber(_ s: String) -> Bool {
        guard s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == " " || $0 == "-") }) else { return false }
        let digits = s.compactMap { $0.wholeNumberValue }
        guard (13...19).contains(digits.count), let first = digits.first, (2...6).contains(first) else { return false }
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    /// The whole text is an IBAN (spaces allowed) with a valid mod-97 check.
    static func isIBAN(_ s: String) -> Bool {
        let compact = s.replacingOccurrences(of: " ", with: "").uppercased()
        guard (15...34).contains(compact.count), compact.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            return false
        }
        let chars = Array(compact)
        guard chars[0].isLetter, chars[1].isLetter, chars[2].isNumber, chars[3].isNumber else { return false }
        var remainder = 0
        for ch in chars[4...] + chars[0..<4] {
            let value: Int
            if let digit = ch.wholeNumberValue { value = digit } else if let ascii = ch.asciiValue { value = Int(ascii) - 55 } else { return false }
            for d in String(value) { remainder = (remainder * 10 + (d.wholeNumberValue ?? 0)) % 97 }
        }
        return remainder == 1
    }

    /// 6–8 digits on their own, optionally split in two ("123 456").
    static func isOneTimeCode(_ s: String) -> Bool {
        let compact = s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        guard (6...8).contains(compact.count), compact.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        return s.filter({ $0 == " " || $0 == "-" }).count <= 1
    }

    /// One word, 24–200 characters, three or more character classes, high entropy, and not a URL, path, UUID or
    /// plain hex hash.
    static func isRandomToken(_ s: String) -> Bool {
        guard (24...200).contains(s.count), !s.contains(where: { $0.isWhitespace }) else { return false }
        if s.contains("://") || s.hasPrefix("/") || s.hasPrefix("~") || s.contains("@") { return false }
        if s.range(of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
                   options: .regularExpression) != nil { return false }
        if s.allSatisfy({ $0.isHexDigit }) { return false }
        let classes = [s.contains { $0.isLowercase }, s.contains { $0.isUppercase }, s.contains { $0.isNumber },
                       s.contains { !$0.isLetter && !$0.isNumber }].filter { $0 }.count
        guard classes >= 3 else { return false }
        return entropy(s) >= 4.0
    }

    /// Shannon entropy in bits per character.
    static func entropy(_ s: String) -> Double {
        var counts: [Character: Int] = [:]
        for ch in s { counts[ch, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0) { total, c in
            let p = Double(c) / n
            return total - p * log2(p)
        }
    }
}
