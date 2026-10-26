import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum Format {
    /// "0:00", "3:07", "1:02:03"; NaN/neg/inf → "0:00".
    public static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Clamps 0...1 → "0%"..."100%".
    public static func percent(_ level: Double) -> String {
        let clamped = level.isNaN ? 0 : min(1, max(0, level))
        return "\(Int((clamped * 100).rounded()))%"
    }

    /// <=0 "now", "in 5 min", "in 1 h", "in 1 h 20 min".
    public static func relativeMinutes(_ minutes: Int) -> String {
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "in \(h) h" : "in \(h) h \(m) min"
    }

    /// Short-time range, e.g. "09:00 – 10:30" (format depends on locale).
    public static func clockRange(start: Date, end: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: start) + " – " + formatter.string(from: end)
    }
}
