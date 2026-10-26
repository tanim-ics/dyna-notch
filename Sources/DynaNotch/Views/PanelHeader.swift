import SwiftUI
import AppKit
import Combine
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
            // Only the first nine tabs have a ⌘-number; the rest get no shortcut at all.
            ForEach(Array(settings.enabledTabs.prefix(9).enumerated()), id: \.element) { index, tab in
                Button {
                    vm.select(tab)
                } label: {
                    Label(tab.title, systemImage: tab.symbolName)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            if settings.enabledTabs.count > 9 {
                Divider()
                ForEach(Array(settings.enabledTabs.dropFirst(9)), id: \.self) { tab in
                    Button {
                        vm.select(tab)
                    } label: {
                        Label(tab.title, systemImage: tab.symbolName)
                    }
                }
            }
        } label: {
            HeaderGlyph(symbol: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .uiTestID("tabMenu")
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
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var keepAwake: KeepAwakeService
    @EnvironmentObject var timer: TimerService
    @EnvironmentObject var audio: AudioDeviceService

    private static let awakeTint = Color(red: 1.0, green: 0.75, blue: 0.3)

    /// Settings → Tabs → Header Buttons (canonical order).
    private var buttons: [HeaderButtonID] {
        let chosen = Set(HeaderButtonID.parseList(settings.headerButtons))
        return HeaderButtonID.allCases.filter { chosen.contains($0) }
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(buttons, id: \.self) { button in
                control(button)
            }
        }
    }

    @ViewBuilder
    private func control(_ button: HeaderButtonID) -> some View {
        switch button {
        case .battery:
            BatteryPill(isOpen: vm.headerCard == .battery) {
                vm.toggleHeaderCard(.battery)
            }
            .fixedSize()
            .layoutPriority(1)
            .uiTestID("batteryPill")
            .hoverRegion("hover.battery")
        case .timer:
            HeaderButton(symbol: "timer", isOn: timer.state != nil, tint: .orange,
                         help: timer.state != nil ? "Timer running" : "Timer") {
                vm.select(.timer)
            }
        case .output:
            SoundButton()
        case .keepAwake:
            KeepAwakeMenu(tint: HeaderControls.awakeTint)
        case .mic:
            HeaderButton(symbol: audio.isMicMuted ? "mic.slash.fill" : "mic.fill", isOn: audio.isMicMuted,
                         tint: IslandColors.low,
                         help: audio.isMicMuted ? "Unmute microphone" : "Mute microphone") {
                audio.toggleMicMute()
            }
        case .screenshot:
            HeaderButton(symbol: "camera.viewfinder", isOn: false, tint: .white, help: "Capture screenshot") {
                vm.collapse()
                QuickActions.captureScreenshot()
            }
        case .colorPicker:
            HeaderButton(symbol: "eyedropper", isOn: false, tint: .white, help: "Pick a color") {
                vm.collapse()
                QuickActions.pickColor()
            }
        case .actions:
            ActionsMenu()
        case .pin:
            HeaderButton(symbol: vm.isPinned ? "pin.fill" : "pin", isOn: vm.isPinned, tint: .white,
                         help: vm.isPinned ? "Unpin panel" : "Pin panel open") {
                vm.togglePin()
            }
        case .lock:
            HeaderButton(symbol: "lock.fill", isOn: false, tint: .white, help: "Lock screen") {
                ScreenLock.lock()
            }
        case .stopwatch:
            let running = timer.state?.mode == .stopwatch
            HeaderButton(symbol: "stopwatch", isOn: running, tint: PanelStyle.stopwatch,
                         help: running ? "Reset stopwatch" : "Start stopwatch") {
                if running { timer.reset() } else { timer.startStopwatch() }
            }
            .uiTestID("header.stopwatch")
        case .pomodoro:
            let active = timer.state?.mode == .pomodoro
            HeaderButton(symbol: "leaf.fill", isOn: active, tint: PanelStyle.breakTime,
                         help: active ? "Show Pomodoro" : "Start Pomodoro") {
                if !active {
                    timer.applyConfig(settings.pomodoroConfig)
                    timer.startPomodoro()
                }
                vm.select(.timer)
            }
            .uiTestID("header.pomodoro")
        case .volume:
            // Volume and Sound Output share one sound card; show the button once.
            if !buttons.contains(.output) { SoundButton() }
        case .scanQR:
            ScanQRButton()
        case .ports:
            PortsMenu()
        case .systemStats:
            SystemStatsMenu()
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

/// "⋯" quick actions (Notchy's actions menu).
struct ActionsMenu: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var timer: TimerService
    @EnvironmentObject var audio: AudioDeviceService
    @EnvironmentObject var settings: AppSettings
    @ObservedObject private var recorder = ScreenRecorder.shared

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
            if recorder.isRecording {
                Button("Stop Recording") { recorder.stop() }
            } else {
                Button("Record Screen") {
                    vm.collapse()
                    QuickActions.recordScreen()
                }
                Button("Record Area") {
                    vm.collapse()
                    QuickActions.recordArea()
                }
            }
            Divider()
            Button(audio.isMicMuted ? "Unmute Microphone" : "Mute Microphone") { audio.toggleMicMute() }
            Divider()
            Button("Settings…") { vm.openSettings() }
        } label: {
            if recorder.isRecording {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            } else {
                HeaderGlyph(symbol: "ellipsis.circle")
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .uiTestID("actionsMenu")
        .help("Actions")
    }
}

/// Scan QR Code: select an area; the decoded text is copied. A link turns the button into "Open link" (20 s).
struct ScanQRButton: View {
    @EnvironmentObject var vm: IslandViewModel
    @ObservedObject private var scanner = QRScanner.shared

    var body: some View {
        if scanner.pendingURL != nil {
            HeaderButton(symbol: "safari.fill", isOn: true, tint: PanelStyle.today,
                         help: "Open \(scanner.pendingURL?.absoluteString ?? "link")") {
                scanner.openPending()
                vm.collapse()
            }
            .uiTestID("header.qrOpen")
        } else {
            HeaderButton(symbol: "qrcode.viewfinder", isOn: scanner.isScanning, tint: .white, help: "Scan QR code") {
                vm.collapse()
                scanner.scan { title, body, symbol in
                    vm.postNotification(title: title, body: body, symbol: symbol)
                }
            }
            .uiTestID("header.scanQR")
        }
    }
}

/// Ports: listening TCP ports; "Stop" sits in a submenu with a confirm item.
struct PortsMenu: View {
    @ObservedObject private var service = PortsService.shared

    var body: some View {
        Menu {
            if service.ports.isEmpty {
                Text("No listening ports")
            } else {
                ForEach(service.ports) { port in
                    Menu("\(port.port) · \(port.command)") {
                        Text("PID \(port.pid) · \(port.address)")
                        if let url = URL(string: "http://localhost:\(port.port)") {
                            Button("Open localhost:\(port.port)") { NSWorkspace.shared.open(url) }
                        }
                        Divider()
                        Menu("Stop \(port.command)…") {
                            Button("Confirm: Stop PID \(port.pid)") { service.stop(port) }
                        }
                    }
                }
            }
            Divider()
            Button("Refresh") { service.refresh() }
        } label: {
            HeaderGlyph(symbol: "point.3.connected.trianglepath.dotted")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .uiTestID("portsMenu")
        .help("Listening ports")
        .onAppear { service.acquire() }
        .onDisappear { service.release() }
    }
}

/// System Stats: CPU, memory, disk, Mac battery temperature.
struct SystemStatsMenu: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var system: SystemMonitorService
    @EnvironmentObject var devices: DeviceBatteryService

    var body: some View {
        Menu {
            Text("CPU \(Int((system.cpu * 100).rounded())) %")
            if system.memoryTotal > 0 {
                Text("Memory \(Format.bytes(Double(system.memoryUsed))) of \(Format.bytes(Double(system.memoryTotal)))")
            }
            if system.diskTotal > 0 {
                Text("Disk \(Format.bytes(Double(system.diskFree))) free")
            }
            if let detail = devices.devices.first(where: { $0.kind == .mac })?.detail {
                Text("Battery \(detail)")
            }
            Text("Network ↓ \(Format.rate(system.netIn)) ↑ \(Format.rate(system.netOut))")
            Divider()
            Button("Open System Tab") { vm.select(.system) }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(Int((system.cpu * 100).rounded()))%")
                    .font(.system(size: 9.5, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.white.opacity(0.75))
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .uiTestID("systemStatsMenu")
        .help("System stats")
        .onAppear { SystemSampling.acquire("headerStats") }
        .onDisappear { SystemSampling.release("headerStats") }
    }
}

/// Keep Awake (cup) — click opens a menu of durations; the tooltip shows the time left.
struct KeepAwakeMenu: View {
    let tint: Color

    @EnvironmentObject var keepAwake: KeepAwakeService
    @EnvironmentObject var settings: AppSettings

    /// The next six whole hours (the first at least 30 minutes away).
    private var untilHours: [Date] {
        let cal = Calendar.current
        let now = Date()
        guard let nextHour = cal.nextDate(after: now.addingTimeInterval(1800), matching: DateComponents(minute: 0, second: 0),
                                          matchingPolicy: .nextTime) else { return [] }
        return (0..<6).compactMap { cal.date(byAdding: .hour, value: $0, to: nextHour) }
    }

    static func hourText(_ date: Date, format: TimeFormat) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(format.template)
        return formatter.string(from: date)
    }

    private static let durations: [(String, TimeInterval)] = [
        ("15 Minutes", 900), ("30 Minutes", 1800), ("1 Hour", 3600), ("2 Hours", 7200), ("4 Hours", 14_400),
    ]

    var body: some View {
        // Re-render every 30 s so the tooltip's "time left" stays current.
        TimelineView(.periodic(from: Date(), by: 30)) { _ in
            menu
        }
    }

    private var menu: some View {
        Menu {
            ForEach(KeepAwakeMenu.durations, id: \.0) { item in
                Button(item.0) { keepAwake.keepAwake(for: item.1) }
            }
            Menu("Until…") {
                ForEach(untilHours, id: \.self) { date in
                    Button("Until \(KeepAwakeMenu.hourText(date, format: settings.timeFormat))") {
                        keepAwake.keepAwake(until: date)
                    }
                }
            }
            Button("Until Stopped") { keepAwake.keepAwake(for: nil) }
            if keepAwake.isOn {
                Divider()
                Button("Turn Off") { keepAwake.set(false) }
            }
        } label: {
            Image(systemName: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(keepAwake.isOn ? tint : Color.white.opacity(0.75))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(keepAwake.isOn ? 0.16 : 0)))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)   // keeps the label's tint (borderlessButton renders it as a template image)
        .menuIndicator(.hidden)
        .fixedSize()
        .uiTestID("keepAwakeMenu")
        .help(helpText)
    }

    private var helpText: String {
        guard keepAwake.isOn else { return "Keep Awake: Off" }
        if let left = keepAwake.remainingText() { return "Keep Awake: \(left)" }
        return "Keep Awake: On until stopped"
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

// MARK: - Sound

/// SF Symbol for a volume reading.
enum VolumeGlyph {
    static func name(_ reading: LevelReading?) -> String {
        guard let r = reading else { return "speaker.wave.2.fill" }
        if r.muted || r.level <= 0.001 { return "speaker.slash.fill" }
        if r.level < 0.34 { return "speaker.wave.1.fill" }
        if r.level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// Speaker button: hover or click opens the sound card (volume + output device). The glyph follows the volume.
struct SoundButton: View {
    @EnvironmentObject var vm: IslandViewModel
    @State private var reading: LevelReading?

    private var isOpen: Bool { vm.headerCard == .sound }

    var body: some View {
        Button {
            vm.toggleHeaderCard(.sound)
        } label: {
            Image(systemName: VolumeGlyph.name(reading))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(isOpen ? 1 : 0.75))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(isOpen ? 0.16 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(reading.map { "Sound · \(Format.percent($0.level))\($0.muted ? " · muted" : "")" } ?? "Sound")
        .uiTestID("soundButton")
        .hoverRegion("hover.sound")
        .onAppear { reading = VolumeService.shared.read() }
        .onReceive(VolumeService.shared.changes.receive(on: DispatchQueue.main)) { reading = $0 }
    }
}

/// Dropdown card: live volume slider with mute, then the output devices (current one ticked).
struct SoundCard: View {
    @EnvironmentObject var audio: AudioDeviceService
    @State private var reading: LevelReading?

    private var level: Double { reading?.level ?? 0 }
    private var muted: Bool { reading?.muted ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: toggleMute) {
                    Image(systemName: VolumeGlyph.name(reading))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(muted ? 0.5 : 0.9))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .help(muted ? "Unmute" : "Mute")
                .uiTestID("sound.mute")
                VolumeSlider(value: muted ? 0 : level, onChange: setLevel)
                    .frame(height: 22)
                    .uiTestID("sound.slider")
                Text(muted ? "Muted" : Format.percent(level))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 44, alignment: .trailing)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5)
            Text("Output")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
            if audio.outputs.isEmpty {
                Text("No output devices")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            ForEach(Array(audio.outputs.enumerated()), id: \.element.id) { index, device in
                OutputRow(device: device, isCurrent: device.id == audio.currentOutputID) {
                    audio.select(device)
                    // The new device has its own volume.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { reading = VolumeService.shared.read() }
                }
                .uiTestID("sound.output.\(index)")
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.96))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        )
        .onAppear { reading = VolumeService.shared.read() }
        .onReceive(VolumeService.shared.changes.receive(on: DispatchQueue.main)) { reading = $0 }
    }

    private func toggleMute() {
        VolumeService.shared.setMuted(!muted)
        reading = VolumeService.shared.read()
    }

    private func setLevel(_ value: Double) {
        VolumeService.shared.setLevel(value)
        if muted && value > 0 { VolumeService.shared.setMuted(false) }
        reading = LevelReading(level: value, muted: false)
    }
}

/// Capsule slider that works in the non-activating panel (drag or click anywhere on the track).
struct VolumeSlider: View {
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = CGFloat(min(1, max(0, value)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15)).frame(height: 5)
                Capsule().fill(Color.white).frame(width: width * fraction, height: 5)
                Circle()
                    .fill(Color.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .offset(x: width * fraction - 6.5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(Double(min(1, max(0, drag.location.x / width))))
            })
        }
    }
}

struct OutputRow: View {
    let device: AudioDevice
    let isCurrent: Bool
    let action: () -> Void

    private var symbol: String {
        let n = device.name.lowercased()
        if n.contains("airpods") { return "airpods.pro" }
        if n.contains("headphone") || n.contains("headset") || n.contains("buds") { return "headphones" }
        if n.contains("speaker") { return "hifispeaker.fill" }
        return "display"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .frame(width: 18)
                Text(device.name)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}
