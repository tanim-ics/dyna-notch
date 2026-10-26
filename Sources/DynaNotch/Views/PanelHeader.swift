import SwiftUI
import AppKit
import DynaNotchCore

/// Notchy-style header inside the notch row: current-tab pill + "⋯" tab menu on the left,
/// battery pill and quick controls on the right. The middle stays clear of the physical notch.
struct PanelHeader: View {
    @Binding var showsBatteries: Bool

    @EnvironmentObject var vm: IslandViewModel

    private var horizontalPadding: CGFloat { vm.radii.top + 10 }
    private var gap: CGFloat { vm.notch.hasPhysicalNotch ? vm.notch.width + 16 : 12 }
    private var sideWidth: CGFloat { max(0, (vm.islandSize.width - 2 * horizontalPadding - gap) / 2) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                TabPill()
                TabMenu()
            }
            .frame(width: sideWidth, alignment: .leading)
            Color.clear.frame(width: gap)
            HeaderControls(showsBatteries: $showsBatteries)
                .frame(width: sideWidth, alignment: .trailing)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: vm.notch.height)
        .background(TabShortcuts())
    }
}

// MARK: - Left: tabs

/// Glassy capsule showing the current tab.
struct TabPill: View {
    @EnvironmentObject var vm: IslandViewModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.visibleTab.symbolName)
                .font(.system(size: 11, weight: .semibold))
            Text(vm.visibleTab.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 11)
        .frame(height: 24)
        .background(HeaderCapsule())
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: vm.visibleTab)
    }
}

/// "⋯" menu listing every enabled tab with its ⌘-number shortcut.
struct TabMenu: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Menu {
            ForEach(Array(settings.enabledTabs.enumerated()), id: \.element) { index, tab in
                Button {
                    vm.select(tab)
                } label: {
                    Label(tab.title, systemImage: tab.symbolName)
                }
                .keyboardShortcut(index < 9 ? KeyEquivalent(Character("\(index + 1)")) : KeyEquivalent(" "),
                                  modifiers: index < 9 ? .command : [.command, .option, .control, .shift])
            }
        } label: {
            HeaderGlyph(symbol: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("All tabs")
    }
}

/// Invisible buttons so ⌘1…⌘9 switch tabs while the panel has keyboard focus.
struct TabShortcuts: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        ZStack {
            ForEach(Array(settings.enabledTabs.prefix(9).enumerated()), id: \.element) { index, tab in
                Button("") { vm.select(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

// MARK: - Right: controls

struct HeaderControls: View {
    @Binding var showsBatteries: Bool

    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var keepAwake: KeepAwakeService

    private static let awakeTint = Color(red: 1.0, green: 0.75, blue: 0.3)

    var body: some View {
        HStack(spacing: 3) {
            BatteryPill(isOpen: showsBatteries) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showsBatteries.toggle() }
            }
            .fixedSize()
            .layoutPriority(1)
            OutputMenu()
            HeaderButton(symbol: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                         isOn: keepAwake.isOn, tint: HeaderControls.awakeTint,
                         help: keepAwake.isOn ? "Keep Awake: On" : "Keep Awake: Off") {
                keepAwake.toggle()
            }
            ActionsMenu()
            HeaderButton(symbol: vm.isPinned ? "pin.fill" : "pin", isOn: vm.isPinned, tint: .white,
                         help: vm.isPinned ? "Unpin panel" : "Pin panel open") {
                vm.togglePin()
            }
            HeaderButton(symbol: "lock.fill", isOn: false, tint: .white, help: "Lock screen") {
                ScreenLock.lock()
            }
        }
    }
}

/// "▭ 80 %" capsule; opens the device-battery card.
struct BatteryPill: View {
    let isOpen: Bool
    let action: () -> Void

    @EnvironmentObject var battery: BatteryService
    @EnvironmentObject var devices: DeviceBatteryService

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(HeaderCapsule(highlighted: isOpen))
        }
        .buttonStyle(PressableButtonStyle())
        .help("Batteries")
    }

