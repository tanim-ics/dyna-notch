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
        case let .sensor(sensor, active):
            SensorActivity(geometry: geometry, sensor: sensor, active: active)
        case let .toggle(symbol, label, on):
            ToggleActivity(geometry: geometry, symbol: symbol, label: label, on: on)
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
            Text(active ? "In use" : "Off")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active ? tint : Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .help(sensor == .camera ? "Camera" : "Microphone")
        .accessibilityLabel(sensor == .camera ? "Camera" : "Microphone")
    }
}

// MARK: - Toggles (caps lock, mic mute, keep awake)

struct ToggleActivity: View {
    let geometry: ActivityGeometry
    let symbol: String
    let label: String
    let on: Bool

    private var tint: Color { on ? IslandColors.charging : Color.white.opacity(0.6) }

    var body: some View {
        CompactRow(notch: geometry.notch, side: geometry.side, radii: geometry.radii) {
            Image(systemName: symbol.isEmpty ? "switch.2" : symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        } trailing: {
            Text(on ? "On" : "Off")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .help(label)
        .accessibilityLabel(label)
    }
}
