import SwiftUI
import AppKit
import DynaNotchCore

/// Compact geometry for one activity.
struct ActivityGeometry {
    let notch: NotchMetrics
    let side: CGFloat
    let radii: IslandRadii
}

/// Renders a live activity in the island.
struct ActivityView: View {
    let activity: LiveActivity
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings
    /// Observed so the unplug island picks up macOS's "time remaining" estimate as soon as it is known.
    @EnvironmentObject var battery: BatteryService

    private var geometry: ActivityGeometry {
        let p = IslandPresentation.activity(activity)
        return ActivityGeometry(notch: vm.notch,
                                side: IslandLayout.sideWidth(for: p, hudStyle: settings.hudStyle),
                                radii: IslandLayout.radii(for: p, hudStyle: settings.hudStyle))
    }

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch activity.kind {
        case let .hud(kind, level, muted):
            if settings.hudStyle == .expanded {
                HUDExpandedView(kind: kind, level: level, muted: muted, notch: vm.notch)
            } else {
                HUDCompactActivity(geometry: geometry, kind: kind, level: level, muted: muted)
            }
        case let .charging(level, isCharging, pluggedIn):
            ChargingActivity(geometry: geometry, level: level, isCharging: isCharging, pluggedIn: pluggedIn,
                             minutesLeft: pluggedIn || !settings.unplugActivity ? nil : vm.unplugMinutesLeft)
        case let .lowBattery(level):
            LowBatteryActivity(geometry: geometry, level: level)
        case let .bluetooth(name, device, battery, connected):
            BluetoothActivity(geometry: geometry, name: name, device: device, battery: battery, connected: connected)
        case let .focus(name, symbol, enabled):
            FocusActivity(geometry: geometry, name: name, symbol: symbol, enabled: enabled)
        case let .calendar(title, minutesUntil):
            CalendarActivity(geometry: geometry, title: title, minutesUntil: minutesUntil)
        case let .timerFinished(label):
            TimerFinishedActivity(geometry: geometry, label: label)
        case let .notification(title, body, symbol):
            NotificationActivity(geometry: geometry, title: title, message: body, symbol: symbol)
        case let .download(name, finished):
            DownloadActivity(geometry: geometry, name: name, finished: finished)
        case let .sensor(sensor, active, app):
            SensorActivity(geometry: geometry, sensor: sensor, active: active, app: app)
        case let .toggle(symbol, label, on):
            ToggleActivity(geometry: geometry, symbol: symbol, label: label, on: on)
        case let .fileCopy(name, fraction, secondsLeft):
            FileCopyActivity(geometry: geometry, name: name, fraction: fraction, secondsLeft: secondsLeft)
        case let .conversion(source, result, symbol):
            ConversionActivity(geometry: geometry, source: source, result: result, symbol: symbol)
        case let .agentRequest(_, project, tool, detail):
            AgentRequestActivity(geometry: geometry, project: project, tool: tool, detail: detail)
        case let .agentStatus(project, detail, done):
            AgentStatusActivity(geometry: geometry, project: project, detail: detail, done: done)
        case let .call(app, startedAt, talkShare):
            CallActivity(geometry: geometry, app: app, startedAt: startedAt, talkShare: talkShare)
        case let .vitals(title, detail, symbol):
            NotificationActivity(geometry: geometry, title: title, message: detail, symbol: symbol)
        case let .wrap(lines):
            WrapActivity(geometry: geometry, lines: lines)
        case let .voice(text, result):
            VoiceActivity(geometry: geometry, text: text, result: result)
        }
    }
}

// MARK: - HUD (compact)

struct HUDCompactActivity: View {
    let geometry: ActivityGeometry
    let kind: HUDKind
    let level: Double
    let muted: Bool

