import Foundation

/// Mac Vitals (CONTRACTS §6.18): pure checks behind the heat / memory / disk / runaway-app alerts.
public enum Vitals {
    /// CPU time used between two samples as % of one core (100 = one core busy).
    public static func cpuPercent(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / 1e9 / elapsed * 100
    }

    /// Under 10 GB or under 5 % free.
    public static func diskLow(free: Int64, total: Int64) -> Bool {
        guard total > 0, free >= 0 else { return false }
        return free < 10_000_000_000 || Double(free) / Double(total) < 0.05
    }

    /// `ProcessInfo.ThermalState.rawValue` → title for serious (2) / critical (3), nil otherwise.
    public static func thermalTitle(_ raw: Int) -> String? {
        switch raw {
        case 2: return "Your Mac is running hot"
        case 3: return "Your Mac is very hot"
        default: return nil
        }
    }

    /// `kern.memorystatus_vm_pressure_level` (1 normal, 2 warning, 4 critical) → 0 none, 1 tight, 2 almost full.
    /// The dispatch memory-pressure event alone is not enough: macOS sends short "warning" blips while Activity
    /// Monitor's pressure is still green, so the alert only fires when this level confirms it.
    public static func memorySeverity(pressureLevel: Int) -> Int {
        switch pressureLevel {
        case 4...: return 2
        case 2, 3: return 1
        default: return 0
        }
    }

    public static func gigabytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return gb >= 10 ? "\(Int(gb.rounded())) GB" : String(format: "%.1f GB", gb)
    }
}

/// Apps that stay at ≥ 90 % CPU for two samples in a row; each reported once until it drops below again.
public struct RunawayTracker: Equatable {
    public static let threshold: Double = 90
    private var hot: Set<Int32> = []
    private var reported: Set<Int32> = []

    public init() {}

    public mutating func update(_ percent: [Int32: Double]) -> [Int32] {
        var fresh: [Int32] = []
        var nowHot: Set<Int32> = []
        for (pid, p) in percent where p >= RunawayTracker.threshold {
            nowHot.insert(pid)
            if hot.contains(pid), !reported.contains(pid) {
                fresh.append(pid)
                reported.insert(pid)
            }
        }
        reported = reported.intersection(nowHot)   // calmed down → may be reported again later
        hot = nowHot
        return fresh.sorted()
    }
}
