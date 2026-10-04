import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage("expandOnHover")        private var expandOnHover        = true
    @AppStorage("showMusicWidget")      private var showMusicWidget      = true
    @AppStorage("showVolumeHUD")        private var showVolumeHUD        = true
    @AppStorage("showNotifications")    private var showNotifications    = true
    @AppStorage("autoCollapseDelay")    private var autoCollapseDelay    = 2.0
    @AppStorage("displayMode")          private var displayMode          = "focused"
    @AppStorage("idleOpacity")          private var idleOpacity          = 0.5
    @AppStorage("clickThroughExternal") private var clickThroughExternal = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @ObservedObject private var musicVM = MusicViewModel.shared

    private var musicSubtitle: String {
        if musicVM.installedMusicApps.isEmpty {
            return "Auto-detects Spotify, Apple Music, YouTube Music"
        } else {
            return "Detected on your Mac: " + musicVM.installedMusicApps.joined(separator: ", ")
        }
    }

    private var displaySubtitle: String {
        switch displayMode {
        case "focused": return "Follows mouse cursor to active monitor"
        case "notch":   return "Pinned to built-in MacBook screen"
        default:        return "Pinned to primary display"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "capsule.fill")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("DynaNotch")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Dynamic Island for macOS")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("v1.0")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                .padding(20)

                Divider()

                // General / System
                settingGroup("General") {
                    settingRow(
                        icon: "power", color: .indigo,
                        title: "Launch at Login",
                        subtitle: "Start DynaNotch automatically when you log in"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                launchAtLogin = newValue
                                do {
                                    if newValue {
                                        try SMAppService.mainApp.register()
                                    } else {
                                        try SMAppService.mainApp.unregister()
                                    }
                                } catch {
                                    print("Failed to change launch at login: \(error)")
                                }
                            }
                        )).labelsHidden()
                    }

                    Divider().padding(.leading, 44)

                    settingRow(
                        icon: "display", color: .purple,
                        title: "Display Mode",
                        subtitle: displaySubtitle
                    ) {
                        Picker("", selection: $displayMode) {
                            Text("Follow Focus").tag("focused")
                            Text("Notch Screen").tag("notch")
                            Text("Main Screen").tag("main")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                }

                // Appearance & Interaction
                settingGroup("Appearance & Interaction") {
                    settingRow(
                        icon: "circle.lefthalf.filled", color: .cyan,
                        title: "Idle Opacity",
                        subtitle: String(format: "Dim notch to %.0f%% when mouse is away", idleOpacity * 100)
                    ) {
                        HStack(spacing: 8) {
                            Slider(value: $idleOpacity, in: 0.1...1.0, step: 0.05)
                                .frame(width: 90)
                            Text(String(format: "%.0f%%", idleOpacity * 100))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }

                    Divider().padding(.leading, 44)

                    settingRow(
                        icon: "cursorarrow.motionlines", color: .blue,
                        title: "Expand on Hover",
                        subtitle: "Notch expands when you hover over it"
                    ) { Toggle("", isOn: $expandOnHover).labelsHidden() }

                    Divider().padding(.leading, 44)

                    settingRow(
                        icon: "timer", color: .orange,
                        title: "Auto-collapse Delay",
                        subtitle: String(format: "%.1f seconds", autoCollapseDelay)
                    ) {
                        Slider(value: $autoCollapseDelay, in: 0.5...5.0, step: 0.5)
                            .frame(width: 110)
                    }

                    Divider().padding(.leading, 44)

                    settingRow(
                        icon: "hand.draw.fill", color: .teal,
                        title: "Gestures",
                        subtitle: "Swipe ◄ / ► to skip tracks, ▲ or double-tap to tuck"
                    ) {
                        Text("Active")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Divider().padding(.leading, 44)

                    settingRow(
                        icon: "cursorarrow.click.2", color: .mint,
                        title: "External Display Click-Through",
                        subtitle: "Pass clicks through collapsed notch to tabs underneath"
                    ) { Toggle("", isOn: $clickThroughExternal).labelsHidden() }

                    Divider().padding(.leading, 16)

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "command")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Browser Tab Pass-Through Tips")
                                .font(.system(size: 11, weight: .semibold))
                            Text("• Hold ⌘ Command or ⌥ Option to click any tab directly behind the notch.\n• Swipe ▲ or double-tap the notch to tuck it to the screen edge.")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                settingGroup("Features") {
                    settingRow(
                        icon: "music.note", color: .pink,
                        title: "Music Widget",
                        subtitle: musicSubtitle
                    ) { Toggle("", isOn: $showMusicWidget).labelsHidden() }

                    Divider().padding(.leading, 44)

                    settingRow(
                        icon: "speaker.wave.2.fill", color: .green,
                        title: "Volume HUD",
                        subtitle: "Show volume level when you adjust volume"
                    ) { Toggle("", isOn: $showVolumeHUD).labelsHidden() }

                    Divider().padding(.leading, 44)

                    settingRow(
                        icon: "bell.fill", color: .yellow,
                        title: "Notifications",
                        subtitle: "Show system notifications in the notch"
                    ) { Toggle("", isOn: $showNotifications).labelsHidden() }
                }

                settingGroup("Test Previews") {
                    HStack(spacing: 8) {
                        Button("Music") {
                            NotificationCenter.default.post(name: .testMusicPreview, object: nil)
                        }
                        .buttonStyle(.bordered)

                        Button("Volume") {
                            NotificationCenter.default.post(name: .testVolumeHUD, object: nil)
                        }
                        .buttonStyle(.bordered)

                        Button("Battery") {
                            NotificationCenter.default.post(name: .testBatteryHUD, object: nil)
                        }
                        .buttonStyle(.bordered)

                        Button("Notification") {
                            NotificationCenter.default.post(name: .testNotification, object: nil)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                settingGroup("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)

                    Divider().padding(.leading, 16)

                    HStack {
                        Label("Author", systemImage: "person.fill")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Tanim Rayhan")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }

                Spacer(minLength: 20)
            }
        }
        .frame(width: 440, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: – Helpers
    @ViewBuilder
    private func settingGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 6)

            VStack(spacing: 0) { content() }
                .background(Color(NSColor.controlBackgroundColor),
                             in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func settingRow<Control: View>(
        icon: String, color: Color,
        title: String, subtitle: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
