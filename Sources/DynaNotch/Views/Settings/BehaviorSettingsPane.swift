import SwiftUI
import DynaNotchCore

struct BehaviorSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var vm: IslandViewModel

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
                SettingsKey.invisibleUntilHover, SettingsKey.displayMode, SettingsKey.hideInFullscreen,
                SettingsKey.autoCollapse, SettingsKey.fullscreenScope, SettingsKey.hideWhileMirroring,
                SettingsKey.screenSharingPrivacy, SettingsKey.hotkeysEnabled, SettingsKey.hotkeyBindings,
            ])
        }
    }

    private var openingSection: some View {
        Section("Opening") {
            SettingToggle(symbol: "cursorarrow.rays", color: .blue, title: "Expand on Hover",
                          detail: "Open the panel when the pointer rests on the island.",
                          isOn: $settings.expandOnHover)
            SliderRow(symbol: "hourglass", color: .blue, title: "Hover Delay",
                      detail: "Wait this long before opening, so passing the pointer by doesn't open it.",
                      value: $settings.hoverDelay, range: 0...1, step: 0.05, format: SettingsFormat.seconds)
                .disabled(!settings.expandOnHover)
            SettingToggle(symbol: "cursorarrow.click", color: .indigo, title: "Click to Expand",
                          detail: "Clicking the island opens or closes the panel.",
                          isOn: $settings.clickToExpand)
            SettingRow(symbol: "rectangle.stack.fill", color: .purple, title: "Default Tab",
                       detail: "Which tab the panel opens on after it has been closed.") {
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
                          detail: "Reopen on the tab you used last. Only applies with Default Tab set to Previous Tab.",
                          isOn: $settings.rememberLastTab)
                .disabled(settings.defaultTab != "previous")
            SettingToggle(symbol: "waveform", color: .pink, title: "Open on Current Activity",
                          detail: "While music plays or a timer runs, open on Now Playing or Timer instead of the default tab.",
                          isOn: $settings.openOnCurrentActivity)
        }
    }

    private var closingSection: some View {
        Section("Closing") {
            SettingToggle(symbol: "rectangle.compress.vertical", color: .teal, title: "Auto Collapse",
                          detail: "Close the panel when the pointer leaves it. When off, it stays open until you click outside or press Esc.",
                          isOn: $settings.autoCollapse, testID: "setting-autoCollapse")
            SliderRow(symbol: "arrow.down.right.and.arrow.up.left", color: .teal, title: "Collapse Delay",
                      detail: "Wait this long after the pointer leaves the panel before closing it. Needs Auto Collapse.",
                      value: $settings.collapseDelay, range: 0...2, step: 0.05, format: SettingsFormat.seconds,
                      testID: "setting-collapseDelay")
                .disabled(!settings.autoCollapse)
            SettingRow(symbol: "moon.zzz.fill", color: .gray, title: "Idle Timeout",
                       detail: "Close a pinned or untouched panel after this long. Never keeps it open.") {
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
                          detail: "Two-finger swipe on the island: ← → skips tracks, ↑ closes or dismisses.",
                          isOn: $settings.gesturesEnabled)
        }
    }

    private var shortcutsSection: some View {
        Section {
            SettingToggle(symbol: "keyboard.fill", color: .gray, title: "Global Shortcuts",
                          detail: "Work in every app and need no permission. Turn off to free all of them at once.",
                          isOn: $settings.hotkeysEnabled, testID: "setting-hotkeysEnabled")
            ForEach(HotKeyAction.allCases, id: \.self) { action in
                ShortcutRow(key: action.rawValue, symbol: action.settingsSymbol, color: action.settingsColor,
                            title: action.title, detail: action.settingsDetail)
            }
            .disabled(!settings.hotkeysEnabled)
        } header: {
            Text("Keyboard Shortcuts")
        } footer: {
            SettingsFooter("Click a shortcut and press the new keys (with ⌃, ⌥ or ⌘). Esc cancels, Delete removes it. ⟲ restores the default.")
        }
    }

    private var tabShortcutsSection: some View {
        Section {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                ShortcutRow(key: HotKeyMap.tabKey(tab), symbol: tab.symbolName, color: .purple,
                            title: tab.title, detail: "Open the panel on \(tab.title), or close it if it's already showing.")
            }
            .disabled(!settings.hotkeysEnabled)
        } header: {
            Text("Tab Shortcuts")
        } footer: {
            SettingsFooter("Tabs have no shortcut until you record one.")
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
            SettingToggle(symbol: "eye.slash.fill", color: .gray, title: "Invisible Until Hover",
                          detail: "Hide the resting island completely. Music, timers and popups still appear as normal.",
                          isOn: $settings.invisibleUntilHover)
            SettingToggle(symbol: "arrow.up.left.and.arrow.down.right", color: .indigo, title: "Hide in Full Screen",
                          detail: "Hide the island while an app is full screen. Volume and brightness popups still show.",
                          isOn: $settings.hideInFullscreen, testID: "setting-hideInFullscreen")
            SettingRow(symbol: "play.rectangle.fill", color: .indigo, title: "Full-Screen Apps",
                       detail: "Hide for every full-screen app, or only when the app playing media is full screen.") {
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
                          detail: "Hide the island while this display is mirrored, e.g. to a projector or TV.",
                          isOn: $settings.hideWhileMirroring, testID: "setting-hideWhileMirroring")
            SettingToggle(symbol: "rectangle.dashed.badge.record", color: .red, title: "Screen Sharing Privacy",
                          detail: "Hide the island from screenshots, recordings and screen sharing. You still see it.",
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
            SettingsFooter("Plays each live activity once in the notch so you can see how it looks.")
        }
    }

    /// What the selected Show On choice does, and its cost.
    private var displayModeDetail: String {
        switch settings.displayMode {
        case .notchOrMain: return "One island, on the MacBook's notch display (the main display if there is none)."
        case .main: return "One island, on the display with the menu bar."
        case .external: return "One island, on an external display; the built-in display when none is plugged in."
        case .followMouse: return "One island that moves to whichever display your pointer is on."
        case .allDisplays: return "An island on every display, each opening on its own. Uses a little more memory and energy per display."
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
                SettingsKey.downloadActivity, SettingsKey.notifyActivity, SettingsKey.quietDuringFocus,
                SettingsKey.alertSounds, SettingsKey.edgeGlow,
            ])
        }
    }

    private var durationSection: some View {
        Section("Timing") {
            SliderRow(symbol: "timer", color: .orange, title: "Notification Duration",
                      detail: "How long notifications from scripts stay under the notch. A duration in the URL wins.",
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
                          detail: "A short popup when Caps Lock turns on or off.",
                          isOn: $settings.capsLockActivity)
            SettingToggle(symbol: "moon.fill", color: .indigo, title: "Focus Changes",
                          detail: "Shows the Focus mode when it turns on or off. Needs Full Disk Access.",
                          isOn: $settings.focusActivity)
            if settings.focusActivity && !focus.isReadable {
                SettingRow(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Focus Can't Be Read Yet",
                           detail: "Grant Full Disk Access to DynaNotch, then restart it.") {
                    Button("Open…") { Permissions.openFullDiskAccessSettings() }
                }
            }
            SettingToggle(symbol: "moon.zzz.fill", color: .indigo, title: "Quiet Popups During Focus",
                          detail: "Hold back popups while a Focus mode is on. Detecting Focus needs Full Disk Access.",
                          isOn: $settings.quietDuringFocus, testID: "setting-quietDuringFocus")
            SettingToggle(symbol: "terminal.fill", color: .gray, title: "Notifications from Scripts",
                          detail: "Show messages sent with dynanotch://notify, e.g. from a Claude Code hook.",
                          isOn: $settings.notifyActivity)
        } header: {
            Text("System")
        }
    }

    private var privacySection: some View {
        Section("Privacy & Files") {
            SettingToggle(symbol: "video.fill", color: .green, title: "Camera & Microphone in Use",
                          detail: "A popup whenever an app starts or stops using the camera or microphone.",
                          isOn: $settings.privacyActivity)
            SettingToggle(symbol: "arrow.down.circle.fill", color: .blue, title: "Downloads",
                          detail: "When a download starts and finishes in ~/Downloads.",
                          isOn: $settings.downloadActivity)
        }
    }

    private func soundBinding(_ category: AlertCategory) -> Binding<String> {
        Binding(get: { AlertSounds.sound(for: category, in: settings.alertSounds) },
                set: { settings.alertSounds = AlertSounds.setting($0, for: category, in: settings.alertSounds) })
    }

    private func soundDetail(_ category: AlertCategory) -> String {
        switch category {
        case .timers: return "Timer finished, Pomodoro phases and break reminders."
        case .calendar: return "Alerts before events and meeting alerts."
        case .battery: return "Low battery, fully charged and drain warnings."
        case .devices: return "Accessories connecting, low or fully charged."
        case .downloads: return "Finished downloads and mounted drives."
        case .notifications: return "Messages from scripts and Claude Code hooks."
        case .aiUsage: return "AI usage limit warnings."
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
                          detail: "The screen edge glows softly in the alert's colour, so you notice it from the corner of your eye.",
                          isOn: $settings.edgeGlow, testID: "setting-edgeGlow")
        } header: {
            Text("Alert Sounds")
        } footer: {
            SettingsFooter("Sounds play at your Mac’s alert volume. Choose None to keep a category silent.")
        }
    }

    private var featuresSection: some View {
        Section {
            SettingNavigationRow(page: .timer, detail: "Timer finished, Pomodoro phases and break reminders.")
            SettingNavigationRow(page: .calendar, detail: "Alerts before events and full-screen meeting alerts.")
            SettingNavigationRow(page: .battery, detail: "Charging, low battery and fully charged.")
            SettingNavigationRow(page: .connectivity, detail: "AirPods and other accessories connecting, low or full.")
            SettingNavigationRow(page: .files, detail: "Downloads and mounted drives.")
        } header: {
            Text("Feature Alerts")
        } footer: {
            SettingsFooter("Each feature's own popups live on its page.")
        }
    }
}
