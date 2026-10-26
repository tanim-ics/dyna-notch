import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum DeviceKind: String, Equatable, Hashable, CaseIterable {
    case mac, mouse, keyboard, trackpad, headphones, airpods, gamepad, other

    public var symbolName: String {
        switch self {
        case .mac: return "laptopcomputer"
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        case .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .headphones: return "headphones"
        case .airpods: return "airpods.pro"
        case .gamepad: return "gamecontroller.fill"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }

    /// From system_profiler's `device_minorType` plus the device name.
    public static func classify(minorType: String?, name: String) -> DeviceKind {
        let n = name.lowercased()
        if n.contains("airpods") || n.contains("beats") { return .airpods }
        switch (minorType ?? "").lowercased() {
        case "mouse": return .mouse
        case "keyboard": return .keyboard
        case "trackpad": return .trackpad
        case "headphones", "headset", "speaker": return .headphones
        case "gamepad", "joystick": return .gamepad
        default: break
        }
        if n.contains("mouse") || n.contains("mx master") { return .mouse }
        if n.contains("keyboard") { return .keyboard }
        if n.contains("trackpad") { return .trackpad }
        return .other
    }
}

public struct DeviceBattery: Equatable, Identifiable {
    /// Bluetooth address (upper-case), or "mac".
    public var id: String
    public var name: String
    public var kind: DeviceKind
    public var level: Int?
    public var left: Int?
    public var right: Int?
    public var caseLevel: Int?
    public var isCharging: Bool
    public var detail: String?

    public init(id: String, name: String, kind: DeviceKind, level: Int? = nil, left: Int? = nil, right: Int? = nil,
                caseLevel: Int? = nil, isCharging: Bool = false, detail: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.level = level
        self.left = left
        self.right = right
        self.caseLevel = caseLevel
        self.isCharging = isCharging
        self.detail = detail
    }

    /// Main level, else the lower earbud, else the case.
    public var displayLevel: Int? {
        if let level = level { return level }
        switch (left, right) {
        case let (l?, r?): return min(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return caseLevel
        }
    }

    var hasAnyLevel: Bool { displayLevel != nil }
}

public enum BluetoothProfilerParser {
    /// "86 %", "86%", "86\u{a0}%" → 86 (clamped 0...100).
    public static func percent(_ s: String) -> Int? {
        let digits = s.filter(\.isNumber)
        guard !digits.isEmpty, let v = Int(digits) else { return nil }
        return min(100, max(0, v))
    }

    /// Connected devices from `system_profiler -json SPBluetoothDataType` (with or without battery levels).
    public static func parse(_ data: Data) -> [DeviceBattery] {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let root = obj as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var result: [DeviceBattery] = []
        for controller in controllers {
            guard let connected = controller["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    func level(_ key: String) -> Int? { (info[key] as? String).flatMap(percent) }
                    let address = (info["device_address"] as? String)?.uppercased() ?? name
                    result.append(DeviceBattery(
                        id: address, name: name,
                        kind: DeviceKind.classify(minorType: info["device_minorType"] as? String, name: name),
                        level: level("device_batteryLevelMain") ?? level("device_batteryLevel"),
                        left: level("device_batteryLevelLeft"), right: level("device_batteryLevelRight"),
                        caseLevel: level("device_batteryLevelCase")))
                }
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

public enum DeviceBatteryMerge {
    /// Merges by id (else case-insensitive name). The first source sets name/kind; later sources only fill nil fields.
    public static func merge(_ sources: [[DeviceBattery]]) -> [DeviceBattery] {
        var merged: [DeviceBattery] = []
        for source in sources {
            for device in source {
                let index = merged.firstIndex { $0.id == device.id }
                    ?? merged.firstIndex { $0.name.caseInsensitiveCompare(device.name) == .orderedSame }
                guard let i = index else {
                    merged.append(device)
                    continue
                }
                var m = merged[i]
                m.level = m.level ?? device.level
                m.left = m.left ?? device.left
                m.right = m.right ?? device.right
                m.caseLevel = m.caseLevel ?? device.caseLevel
                m.detail = m.detail ?? device.detail
                m.isCharging = m.isCharging || device.isCharging
                if m.kind == .other { m.kind = device.kind }
                merged[i] = m
            }
        }
        return merged.sorted { a, b in
            if (a.kind == .mac) != (b.kind == .mac) { return a.kind == .mac }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

public enum IslandMaterial: String, Equatable, Hashable, CaseIterable {
    case glass, black

    public var title: String {
        switch self {
        case .glass: return "Glass"
        case .black: return "Black"
        }
    }
}
