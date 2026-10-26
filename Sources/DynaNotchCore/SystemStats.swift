import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct CPUTicks: Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }
}

public enum SystemMath {
    /// Busy fraction 0...1 between two tick samples; 0 when nothing changed or counters went backwards.
    public static func cpuUsage(previous: CPUTicks, current: CPUTicks) -> Double {
        func delta(_ a: UInt64, _ b: UInt64) -> Double { b >= a ? Double(b - a) : 0 }
        let busy = delta(previous.user, current.user) + delta(previous.system, current.system)
            + delta(previous.nice, current.nice)
        let total = busy + delta(previous.idle, current.idle)
        guard total > 0 else { return 0 }
        return min(1, max(0, busy / total))
    }

    /// Bytes per second; a counter reset/wrap yields 0.
    public static func rate(previous: UInt64, current: UInt64, interval: TimeInterval) -> Double {
        guard interval > 0, current >= previous else { return 0 }
        return Double(current - previous) / interval
    }
}

extension Format {
    /// "0 B", "512 B", "1.5 KB", "12 MB", "1.2 GB" (1000-based, one decimal below 10).
    public static func bytes(_ count: Double) -> String {
        guard count.isFinite, count > 0 else { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = count
        var index = 0
        while value >= 1000 && index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 { return "\(Int(value)) B" }
        if value < 10 {
            let rounded = (value * 10).rounded() / 10
            if rounded < 10 { return String(format: "%.1f %@", rounded, units[index]) }
        }
        return "\(Int(value.rounded())) \(units[index])"
    }

    public static func rate(_ bytesPerSecond: Double) -> String {
        bytes(bytesPerSecond) + "/s"
    }

    /// "950", "12.3K", "4.5M", "1.2B".
    public static func tokens(_ n: Int) -> String {
        let v = Double(max(0, n))
        func fmt(_ x: Double, _ suffix: String) -> String {
            x < 100 ? String(format: "%.1f%@", x, suffix) : "\(Int(x.rounded()))\(suffix)"
        }
        if v >= 1_000_000_000 { return fmt(v / 1_000_000_000, "B") }
        if v >= 1_000_000 { return fmt(v / 1_000_000, "M") }
        if v >= 1_000 { return fmt(v / 1_000, "K") }
        return "\(Int(v))"
    }

    /// "2h 05m", "14m", "<1m".
    public static func countdown(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 60 else { return "<1m" }
        let minutes = Int(seconds / 60)
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        return "\(m)m"
    }

    /// "$0.00".
    public static func currency(_ usd: Double) -> String {
        let v = usd.isFinite ? max(0, usd) : 0
        return String(format: "$%.2f", v)
    }
}
