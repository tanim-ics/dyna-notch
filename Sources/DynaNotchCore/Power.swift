import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct BatteryInfo: Equatable {
    /// 0...1
    public var level: Double
    public var isCharging: Bool
    public var isPluggedIn: Bool
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?

    public init(level: Double, isCharging: Bool, isPluggedIn: Bool, minutesToEmpty: Int? = nil, minutesToFull: Int? = nil) {
        self.level = level
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesToEmpty = minutesToEmpty
        self.minutesToFull = minutesToFull
    }
}

public enum PowerEvent: Equatable {
    case pluggedIn(BatteryInfo), unplugged(BatteryInfo), lowBattery(BatteryInfo, threshold: Int)
}

public struct PowerEventDetector {
    private let thresholds: [Int]
    private var last: BatteryInfo?
    private var armed: Set<Int> = []
    private static let epsilon = 1e-9
    private static let rearmMargin = 5.0

    /// `thresholds` are percentages (e.g. 20 = 20 %).
    public init(thresholds: [Int] = [20, 10]) {
        self.thresholds = Array(Set(thresholds)).sorted(by: >)
    }

    /// First call only records state (no events). Plug state change → plugged/unplugged.
    /// Crossing a threshold downward while not plugged in → lowBattery once; re-armed when plugged in
    /// (and above the threshold) or level > threshold + 5.
    public mutating func update(_ info: BatteryInfo) -> [PowerEvent] {
        let percent = info.level * 100
        guard let previous = last else {
            last = info
            armed = Set(thresholds.filter { percent > Double($0) + Self.epsilon })
            return []
        }
        last = info

        var events: [PowerEvent] = []
        if previous.isPluggedIn != info.isPluggedIn {
            events.append(info.isPluggedIn ? .pluggedIn(info) : .unplugged(info))
        }

        if !info.isPluggedIn {
            let crossed = thresholds.filter { armed.contains($0) && percent <= Double($0) + Self.epsilon }
            if let lowest = crossed.min() {
                events.append(.lowBattery(info, threshold: lowest))
                crossed.forEach { armed.remove($0) }
            }
        }

        for t in thresholds {
            let above = percent > Double(t) + Self.epsilon
            if (info.isPluggedIn && above) || percent > Double(t) + Self.rearmMargin {
                armed.insert(t)
            }
        }
        return events
    }
}
