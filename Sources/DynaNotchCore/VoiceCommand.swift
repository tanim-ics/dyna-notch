import Foundation

/// Voice Notes (CONTRACTS §6.20): what a spoken sentence should do.
public enum VoiceCommand: Equatable {
    case reminder(String)
    case timer(minutes: Double)
    case note(String)

    public static func parse(_ transcript: String) -> VoiceCommand {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".!?,".contains(last) { text.removeLast() }
        let lower = text.lowercased()

        for prefix in ["remind me to ", "remind me ", "reminder to ", "reminder "] where lower.hasPrefix(prefix) {
            let rest = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { return .reminder(capitalizedFirst(rest)) }
        }
        if let minutes = timerMinutes(lower) { return .timer(minutes: minutes) }
        for prefix in ["take a note ", "note "] where lower.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        return .note(capitalizedFirst(text.trimmingCharacters(in: .whitespaces)))
    }

    static func timerMinutes(_ lower: String) -> Double? {
        let patterns = [
            #"^(?:set (?:a )?)?timer (?:for )?(\d+(?:[.,]\d+)?)\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|h)?$"#,
            #"^(?:start (?:a )?|set (?:a )?)?(\d+(?:[.,]\d+)?)[ -]?(seconds?|secs?|minutes?|mins?|hours?)[ -]timer$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let m = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                  let numberRange = Range(m.range(at: 1), in: lower),
                  let value = Double(lower[numberRange].replacingOccurrences(of: ",", with: ".")), value > 0 else { continue }
            let unit = Range(m.range(at: 2), in: lower).map { String(lower[$0]) } ?? "min"
            if unit.hasPrefix("s") { return value / 60 }
            if unit.hasPrefix("h") { return value * 60 }
            return value
        }
        return nil
    }

    private static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    /// What the island says afterwards.
    public var resultLabel: String {
        switch self {
        case .reminder: return "Reminder added"
        case .note: return "Note saved"
        case .timer(let minutes):
            if minutes < 1 { return "Timer \(Int((minutes * 60).rounded())) s" }
            return minutes == minutes.rounded() ? "Timer \(Int(minutes)) min" : String(format: "Timer %.1f min", minutes)
        }
    }
}