    private var shown: Double { HUDSymbol.displayLevel(level: level, muted: muted) }

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: HUDSymbol.name(kind: kind, level: level, muted: muted))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        } trailing: {
            trailing
        }
    }

    private var trailing: some View {
        HStack(spacing: 4) {
            LevelBar(level: shown, color: LevelTint.color(for: shown, kind: kind))
                .frame(width: 38, height: 4)
            Text(Format.percent(shown))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Power

struct ChargingActivity: View {
    let geometry: ActivityGeometry
    let level: Double
    let isCharging: Bool
    let pluggedIn: Bool
    /// Unplug island: battery time left ("4 h 5 min left"); nil while macOS is still estimating.
    var minutesLeft: Int? = nil

    private var tint: Color {
        if isCharging || pluggedIn { return IslandColors.charging }
        return level <= 0.2 ? IslandColors.low : Color.white
    }

    private var label: String {
        if isCharging { return "Charging" }
        if !pluggedIn, let minutes = minutesLeft, minutes > 0 { return ChargingActivity.timeLeft(minutes) }
        return pluggedIn ? "Plugged In" : "On Battery"
    }

    /// "4 h 5 min left", "2 h left", "35 min left".
    static func timeLeft(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min left" }
        return m == 0 ? "\(h) h left" : "\(h) h \(m) min left"
    }

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            leading
        } trailing: {
            trailing
        }
    }

    private var leading: some View {
        HStack(spacing: 3) {
            Image(systemName: isCharging || pluggedIn ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var trailing: some View {
        HStack(spacing: 4) {
            Text(Format.percent(level))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: BatteryGlyph.name(level: level, charging: isCharging))
                .font(.system(size: 13))
                .foregroundStyle(tint)
        }
    }
}

struct LowBatteryActivity: View {
    let geometry: ActivityGeometry
    let level: Double

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: BatteryGlyph.name(level: level, charging: false))
                .font(.system(size: 14))
                .foregroundStyle(IslandColors.low)
        } trailing: {
            Text(Format.percent(level))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(IslandColors.low)
                .lineLimit(1)
        }
    }
}

// MARK: - Bluetooth

struct BluetoothActivity: View {
    let geometry: ActivityGeometry
    let name: String
    let device: BluetoothDeviceKind
    let battery: Int?
    let connected: Bool

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: device.symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(connected ? Color.white : Color.white.opacity(0.5))
        } trailing: {
            trailing
        }
        .help(name)
        .accessibilityLabel(name)
    }

    @ViewBuilder
    private var trailing: some View {
        if let battery = battery, connected {
            BatteryRingLabel(percent: battery)
        } else {
            Text(connected ? "Connected" : "Disconnected")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(connected ? IslandColors.charging : Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct BatteryRingLabel: View {
    let percent: Int

    private var fraction: CGFloat { CGFloat(max(0, min(100, percent))) / 100 }
    private var tint: Color { percent <= 20 ? IslandColors.low : IslandColors.charging }

    var body: some View {
        HStack(spacing: 5) {
            Text("\(percent)%")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
        }
    }
}

// MARK: - Focus

struct FocusActivity: View {
    let geometry: ActivityGeometry
    let name: String
    let symbol: String
    let enabled: Bool

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: symbol.isEmpty ? "moon.fill" : symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(enabled ? IslandColors.focus : Color.white.opacity(0.5))
        } trailing: {
            Text(enabled ? "On" : "Off")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(enabled ? IslandColors.focus : Color.white.opacity(0.6))
        }
        .help(name)
        .accessibilityLabel(name)
    }
}

// MARK: - Calendar

struct CalendarActivity: View {
    let geometry: ActivityGeometry
    let title: String
    let minutesUntil: Int

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(IslandColors.calendar)
        } trailing: {
            Text(Format.relativeMinutes(minutesUntil))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .help(title)
        .accessibilityLabel(title)
    }
}

// MARK: - Timer finished

struct TimerFinishedActivity: View {
    let geometry: ActivityGeometry
    let label: String

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PanelStyle.timer)
                .symbolEffect(.pulse, isActive: true)
        } trailing: {
            Text(label.isEmpty ? "Time\u{2019}s up" : label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .help(label.isEmpty ? "Timer finished" : "\(label) finished")
        .accessibilityLabel(label.isEmpty ? "Timer finished" : "\(label) finished")
    }
}

// MARK: - Notification

struct NotificationActivity: View {
    let geometry: ActivityGeometry
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        VStack(spacing: 0) {
            CompactRow(notch: geometry.notch,
                       side: geometry.side,
                       radii: geometry.radii,
                       leadingAlignment: .leading,
                       trailingAlignment: .trailing) {
                Image(systemName: symbol.isEmpty ? "bell.fill" : symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.leading, 8)
            } trailing: {
                Text("now")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(IslandColors.secondary)
                    .padding(.trailing, 8)
            }
            textBlock
        }
    }

    private var textBlock: some View {
        VStack(spacing: 1) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(IslandColors.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
    }
}

// MARK: - Download

struct DownloadActivity: View {
    let geometry: ActivityGeometry
    let name: String
    let finished: Bool

    private static let progressTint = Color(red: 0.35, green: 0.62, blue: 1.0)

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: finished ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(finished ? IslandColors.charging : DownloadActivity.progressTint)
        } trailing: {
            Text(finished ? "Downloaded" : "Downloading")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .help(name)
        .accessibilityLabel(name)
    }
}

