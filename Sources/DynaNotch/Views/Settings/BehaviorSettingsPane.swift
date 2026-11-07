import AppKit
import SwiftUI
import DynaNotchCore

struct BehaviorSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var vm: IslandViewModel

    /// Displays plugged in now (refreshed when displays change).
    @State private var displays: [ConnectedDisplay] = ConnectedDisplay.current()

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        SettingsPageView(page: .behavior) {
            openingSection
            closingSection
            interactionSection
            shortcutsSection
            tabShortcutsSection
            visibilitySection
            previewSection
            RestoreDefaultsSection(keys: [
                SettingsKey.expandOnHover, SettingsKey.hoverDelay, SettingsKey.collapseDelay,
                SettingsKey.clickToExpand, SettingsKey.gesturesEnabled, SettingsKey.defaultTab,
                SettingsKey.rememberLastTab, SettingsKey.openOnCurrentActivity, SettingsKey.idleTimeout,
                SettingsKey.invisibleUntilHover, SettingsKey.displayMode, SettingsKey.hiddenDisplays, SettingsKey.hideInFullscreen,
                SettingsKey.autoCollapse, SettingsKey.fullscreenScope, SettingsKey.hideWhileMirroring,
                SettingsKey.screenSharingPrivacy, SettingsKey.hotkeysEnabled, SettingsKey.hotkeyBindings,
            ])
        }
    }

    private var openingSection: some View {
        Section("Opening") {
            SettingToggle(symbol: "cursorarrow.rays", color: .blue, title: "Expand on Hover",
                          detail: "Open the panel when you rest the pointer on the island.",
                          isOn: $settings.expandOnHover)
            SliderRow(symbol: "hourglass", color: .blue, title: "Hover Delay",
                      detail: "A short wait, so brushing past doesn't open it.",
                      value: $settings.hoverDelay, range: 0...1, step: 0.05, format: SettingsFormat.seconds)
                .disabled(!settings.expandOnHover)
            SettingToggle(symbol: "cursorarrow.click", color: .indigo, title: "Click to Expand",
                          detail: "Click the island to open or close the panel.",
                          isOn: $settings.clickToExpand)
            SettingRow(symbol: "rectangle.stack.fill", color: .purple, title: "Default Tab",
                       detail: "The tab you see when the panel opens.") {
                Picker("Default tab", selection: $settings.defaultTab) {
                    Text("Previous Tab").tag("previous")
                    Divider()
                    ForEach(PanelTab.allCases, id: \.self) { tab in
                        Label(tab.title, systemImage: tab.symbolName).tag(tab.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingToggle(symbol: "clock.arrow.circlepath", color: .purple, title: "Remember the Last Tab",
                          detail: "Open on the tab you used last. Works with Default Tab set to Previous Tab.",
                          isOn: $settings.rememberLastTab)
                .disabled(settings.defaultTab != "previous")
            SettingToggle(symbol: "waveform", color: .pink, title: "Open on Current Activity",
                          detail: "Open on Now Playing or Timer while music or a timer is running.",
                          isOn: $settings.openOnCurrentActivity)
        }
    }

    private var closingSection: some View {
        Section("Closing") {
            SettingToggle(symbol: "rectangle.compress.vertical", color: .teal, title: "Auto Collapse",
                          detail: "Close the panel when the pointer leaves. Off: click outside or press Esc.",
                          isOn: $settings.autoCollapse, testID: "setting-autoCollapse")
            SliderRow(symbol: "arrow.down.right.and.arrow.up.left", color: .teal, title: "Collapse Delay",
                      detail: "How long to wait before closing. Needs Auto Collapse.",
                      value: $settings.collapseDelay, range: 0...2, step: 0.05, format: SettingsFormat.seconds,
                      testID: "setting-collapseDelay")
                .disabled(!settings.autoCollapse)
            SettingRow(symbol: "moon.zzz.fill", color: .gray, title: "Idle Timeout",
                       detail: "Close the panel after this long without use.") {
                Picker("Idle timeout", selection: $settings.idleTimeout) {
                    Text("Never").tag(0.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                    if ![0.0, 10, 30, 60, 120, 300, 600].contains(settings.idleTimeout) {
                        Text("\(Int(settings.idleTimeout)) seconds").tag(settings.idleTimeout)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var interactionSection: some View {
        Section("Gestures") {
            SettingToggle(symbol: "hand.draw.fill", color: .orange, title: "Swipe Gestures",
                          detail: "Swipe left or right to skip tracks, up to close.",
                          isOn: $settings.gesturesEnabled)
        }
    }

    private var shortcutsSection: some View {
        Section {
            SettingToggle(symbol: "keyboard.fill", color: .gray, title: "Global Shortcuts",
                          detail: "They work in every app. Turn off to free up all the keys.",
                          isOn: $settings.hotkeysEnabled, testID: "setting-hotkeysEnabled")
            ForEach(HotKeyAction.allCases, id: \.self) { action in
                ShortcutRow(key: action.rawValue, symbol: action.settingsSymbol, color: action.settingsColor,
                            title: action.title, detail: action.settingsDetail)
            }
            .disabled(!settings.hotkeysEnabled)
        } header: {
            Text("Keyboard Shortcuts")
        } footer: {
            SettingsFooter("Click one and press new keys. Esc cancels, Delete removes, ⟲ resets.")
        }
    }

    private var tabShortcutsSection: some View {
        Section {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                ShortcutRow(key: HotKeyMap.tabKey(tab), symbol: tab.symbolName, color: .purple,
                            title: tab.title, detail: "Open or close the panel on \(tab.title).")
            }
            .disabled(!settings.hotkeysEnabled)
        } header: {
            Text("Tab Shortcuts")
        } footer: {
            SettingsFooter("Record a shortcut to give a tab one.")
        }
    }

    private var visibilitySection: some View {
        Section("Visibility") {
            SettingRow(symbol: "display.2", color: .blue, title: "Show On",
                       detail: displayModeDetail) {
                Picker("Show island on", selection: $settings.displayMode) {
                    ForEach(DisplayMode.allCases, id: \.self) { mode in
                        Text(shortTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .uiTestID("setting-displayMode")
            }
            ForEach(displays) { display in
                SettingToggle(symbol: display.isBuiltIn ? "laptopcomputer" : "display", color: .blue,
                              title: display.name,
                              detail: displayDetail(display),
                              isOn: displayBinding(display), testID: "setting-display-\(display.testKey)")
            }
            .disabled(settings.displayMode != .allDisplays)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                displays = ConnectedDisplay.current()
            }
            SettingToggle(symbol: "eye.slash.fill", color: .gray, title: "Invisible Until Hover",
                          detail: "Hide the island until you hover. Music, timers and popups still show.",
                          isOn: $settings.invisibleUntilHover)
            SettingToggle(symbol: "arrow.up.left.and.arrow.down.right", color: .indigo, title: "Hide in Full Screen",
                          detail: "Hide the island when an app goes full screen. Volume and brightness still show.",
                          isOn: $settings.hideInFullscreen, testID: "setting-hideInFullscreen")
            SettingRow(symbol: "play.rectangle.fill", color: .indigo, title: "Full-Screen Apps",
                       detail: "Every full-screen app, or only the one playing media.") {
                Picker("Full-screen apps", selection: $settings.fullscreenScope) {
                    ForEach(FullscreenScope.allCases, id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .uiTestID("setting-fullscreenScope")
            }
            .disabled(!settings.hideInFullscreen)
            SettingToggle(symbol: "rectangle.on.rectangle", color: .gray, title: "Hide While Mirroring",
                          detail: "Hide the island when you mirror to a projector or TV.",
                          isOn: $settings.hideWhileMirroring, testID: "setting-hideWhileMirroring")
            SettingToggle(symbol: "rectangle.dashed.badge.record", color: .red, title: "Screen Sharing Privacy",
                          detail: "Keep the island out of screenshots, recordings and screen sharing.",
                          isOn: $settings.screenSharingPrivacy, testID: "setting-screenSharingPrivacy")
        }
    }

    private var previewSection: some View {
        Section {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(DemoActivity.allCases, id: \.self) { demo in
                    Button(demoTitle(demo)) { vm.simulate(demo) }
                        .frame(maxWidth: .infinity)
                }
            }
        } header: {
            Text("Try It")
        } footer: {
            SettingsFooter("Play each popup once so you can see it.")
        }
    }

    private func displayBinding(_ display: ConnectedDisplay) -> Binding<Bool> {
        Binding(
            get: { !DisplaySelection.parse(settings.hiddenDisplays).contains(display.key) },
            set: { show in
                settings.hiddenDisplays = DisplaySelection.toggled(settings.hiddenDisplays, key: display.key, show: show,
                                                                   connected: displays.map(\.key))
            }
        )
    }

    private func displayDetail(_ display: ConnectedDisplay) -> String {
        if settings.displayMode != .allDisplays { return "Pick Every Display above to choose displays." }
        let on = !DisplaySelection.parse(settings.hiddenDisplays).contains(display.key)
        let shown = displays.filter { !DisplaySelection.parse(settings.hiddenDisplays).contains($0.key) }
        if on && shown.count == 1 { return "At least one display keeps the island." }
        return on ? "Shows an island on this display." : "No island on this display."
    }

    /// What the selected Show On choice does, and its cost.
    private var displayModeDetail: String {
        switch settings.displayMode {
        case .notchOrMain: return "Just the MacBook screen, or the main display if there's no notch."
        case .main: return "Just the display with the menu bar."
        case .external: return "Just an external display, or the MacBook if none is plugged in."
        case .followMouse: return "Follows your pointer from display to display."
        case .allDisplays: return "An island on each display you switch on below."
        }
    }

    private func shortTitle(_ mode: DisplayMode) -> String {
        switch mode {
        case .notchOrMain: return "Built-in"
        case .main: return "Main"
        case .external: return "External"
        case .followMouse: return "Follow Mouse"
        case .allDisplays: return "Every Display"
        }
    }

    private func demoTitle(_ demo: DemoActivity) -> String {
        switch demo {
        case .lowBattery: return "Low Battery"
        case .airpods: return "AirPods"
        case .peek: return "Track Peek"
        case .capsLock: return "Caps Lock"
        default: return demo.rawValue.capitalized
        }
    }
}

struct PopupsSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var focus: FocusService

    var body: some View {
        SettingsPageView(page: .popups) {
            durationSection
            systemSection
            privacySection
            soundsSection
            featuresSection
            RestoreDefaultsSection(keys: [
                SettingsKey.notificationDuration, SettingsKey.volumeHUD, SettingsKey.brightnessHUD,
                SettingsKey.capsLockActivity, SettingsKey.focusActivity, SettingsKey.privacyActivity,
                SettingsKey.downloadActivity, SettingsKey.copyProgress, SettingsKey.notifyActivity,
                SettingsKey.sensorDot, SettingsKey.meetingMeter, SettingsKey.meetingTalkShare, SettingsKey.macVitals, SettingsKey.quietDuringFocus,
                SettingsKey.alertSounds, SettingsKey.edgeGlow,
            ])
        }
    }

    private var durationSection: some View {
        Section("Timing") {
            SliderRow(symbol: "timer", color: .orange, title: "Notification Duration",
                      detail: "How long script notifications stay up.",
                      value: $settings.notificationDuration, range: 1...15, step: 0.5,
                      format: SettingsFormat.oneDecimalSeconds)
        }
    }

    private var systemSection: some View {
        Section {
            SettingToggle(symbol: "speaker.wave.2.fill", color: .gray, title: "Volume",
                          detail: settings.hudEnabled ? "Show the level when you change the volume."
                                                      : "Turn on the HUD on the HUD page to use this.",
                          isOn: $settings.volumeHUD)
                .disabled(!settings.hudEnabled)
            SettingToggle(symbol: "sun.max.fill", color: .yellow, title: "Brightness",
                          detail: settings.hudEnabled ? "Show the level when you change the display brightness."
                                                      : "Turn on the HUD on the HUD page to use this.",
                          isOn: $settings.brightnessHUD)
                .disabled(!settings.hudEnabled)
            SettingToggle(symbol: "capslock.fill", color: .green, title: "Caps Lock",
                          detail: "Show when Caps Lock turns on or off.",
                          isOn: $settings.capsLockActivity)
            SettingToggle(symbol: "moon.fill", color: .indigo, title: "Focus Changes",
                          detail: "Show when a Focus mode turns on or off. Needs Full Disk Access.",
                          isOn: $settings.focusActivity)
            if settings.focusActivity && !focus.isReadable {
                SettingRow(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Focus Can't Be Read Yet",
                           detail: "Give DynaNotch Full Disk Access, then restart it.") {
                    Button("Open…") { Permissions.openFullDiskAccessSettings() }
                }
            }
            SettingToggle(symbol: "moon.zzz.fill", color: .indigo, title: "Quiet Popups During Focus",
                          detail: "Hold popups back while Focus is on. Needs Full Disk Access.",
                          isOn: $settings.quietDuringFocus, testID: "setting-quietDuringFocus")
            SettingToggle(symbol: "terminal.fill", color: .gray, title: "Notifications from Scripts",
                          detail: "Show messages sent with dynanotch://notify, like Claude Code hooks.",
                          isOn: $settings.notifyActivity)
        } header: {
            Text("System")
        }
    }

    private var privacySection: some View {
        Section("Privacy & Files") {
            SettingToggle(symbol: "video.fill", color: .green, title: "Camera & Microphone in Use",
                          detail: "Show when an app starts or stops using the camera or mic.",
                          isOn: $settings.privacyActivity)
            SettingToggle(symbol: "circle.fill", color: .orange, title: "Dot While On",
                          detail: "A small green or orange dot while the camera or mic is on.",
                          isOn: $settings.sensorDot, testID: "setting-sensorDot")
            SettingToggle(symbol: "phone.fill", color: .green, title: "Meeting Meter",
                          detail: "Shows how long your call has been going, with a short recap after.",
                          isOn: $settings.meetingMeter, testID: "setting-meetingMeter")
            SettingToggle(symbol: "waveform", color: .purple, title: "Your Talk Share",
                          detail: "Also show how much you talked. Only reads your mic level, nothing is recorded.",
                          isOn: $settings.meetingTalkShare, testID: "setting-meetingTalkShare")
                .disabled(!settings.meetingMeter)
            SensorLogRows()
            SettingToggle(symbol: "heart.text.square.fill", color: .red, title: "Mac Vitals",
                          detail: "Warns when your Mac gets hot, low on memory or disk, or an app hogs the CPU.",
                          isOn: $settings.macVitals, testID: "setting-macVitals")
            SettingToggle(symbol: "arrow.down.circle.fill", color: .blue, title: "Downloads",
                          detail: "Show when a download starts and finishes.",
                          isOn: $settings.downloadActivity)
            SettingToggle(symbol: "doc.on.doc.fill", color: .green, title: "File Copies",
                          detail: "Show a progress bar while Finder copies files.",
                          isOn: $settings.copyProgress, testID: "setting-copyProgress")
        }
    }

    private func soundBinding(_ category: AlertCategory) -> Binding<String> {
        Binding(get: { AlertSounds.sound(for: category, in: settings.alertSounds) },
                set: { settings.alertSounds = AlertSounds.setting($0, for: category, in: settings.alertSounds) })
    }

    private func soundDetail(_ category: AlertCategory) -> String {
        switch category {
        case .timers: return "Timers, Pomodoro and break reminders."
        case .calendar: return "Upcoming events and meeting alerts."
        case .battery: return "Low battery, fully charged and fast drain."
        case .devices: return "Accessories connecting, low or fully charged."
        case .downloads: return "Finished downloads and mounted drives."
        case .notifications: return "Messages from scripts and Claude Code hooks."
        case .aiUsage: return "AI usage limit warnings."
        case .screenLock: return "When the screen locks."
        case .screenUnlock: return "When you unlock and come back."
        }
    }

    private func soundSymbol(_ category: AlertCategory) -> String {
        switch category {
        case .timers: return "timer"
        case .calendar: return "calendar"
        case .battery: return "battery.25percent"
        case .devices: return "airpods"
        case .downloads: return "arrow.down.circle.fill"
        case .notifications: return "bell.fill"
        case .aiUsage: return "sparkles"
        case .screenLock: return "lock.fill"
        case .screenUnlock: return "lock.open.fill"
        }
    }

    private var soundsSection: some View {
        Section {
            ForEach(AlertCategory.allCases, id: \.self) { category in
                SettingRow(symbol: soundSymbol(category), color: .red, title: category.title,
                           detail: soundDetail(category)) {
                    HStack(spacing: 6) {
                        Button {
                            AlertSoundPlayer.preview(AlertSounds.sound(for: category, in: settings.alertSounds))
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(AlertSounds.sound(for: category, in: settings.alertSounds) == AlertSounds.none)
                        .help("Play this sound")
                        .uiTestID("sound-\(category.rawValue)-play")
                        Picker(category.title, selection: soundBinding(category)) {
                            Text("None").tag(AlertSounds.none)
                            Divider()
                            ForEach(AlertSounds.systemSounds, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .uiTestID("sound-\(category.rawValue)")
                    }
                }
            }
            SettingToggle(symbol: "rectangle.dashed", color: .orange, title: "Edge Glow",
                          detail: "Make the screen edge glow softly with the alert.",
                          isOn: $settings.edgeGlow, testID: "setting-edgeGlow")
        } header: {
            Text("Alert Sounds")
        } footer: {
            SettingsFooter("Plays at your Mac's alert volume. Pick None to keep one quiet.")
        }
    }

    private var featuresSection: some View {
        Section {
            SettingNavigationRow(page: .timer, detail: "Timers, Pomodoro and break reminders.")
            SettingNavigationRow(page: .calendar, detail: "Upcoming events and meeting alerts.")
            SettingNavigationRow(page: .battery, detail: "Charging, low battery and fully charged.")
            SettingNavigationRow(page: .connectivity, detail: "AirPods and other accessories.")
            SettingNavigationRow(page: .files, detail: "Downloads and mounted drives.")
        } header: {
            Text("Feature Alerts")
        } footer: {
            SettingsFooter("Each feature's popups live on its own page.")
        }
    }
}

/// The last camera / microphone sessions (Settings → Popups), with Clear.
struct SensorLogRows: View {
    @ObservedObject private var privacy = PrivacyMonitor.shared

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    var body: some View {
        SettingStackedRow(symbol: "list.bullet.rectangle", color: .gray, title: "Recent Camera & Microphone Use",
                          detail: "The last \(min(8, privacy.log.sessions.count)) sessions. Stays on this Mac.") {
            VStack(alignment: .leading, spacing: 4) {
                if privacy.log.sessions.isEmpty {
                    Text("Nothing yet").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(privacy.log.sessions.prefix(8).enumerated()), id: \.offset) { _, s in
                    HStack(spacing: 6) {
                        Image(systemName: s.sensor == "camera" ? "video.fill" : "mic.fill")
                            .foregroundStyle(s.sensor == "camera" ? Color.green : Color.orange)
                            .frame(width: 16)
                        Text(s.app.isEmpty ? (s.sensor == "camera" ? "Camera" : "Microphone") : s.app)
                        Spacer()
                        Text(Self.time.string(from: s.start)).foregroundStyle(.secondary)
                        Text(s.duration.map { CallFormat.duration($0) } ?? "now").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                if !privacy.log.sessions.isEmpty {
                    Button("Clear") { privacy.clearLog() }
                        .controlSize(.small)
                        .uiTestID("sensorLog-clear")
                }
            }
        }
    }
}


/// One display in Settings → Behavior → Show On.
struct ConnectedDisplay: Identifiable, Equatable {
    let key: String
    let name: String
    let isBuiltIn: Bool

    var id: String { key }
    /// Test ID suffix: the display name in lower case, letters and digits only.
    var testKey: String { name.lowercased().filter { $0.isLetter || $0.isNumber } }

    static func current() -> [ConnectedDisplay] {
        var seen = Set<String>()
        return NSScreen.screens.compactMap { screen in
            guard let key = ScreenLocator.displayKey(screen), seen.insert(key).inserted else { return nil }
            return ConnectedDisplay(key: key, name: screen.localizedName, isBuiltIn: ScreenLocator.isBuiltIn(screen))
        }
    }
}
