import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum HUDKind: String, Equatable, Hashable, CaseIterable {
    case volume, brightness
}

public enum BluetoothDeviceKind: String, Equatable, Hashable, CaseIterable {
    case airpods, airpodsPro, airpodsMax, headphones, speaker, keyboard, mouse, trackpad, gamepad, generic

    /// SF Symbol name for the device kind.
    public var symbolName: String {
        switch self {
        case .airpods: return "airpods"
        case .airpodsPro: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker.fill"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .gamepad: return "gamecontroller.fill"
        case .generic: return "dot.radiowaves.left.and.right"
        }
    }

    /// Classifies a Bluetooth device from its name and (already shifted) Class-of-Device major/minor values.
    public static func classify(name: String, majorClass: UInt32, minorClass: UInt32) -> BluetoothDeviceKind {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return .airpodsMax }
        if lower.contains("airpods pro") { return .airpodsPro }
        if lower.contains("airpods") { return .airpods }
        for token in ["beats", "headphone", "buds", "wh-", "bose"] where lower.contains(token) {
            return .headphones
        }

        switch majorClass {
        case 0x04: // Audio / video
            switch minorClass {
            case 0x05: return .speaker
            default: return .headphones // 0x01 headset, 0x02 hands-free, 0x06 headphones, others
            }
        case 0x05: // Peripheral
            let upper = minorClass & 0x30
            if upper == 0x10 { return .keyboard }
            if upper == 0x20 { return lower.contains("trackpad") ? .trackpad : .mouse }
            let lowerBits = minorClass & 0x0F
            if lowerBits == 0x02 || lowerBits == 0x01 { return .gamepad }
        default:
            break
        }

        if lower.contains("keyboard") { return .keyboard }
        if lower.contains("mouse") { return .mouse }
        if lower.contains("trackpad") { return .trackpad }
        if lower.contains("controller") { return .gamepad }
        return .generic
    }
}

public enum ActivityCategory: String, Equatable, Hashable {
    case hud, power, bluetooth, focus, calendar, timer, notification, download, privacy, toggle
}

public enum SensorKind: String, Equatable, Hashable, CaseIterable {
    case camera, microphone

    public var symbolName: String {
        switch self {
        case .camera: return "video.fill"
        case .microphone: return "mic.fill"
        }
    }
}

public enum ActivityKind: Equatable {
    case hud(HUDKind, level: Double, muted: Bool)
    case charging(level: Double, isCharging: Bool, pluggedIn: Bool)
    case lowBattery(level: Double)
    case bluetooth(name: String, device: BluetoothDeviceKind, battery: Int?, connected: Bool)
    case focus(name: String, symbol: String, enabled: Bool)
    case calendar(title: String, minutesUntil: Int)
    case timerFinished(label: String)
    case notification(title: String, body: String, symbol: String)
    case download(name: String, finished: Bool)
    case sensor(SensorKind, active: Bool)
    case toggle(symbol: String, label: String, on: Bool)

    /// charging & lowBattery → .power
    public var category: ActivityCategory {
        switch self {
        case .hud: return .hud
        case .charging, .lowBattery: return .power
        case .bluetooth: return .bluetooth
        case .focus: return .focus
        case .calendar: return .calendar
        case .timerFinished: return .timer
        case .notification: return .notification
        case .download: return .download
        case .sensor: return .privacy
        case .toggle: return .toggle
        }
    }

    public var defaultDuration: TimeInterval {
        switch self {
        case .hud: return 1.6
        case .charging: return 3.0
        case .lowBattery: return 4.0
        case .bluetooth: return 3.5
        case .focus: return 2.5
        case .calendar: return 6.0
        case .timerFinished: return 6.0
        case .notification: return 4.5
        case .download: return 3.5
        case .sensor: return 3.0
        case .toggle: return 1.5
        }
    }

    public var priority: Int {
        switch self {
        case .hud: return 100
        case .lowBattery: return 90
        case .charging: return 80
        case .bluetooth: return 70
        case .focus: return 60
        case .calendar: return 50
        case .timerFinished: return 95
        case .notification: return 85
        case .download: return 65
        case .sensor: return 88
        case .toggle: return 98
        }
    }
}

public struct LiveActivity: Equatable, Identifiable {
    public let id: UUID
    public var kind: ActivityKind
    public var postedAt: Date
    public var expiresAt: Date

    public init(id: UUID = UUID(), kind: ActivityKind, postedAt: Date, expiresAt: Date) {
        self.id = id
        self.kind = kind
        self.postedAt = postedAt
        self.expiresAt = expiresAt
    }
}