// MARK: - Privacy sensors

struct SensorActivity: View {
    let geometry: ActivityGeometry
    let sensor: SensorKind
    let active: Bool
    let app: String

    private var tint: Color {
        guard active else { return Color.white.opacity(0.5) }
        return sensor == .camera ? IslandColors.charging : Color.orange
    }

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: sensor.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        } trailing: {
            Text(active ? (app.isEmpty ? "In use" : app) : "Off")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? tint : Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .help(sensor == .camera ? "Camera" : "Microphone")
        .accessibilityLabel("\(sensor == .camera ? "Camera" : "Microphone") \(active ? "in use" : "off")\(app.isEmpty ? "" : " by \(app)")")
    }
}

// MARK: - Toggles (caps lock, mic mute, keep awake)

struct ToggleActivity: View {
    let geometry: ActivityGeometry
    let symbol: String
    let label: String
    let on: Bool

    /// Label of the lock screen's "Unlocked" popup, which says so instead of "On".
    static let unlockedLabel = "Unlocked"

    private var tint: Color { on ? IslandColors.charging : Color.white.opacity(0.6) }
    private var status: String { label == ToggleActivity.unlockedLabel ? label : (on ? "On" : "Off") }

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: symbol.isEmpty ? "switch.2" : symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        } trailing: {
            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - File copy (CONTRACTS §6.12)

/// The pill as a progress bar: green fills from the left; the text is white over black and dark over green, split
/// exactly at the fill edge.
struct FileCopyActivity: View {
    let geometry: ActivityGeometry
    let name: String
    let fraction: Double
    let secondsLeft: Int?

    private var done: Bool { fraction >= 1 }
    private var clamped: CGFloat { CGFloat(min(max(fraction, 0), 1)) }

    private var trailingText: String {
        if done { return "Done" }
        let percent = CopyFormat.percent(fraction)
        guard let left = secondsLeft else { return percent }
        return "\(percent) · \(CopyFormat.remaining(left))"
    }

    var body: some View {
        GeometryReader { proxy in
            let filled = proxy.size.width * clamped
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(IslandColors.charging)
                    .frame(width: filled)
                row(Color.white)
                    .mask(alignment: .trailing) { Rectangle().frame(width: max(0, proxy.size.width - filled)) }
                row(Color.black.opacity(0.82))
                    .mask(alignment: .leading) { Rectangle().frame(width: filled) }
            }
            .animation(.easeOut(duration: 0.35), value: fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(done ? "Copied \(name)" : "Copying \(name), \(trailingText)")
    }

    private func row(_ color: Color) -> some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii,
                   leadingAlignment: .leading, trailingAlignment: .trailing) {
            HStack(spacing: 5) {
                Image(systemName: done ? "checkmark.circle.fill" : "doc.on.doc.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 6)
        } trailing: {
            Text(trailingText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .padding(.trailing, 6)
        }
        .foregroundStyle(color)
    }
}

// MARK: - Smart Copy conversion (CONTRACTS §6.13)

/// "€42" on the left, "$45.30" on the right; clicking the island copies the result (the view model handles it).
struct ConversionActivity: View {
    let geometry: ActivityGeometry
    let source: String
    let result: String
    let symbol: String

    private var copied: Bool { result == SmartCopyService.copiedLabel }

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii,
                   leadingAlignment: .leading, trailingAlignment: .trailing) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(copied ? IslandColors.charging : Color.white.opacity(0.85))
                Text(source)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandColors.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 6)
        } trailing: {
            HStack(spacing: 4) {
                if !copied {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(IslandColors.secondary)
                }
                Text(result)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(copied ? IslandColors.charging : Color.white)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.trailing, 6)
        }
        .contentShape(Rectangle())
        .uiTestID("activity-conversion")
        .help(copied ? "Copied" : "Click to copy \(result)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copied ? "Copied" : "\(source) is \(result). Click to copy.")
    }
}

// MARK: - Agent Island (CONTRACTS §6.14)

enum AgentColors {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
}

/// Claude Code asks for permission: what it wants to run, and Deny / Terminal / Allow (equal thirds of the card).
/// The island's own tap answers by where the click lands (`AgentDecision.button(at:…)`).
struct AgentRequestActivity: View {
    let geometry: ActivityGeometry
    let project: String
    let tool: String
    let detail: String

