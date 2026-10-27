import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Screen lock ↔ unlock edge, reported once per change.
public enum LockTransition: String, Equatable {
    case locked, unlocked
}

/// Turns `com.apple.screenIsLocked` / `screenIsUnlocked` notifications into transitions; repeats are ignored
/// (the system can post the same notification twice, e.g. lock followed by display sleep).
public struct LockTransitionTracker: Equatable {
    public private(set) var isLocked: Bool

    public init(isLocked: Bool = false) {
        self.isLocked = isLocked
    }

    public mutating func update(locked: Bool) -> LockTransition? {
        guard locked != isLocked else { return nil }
        isLocked = locked
        return locked ? .locked : .unlocked
    }
}

/// What the lock-screen strip shows: the weather and the connected devices' batteries.
public struct LockScreenSummary: Equatable {
    public struct Weather: Equatable {
        public var symbol: String
        public var temperature: String
        public var detail: String
        public var place: String
    }

    public struct Device: Equatable, Identifiable {
        public var id: String
        public var name: String
        public var symbol: String
        public var level: Int
        public var isCharging: Bool
    }

    public var weather: Weather?
    public var devices: [Device]

    public var isEmpty: Bool { weather == nil && devices.isEmpty }

    /// The temperature is already in the chosen unit (Open-Meteo `temperature_unit`).
    /// Accessories first (in the given order), the Mac last; devices without a known level are dropped. AirPods show
    /// the lower earbud when there is no single level.
    public static func make(weather: WeatherSnapshot?, devices: [DeviceBattery], maxDevices: Int = 3) -> LockScreenSummary {
        let w = weather.map { snapshot -> Weather in
            let deg = "\(Int(snapshot.temperature.rounded()))°"
            let hiLo = "H \(Int(snapshot.high.rounded()))°  L \(Int(snapshot.low.rounded()))°"
            return Weather(symbol: snapshot.symbolName, temperature: deg, detail: "\(snapshot.summary) · \(hiLo)",
                           place: snapshot.locationName)
        }
        let accessories = devices.filter { $0.kind != .mac }
        let mac = devices.filter { $0.kind == .mac }
        let items: [Device] = (accessories + mac).compactMap { device in
            let earbuds = [device.left, device.right].compactMap { $0 }
            guard let level = device.level ?? earbuds.min() else { return nil }
            return Device(id: device.id, name: device.name, symbol: device.kind.symbolName,
                          level: max(0, min(100, level)), isCharging: device.isCharging)
        }
        return LockScreenSummary(weather: w, devices: Array(items.prefix(max(0, maxDevices))))
    }
}

/// Where the lock-screen widgets sit: centred on the main display, a little below the system clock.
public enum LockScreenLayout {
    /// Top of the widgets, as a fraction of the screen height from the top (the clock ends at about 28 %).
    public static let topFraction: CGFloat = 0.34

    /// Window rect in AppKit screen coordinates (origin bottom-left) for widgets of `size` on a screen `screenFrame`.
    public static func widgetsRect(size: CGSize, screenFrame: CGRect) -> CGRect {
        let top = screenFrame.maxY - (screenFrame.height * topFraction).rounded()
        return CGRect(x: (screenFrame.midX - size.width / 2).rounded(), y: top - size.height,
                      width: size.width, height: size.height)
    }
}