    private var glyph: String {
        if let info = battery.info { return BatteryGlyph.name(level: info.level, charging: info.isCharging) }
        return devices.devices.isEmpty ? "battery.100percent" : "bolt.horizontal.circle"
    }

    private var tint: Color {
        guard let info = battery.info else { return .white }
        if info.isCharging { return IslandColors.charging }
        return info.level <= 0.2 ? IslandColors.low : .white
    }

    private var label: String {
        if let info = battery.info { return Format.percent(info.level) }
        return "\(devices.devices.count)"
    }
}

/// Output-device picker behind a speaker glyph.
struct OutputMenu: View {
    @EnvironmentObject var audio: AudioDeviceService

    var body: some View {
        Menu {
            if audio.outputs.isEmpty {
                Text("No output devices")
            }
            ForEach(audio.outputs) { device in
                Button {
                    audio.select(device)
                } label: {
                    if device.id == audio.currentOutputID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            HeaderGlyph(symbol: "speaker.wave.2.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sound output")
    }
}

/// "⋯" quick actions (Notchy's actions menu).
struct ActionsMenu: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var timer: TimerService
    @EnvironmentObject var audio: AudioDeviceService
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Menu {
            if timer.state?.mode == .stopwatch {
                Button("Reset Stopwatch") { timer.reset() }
            } else {
                Button("Start Stopwatch") { timer.startStopwatch() }
            }
            Button("Start Pomodoro") {
                timer.applyConfig(settings.pomodoroConfig)
                timer.startPomodoro()
            }
            if timer.state != nil && timer.state?.mode != .stopwatch {
                Button("Reset Timer") { timer.reset() }
            }
            Divider()
            Button("Capture Screenshot") {
                vm.collapse()
                QuickActions.captureScreenshot()
            }
            Button("Pick a Color") {
                vm.collapse()
                QuickActions.pickColor()
            }
            Divider()
            Button(audio.isMicMuted ? "Unmute Microphone" : "Mute Microphone") { audio.toggleMicMute() }
            Divider()
            Button("Settings…") { vm.openSettings() }
        } label: {
            HeaderGlyph(symbol: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Actions")
    }
}

// MARK: - Building blocks

/// Translucent capsule used behind header pills (glass on glass).
struct HeaderCapsule: View {
    var highlighted = false

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(highlighted ? 0.22 : 0.12))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}

struct HeaderGlyph: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.75))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
    }
}

struct HeaderButton: View {
    let symbol: String
    let isOn: Bool
    let tint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? tint : Color.white.opacity(0.75))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(isOn ? 0.16 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(help)
    }
}

// MARK: - Device batteries

/// Dropdown card listing the Mac and connected Bluetooth devices with battery bars.
struct DeviceBatteryCard: View {
    @EnvironmentObject var service: DeviceBatteryService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if service.devices.isEmpty {
                Text("No batteries found")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            ForEach(service.devices) { device in
                DeviceBatteryRow(device: device)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
        .onAppear { service.refresh() }
    }
}

struct DeviceBatteryRow: View {
    let device: DeviceBattery

    private var level: Int { device.displayLevel ?? 0 }
    private var tint: Color { level <= 20 ? IslandColors.low : IslandColors.charging }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: device.isCharging ? "bolt.fill" : device.kind.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(device.isCharging ? IslandColors.charging : Color.white.opacity(0.8))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                if let detail = subtitle {
                    Text(detail)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if device.displayLevel != nil {
                PanelBarLite(value: Double(level) / 100, tint: tint)
                    .frame(width: 38, height: 4)
                Text("\(level) %")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    /// Mac: health line. AirPods: "L 86 · R 84 · Case 22".
    private var subtitle: String? {
        if let detail = device.detail { return detail }
        var parts: [String] = []
        if let l = device.left { parts.append("L \(l)") }
        if let r = device.right { parts.append("R \(r)") }
        if let c = device.caseLevel { parts.append("Case \(c)") }
        return parts.count > 1 ? parts.joined(separator: " · ") : nil
    }
}

/// Slim capsule progress bar.
struct PanelBarLite: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(tint).frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
            }
        }
    }
}