    var body: some View {
        VStack(spacing: 0) {
            CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii,
                       leadingAlignment: .leading, trailingAlignment: .trailing) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AgentColors.claude)
                    Text(project)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.leading, 8)
            } trailing: {
                Text("wants \(tool)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(IslandColors.secondary)
                    .lineLimit(1)
                    .padding(.trailing, 8)
            }
            VStack(spacing: 8) {
                Text(detail)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.1)))
                    .help(detail)
                HStack(spacing: 8) {
                    button("Deny", .deny, color: IslandColors.low)
                    button("Terminal", .terminal, color: Color.white.opacity(0.18))
                    button("Allow", .allow, color: IslandColors.charging)
                }
            }
            .padding(.horizontal, geometry.radii.bottom)
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude Code in \(project) wants \(tool): \(detail)")
    }

    private func button(_ title: String, _ decision: AgentDecision, color: Color) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(decision == .allow ? Color.black.opacity(0.85) : Color.white)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(Capsule().fill(color))
            .accessibilityAddTraits(.isButton)
            .uiTestID("agent-\(decision.rawValue)")
    }
}

/// What a Claude Code session is doing ("Running npm test"), or "Done".
struct AgentStatusActivity: View {
    let geometry: ActivityGeometry
    let project: String
    let detail: String
    let done: Bool

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii,
                   leadingAlignment: .leading, trailingAlignment: .trailing) {
            HStack(spacing: 5) {
                Image(systemName: done ? "checkmark.circle.fill" : "sparkle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(done ? IslandColors.charging : AgentColors.claude)
                Text(project)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.leading, 6)
        } trailing: {
            Text(detail)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(done ? IslandColors.charging : IslandColors.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.trailing, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Claude Code, \(project): \(detail)")
    }
}

// MARK: - Meeting Meter (CONTRACTS §6.16)

/// A call in progress: the app on the left, a live timer (and your talk share) on the right.
struct CallActivity: View {
    let geometry: ActivityGeometry
    let app: String
    let startedAt: Date
    let talkShare: Int?

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii,
                   leadingAlignment: .leading, trailingAlignment: .trailing) {
            HStack(spacing: 5) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(IslandColors.charging)
                Text(app)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
        } trailing: {
            HStack(spacing: 4) {
                Text(startedAt, style: .timer)   // SwiftUI updates it; no timer of ours
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                if let share = talkShare {
                    Text("· you \(share)%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(IslandColors.secondary)
                }
            }
            .lineLimit(1)
            .padding(.trailing, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Call in \(app)")
    }
}

/// Small dots at the island's top right while the camera (green) or microphone (orange) is on.
struct SensorDots: View {
    @ObservedObject private var privacy = PrivacyMonitor.shared

    var body: some View {
        HStack(spacing: 3) {
            if privacy.inUse.contains(.camera) { dot(IslandColors.charging) }
            if privacy.inUse.contains(.microphone) { dot(Color.orange) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(privacy.inUse.isEmpty ? "" : "Camera or microphone in use")
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.6), radius: 2)
    }
}

// MARK: - Daily Wrap (CONTRACTS §6.19)

/// Today's highlights: "Today" + date on the notch row, then one line per fact.
struct WrapActivity: View {
    let geometry: ActivityGeometry
    let lines: [WrapLine]

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE d MMM")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii,
                       leadingAlignment: .leading, trailingAlignment: .trailing) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.yellow)
                    Text("Your Day")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                }
                .padding(.leading, 8)
            } trailing: {
                Text(Self.day.string(from: Date()))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(IslandColors.secondary)
                    .padding(.trailing, 8)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.self) { line in
                    HStack(spacing: 8) {
                        Image(systemName: line.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 16)
                        Text(line.text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(height: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, geometry.radii.bottom + 6)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your day: " + lines.map(\.text).joined(separator: ", "))
    }
}

// MARK: - Voice Notes (CONTRACTS §6.20)

/// Listening: a red mic and the words as they come; afterwards a green check and what happened.
struct VoiceActivity: View {
    let geometry: ActivityGeometry
    let text: String
    let result: String?

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii,
                   leadingAlignment: .leading, trailingAlignment: .trailing) {
            HStack(spacing: 6) {
                Image(systemName: result == nil ? "mic.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(result == nil ? IslandColors.low : IslandColors.charging)
                Text(result ?? "Listening…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
        } trailing: {
            Text(text.isEmpty ? "Speak now" : text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(IslandColors.secondary)
                .lineLimit(1)
                .truncationMode(.head)   // the newest words stay visible
                .padding(.trailing, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result ?? "Listening")
    }
}
