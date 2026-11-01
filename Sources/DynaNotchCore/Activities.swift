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
    case hud, power, bluetooth, focus, calendar, timer, notification, download, privacy, toggle, fileCopy, conversion, agent, call, vitals, wrap, voice
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
    /// Camera / microphone on or off; `app` records ("" when unknown — the camera never says).
    case sensor(SensorKind, active: Bool, app: String)
    case toggle(symbol: String, label: String, on: Bool)
    /// A Finder copy in progress (CONTRACTS §6.12); fraction 1 = finished.
    case fileCopy(name: String, fraction: Double, secondsLeft: Int?)
    /// Smart Copy conversion of the copied text (CONTRACTS §6.13); click copies `result`.
    case conversion(source: String, result: String, symbol: String)
    /// Claude Code asks for permission (CONTRACTS §6.14): Allow / Deny / Terminal in the notch.
    case agentRequest(id: String, project: String, tool: String, detail: String)
    /// What a Claude Code session is doing; `done` after its reply.
    case agentStatus(project: String, detail: String, done: Bool)
    /// Meeting Meter (CONTRACTS §6.16): a call in progress, its start and your talk share.
    case call(app: String, startedAt: Date, talkShare: Int?)
    /// Mac Vitals (CONTRACTS §6.18): heat, memory pressure, low disk, a runaway app; a click opens Activity Monitor.
    case vitals(title: String, detail: String, symbol: String)
    /// Daily Wrap (CONTRACTS §6.19): today's highlights; a click closes it.
    case wrap(lines: [WrapLine])
    /// Voice Notes (CONTRACTS §6.20): live words while listening (`result` nil), then what happened.
    case voice(text: String, result: String?)

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
        case .fileCopy: return .fileCopy
        case .conversion: return .conversion
        case .agentRequest, .agentStatus: return .agent
        case .call: return .call
        case .vitals: return .vitals
        case .wrap: return .wrap
        case .voice: return .voice
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
        case .fileCopy(_, let fraction, _): return fraction >= 1 ? 1.5 : 8.0
        case .conversion: return 4.0
        case .agentRequest: return 60
        case .agentStatus(_, _, let done): return done ? 2.5 : 6.0
        case .call: return 20
        case .vitals: return 8
        case .wrap: return 20
        case .voice(_, let result): return result == nil ? 35 : 2.5
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
        case .fileCopy: return 40
        case .conversion: return 45
        case .agentRequest: return 97
        case .agentStatus: return 35
        case .call: return 30
        case .vitals: return 92
        case .wrap: return 60
        case .voice: return 96
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
