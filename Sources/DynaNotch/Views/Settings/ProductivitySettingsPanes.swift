import SwiftUI
import AppKit
import Combine
import DynaNotchCore

// MARK: - Timer

struct TimerSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    private var focusSection: some View {
        Section {
            SettingToggle(symbol: "eye.slash.fill", color: .red, title: "Focus Guard",
                          detail: "Opening a distracting app during focus gives the island a little shake.",
                          isOn: $settings.focusGuard, testID: "setting-focusGuard")
            SettingStackedRow(symbol: "list.bullet", color: .gray, title: "Distraction Apps",
                              detail: "App bundle IDs, separated by commas.") {
                TextField("com.tinyspeck.slackmacgap, …", text: $settings.focusGuardApps, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.system(size: 11, design: .monospaced))
                    .uiTestID("setting-focusGuardApps")
            }
            .disabled(!settings.focusGuard)
            SettingRow(symbol: "headphones", color: .indigo, title: "Focus Sound",
                       detail: "Made on this Mac, nothing to download. Stop it from the Timer tab.") {
                Picker("Focus sound", selection: Binding(
                    get: { Soundscape(rawValue: settings.soundscape) ?? .none },
                    set: { sound in
                        if sound == .none { SoundscapeService.shared.stop() } else { SoundscapeService.shared.play(sound) }
                        settings.soundscape = sound.rawValue
                    })) {
                    ForEach(Soundscape.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .uiTestID("setting-soundscape")
            }
            SliderRow(symbol: "speaker.wave.2.fill", color: .indigo, title: "Sound Volume",
                      detail: "Relative to your Mac's volume.", value: $settings.soundscapeVolume,
                      range: 0...1, step: 0.05, format: { "\(Int(($0 * 100).rounded())) %" },
                      testID: "setting-soundscapeVolume")
            SettingToggle(symbol: "timer", color: .orange, title: "Sound With Pomodoro",
                          detail: "Play your focus sound during focus, quiet during breaks.",
                          isOn: $settings.soundscapeWithPomodoro, testID: "setting-soundscapeWithPomodoro")
        } header: {
            Text("Focus")
        }
    }

    var body: some View {
        SettingsPageView(page: .timer) {
            pomodoroSection
            focusSection
            displaySection
            breaksSection
            RestoreDefaultsSection(keys: [
                SettingsKey.focusGuard, SettingsKey.focusGuardApps, SettingsKey.soundscape,
                SettingsKey.soundscapeVolume, SettingsKey.soundscapeWithPomodoro,
                SettingsKey.pomodoroWorkMinutes, SettingsKey.pomodoroShortBreakMinutes,
                SettingsKey.pomodoroLongBreakMinutes, SettingsKey.pomodoroCycles, SettingsKey.pomodoroAutoContinue,
                SettingsKey.timerSound, SettingsKey.showCompactTimer, SettingsKey.timerOverNowPlaying,
                SettingsKey.breakLookAway, SettingsKey.breakStandUp, SettingsKey.standUpMinutes,
                SettingsKey.breakDrinkWater, SettingsKey.drinkWaterMinutes, SettingsKey.timerHoverControls,
                SettingsKey.repeatTimer, SettingsKey.repeatAlarm, SettingsKey.pomodoroOnly,
            ])
        }
    }

    private var pomodoroSection: some View {
        Section("Pomodoro") {
            StepperRow(symbol: "brain.head.profile", color: .orange, title: "Focus Length",
                       detail: "How long you focus.",
                       value: $settings.pomodoroWorkMinutes, range: 5...120, step: 5, format: SettingsFormat.minutes)
            StepperRow(symbol: "cup.and.saucer.fill", color: .green, title: "Short Break",
                       detail: "A short break after each focus.",
                       value: $settings.pomodoroShortBreakMinutes, range: 1...30, format: SettingsFormat.minutes)
            StepperRow(symbol: "sofa.fill", color: .teal, title: "Long Break",
                       detail: "A longer break after a full round.",
                       value: $settings.pomodoroLongBreakMinutes, range: 5...60, step: 5, format: SettingsFormat.minutes)
            StepperRow(symbol: "repeat", color: .blue, title: "Sessions Before a Long Break",
                       detail: "Focus sessions in one round.",
                       value: $settings.pomodoroCycles, range: 2...8, format: { "\($0)" })
            SettingToggle(symbol: "forward.fill", color: .indigo, title: "Continue Automatically",
                          detail: "Start the next round on its own. Off: the timer waits for you.",
                          isOn: $settings.pomodoroAutoContinue)
            SettingToggle(symbol: "brain.head.profile", color: .orange, title: "Pomodoro Only",
                          detail: "Show only Pomodoro in the Timer tab.",
                          isOn: $settings.pomodoroOnly, testID: "setting-pomodoroOnly")
        }
    }

    private var displaySection: some View {
        Section("Alerts & Display") {
            SettingToggle(symbol: "bell.fill", color: .red, title: "Sound When a Timer Ends",
                          detail: "A short chime when a timer ends.",
                          isOn: $settings.timerSound)
            SettingToggle(symbol: "repeat.circle.fill", color: .orange, title: "Repeat Timer",
                          detail: "Start the countdown again when it ends.",
                          isOn: $settings.repeatTimer, testID: "setting-repeatTimer")
            SettingToggle(symbol: "alarm.waves.left.and.right.fill", color: .red, title: "Repeat Alarm Until Dismissed",
                          detail: "Keep ringing until you stop it.",
                          isOn: $settings.repeatAlarm, testID: "setting-repeatAlarm")
                .disabled(!settings.timerSound)
            SettingToggle(symbol: "timer", color: .orange, title: "Running Timer Around the Notch",
                          detail: "Show the time left next to the notch.",
                          isOn: $settings.showCompactTimer)
            SettingToggle(symbol: "music.note", color: .pink, title: "Prefer Timer Over Now Playing",
                          detail: "Show the timer instead of the music when both are on.",
                          isOn: $settings.timerOverNowPlaying)
                .disabled(!settings.showCompactTimer)
            SettingToggle(symbol: "hand.point.up.left.fill", color: .blue, title: "Controls on Hover",
                          detail: "Hover the timer to pause, add a minute or stop.",
                          isOn: $settings.timerHoverControls, testID: "setting-timerHoverControls")
                .disabled(!settings.showCompactTimer)
        }
    }

    private var breaksSection: some View {
        Section {
            SettingToggle(symbol: BreakKind.lookAway.symbol, color: .blue, title: "Look Away (20-20-20)",
                          detail: "Every 20 minutes, look at something far away for 20 seconds.",
                          isOn: $settings.breakLookAway)
            SettingToggle(symbol: BreakKind.standUp.symbol, color: .green, title: "Stand Up",
                          detail: "A nudge to get up and move.",
                          isOn: $settings.breakStandUp)
            StepperRow(symbol: "clock.fill", color: .green, title: "Stand-Up Interval",
                       detail: "How often to remind you.",
                       value: $settings.standUpMinutes, range: 15...180, step: 15, format: SettingsFormat.minutes)
                .disabled(!settings.breakStandUp)
                .padding(.leading, 20)
            SettingToggle(symbol: BreakKind.drinkWater.symbol, color: .cyan, title: "Drink Water",
                          detail: "A reminder to stay hydrated.",
                          isOn: $settings.breakDrinkWater)
            StepperRow(symbol: "clock.fill", color: .cyan, title: "Drink-Water Interval",
                       detail: "How often to remind you.",
                       value: $settings.drinkWaterMinutes, range: 15...180, step: 15, format: SettingsFormat.minutes)
                .disabled(!settings.breakDrinkWater)
                .padding(.leading, 20)
        } header: {
            Text("Break Reminders")
        } footer: {
            SettingsFooter("Reminders wait while you're away or in full screen.")
        }
    }
}

// MARK: - Clipboard

struct ClipboardSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var clipboard = ClipboardService.shared
    @State private var accessibilityGranted = Permissions.accessibilityGranted

    private let permissionPoll = SettingsTicker.tick
    private static let limits = [40, 50, 100, 200, 500]

    var body: some View {
        SettingsPageView(page: .clipboard) {
            historySection
            smartCopySection
            pasteSection
            ignoredSection
            RestoreDefaultsSection(keys: [
                SettingsKey.smartCopy, SettingsKey.homeCurrency,
                SettingsKey.clipboardEnabled, SettingsKey.clipboardLimit, SettingsKey.cleanLinks,
                SettingsKey.pasteOnClick, SettingsKey.pasteWithNumbers, SettingsKey.clipboardIgnoredApps,
                SettingsKey.clipboardAutoClearMinutes, SettingsKey.clipboardCaptureSound,
                SettingsKey.clipboardSkipSecrets, SettingsKey.clipboardClearOnLock,
                SettingsKey.copyTwiceToOpen, SettingsKey.offerCleanCopy,
            ])
        }
        .onReceive(permissionPoll) { _ in
            accessibilityGranted = Permissions.accessibilityGranted
        }
    }

    private static let currencies = ["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "INR", "BDT", "SEK", "NOK",
                                     "DKK", "PLN", "CZK", "HUF", "CNY", "TRY", "BRL", "MXN", "KRW", "SGD"]

    private var smartCopySection: some View {
        Section {
            SettingToggle(symbol: "wand.and.stars", color: .purple, title: "Smart Copy",
                          detail: "Copy an amount, unit, time or hex number to see it converted. Click to copy the result.",
                          isOn: $settings.smartCopy, testID: "setting-smartCopy")
                .disabled(!settings.clipboardEnabled)
            SettingRow(symbol: "dollarsign.circle.fill", color: .green, title: "Home Currency",
                       detail: "Your currency. Amounts already in it show in US dollars.") {
                Picker("Home currency", selection: $settings.homeCurrency) {
                    ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .uiTestID("setting-homeCurrency")
            }
            .disabled(!settings.clipboardEnabled || !settings.smartCopy)
        } header: {
            Text("Smart Copy")
        } footer: {
            SettingsFooter(settings.clipboardEnabled ? "Done on this Mac. Only currency rates come from the internet."
                                                     : "Turn on Clipboard History to use Smart Copy.")
        }
    }

    private var historySection: some View {
        Section {
            SettingToggle(symbol: "doc.on.clipboard.fill", color: .teal, title: "Clipboard History",
                          detail: "Keep what you copy so you can paste it later.",
                          isOn: $settings.clipboardEnabled)
            Group {
                SettingValueRow(symbol: "tray.full.fill", color: .gray, title: "Stored Items",
                                detail: "Pinned items stay even when the list is full.",
                                value: "\(clipboard.history.items.count) of \(settings.clipboardLimit)")
                SettingRow(symbol: "list.number", color: .blue, title: "History Limit",
                           detail: "Older items drop off past this.") {
                    Picker("History limit", selection: $settings.clipboardLimit) {
                        ForEach(ClipboardSettingsPane.limits, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                        if !ClipboardSettingsPane.limits.contains(settings.clipboardLimit) {
                            Text("\(settings.clipboardLimit)").tag(settings.clipboardLimit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingRow(symbol: "clock.badge.xmark", color: .orange, title: "Auto-Clear",
                           detail: "Clear unpinned items older than this.") {
                    Picker("Auto-clear", selection: $settings.clipboardAutoClearMinutes) {
                        Text("Never").tag(0)
                        Text("After 5 minutes").tag(5)
                        Text("After 15 minutes").tag(15)
                        Text("After 30 minutes").tag(30)
                        Text("After 1 hour").tag(60)
                        Text("After 2 hours").tag(120)
                        Text("After 1 day").tag(1440)
                        Text("After 1 week").tag(10080)
                        if ![0, 5, 15, 30, 60, 120, 1440, 10080].contains(settings.clipboardAutoClearMinutes) {
                            Text("After \(settings.clipboardAutoClearMinutes) minutes").tag(settings.clipboardAutoClearMinutes)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingToggle(symbol: "link", color: .indigo, title: "Clean Links",
                              detail: "Remove tracking bits from copied links.",
                              isOn: $settings.cleanLinks)
                SettingRow(symbol: "link.badge.plus", color: .indigo, title: "Tracking Links",
                           detail: settings.offerCleanCopy
                               ? "Keep your link and offer a clean one in the notch."
                               : "Swap in the clean link right away.") {
                    Picker("Tracking links", selection: $settings.offerCleanCopy) {
                        Text("Strip").tag(false)
                        Text("Offer a Clean Copy").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .uiTestID("setting-offerCleanCopy")
                }
                .disabled(!settings.cleanLinks)
                SettingToggle(symbol: "doc.on.doc.fill", color: .teal, title: "Copy Twice to Open",
                              detail: "Press ⌘C twice to open your clipboard.",
                              isOn: $settings.copyTwiceToOpen, testID: "setting-copyTwiceToOpen")
                SettingToggle(symbol: "key.fill", color: .red, title: "Skip Secrets",
                              detail: "Passwords, keys, tokens and card numbers aren't saved. Codes vanish after 2 minutes.",
                              isOn: $settings.clipboardSkipSecrets, testID: "setting-clipboardSkipSecrets")
                SettingToggle(symbol: "lock.fill", color: .gray, title: "Clear on Lock",
                              detail: "Clear the history (except pinned items) when your Mac locks.",
                              isOn: $settings.clipboardClearOnLock, testID: "setting-clipboardClearOnLock")
                SettingToggle(symbol: "speaker.wave.2.fill", color: .pink, title: "Capture Sound",
                              detail: "A soft click when something gets copied.",
                              isOn: $settings.clipboardCaptureSound, testID: "setting-clipboardCaptureSound")
                SettingRow(symbol: "trash.fill", color: .red, title: "Clear History",
                           detail: "Removes every unpinned item now.") {
                    InlineConfirmButton(title: "Clear…", confirmTitle: "Clear") { clipboard.clear() }
                        .disabled(clipboard.history.items.isEmpty)
                }
            }
            .disabled(!settings.clipboardEnabled)
        } header: {
            Text("History")
        } footer: {
            PrivacyFooter(text: "Stays on this Mac. Passwords are never saved.")
        }
    }

    private var pasteSection: some View {
        Section {
            SettingToggle(symbol: "cursorarrow.click.2", color: .blue, title: "Paste on Click",
                          detail: "Click an item to paste it. Needs Accessibility.",
                          isOn: $settings.pasteOnClick)
            SettingToggle(symbol: "number", color: .purple, title: "Paste with 1–9",
                          detail: "Press a number to paste that item.",
                          isOn: $settings.pasteWithNumbers)
            ShortcutRow(key: HotKeyAction.pastePlainText.rawValue, symbol: "doc.plaintext.fill", color: .teal,
                        title: "Paste as Plain Text",
                        detail: "Paste without formatting anywhere. Needs Accessibility.")
                .disabled(!settings.hotkeysEnabled)
            if accessibilityGranted {
                SettingValueRow(symbol: "accessibility", color: .green, title: "Accessibility",
                                detail: "Lets DynaNotch paste for you.",
                                value: "Granted", valueColor: .green)
            } else {
                SettingRow(symbol: "accessibility", color: .orange, title: "Accessibility",
                           detail: "Without it, items are copied but not pasted.") {
                    Button("Allow…") { Permissions.requestAccessibility() }
                }
            }
        } header: {
            Text("Pasting")
        } footer: {
            SettingsFooter("⌥-click to paste as plain text.")
        }
        .disabled(!settings.clipboardEnabled)
    }

    private var ignoredSection: some View {
        Section {
            BundleIDListEditor(list: $settings.clipboardIgnoredApps, placeholder: "com.example.app")
        } header: {
            Text("Ignored Apps")
        } footer: {
            SettingsFooter("Nothing copied in these apps is saved. Password managers are skipped.")
        }
        .disabled(!settings.clipboardEnabled)
    }
}

// MARK: - Quick Search

struct QuickSearchSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        SettingsPageView(page: .quickSearch) {
            Section {
                SettingRow(symbol: "magnifyingglass", color: .blue, title: "Default Engine",
                           detail: "Used when you search without a shortcut.") {
                    Picker("Default engine", selection: $settings.quickSearchEngine) {
                        ForEach(QuickSearch.builtIn) { engine in
                            Label(engine.name, systemImage: engine.symbol).tag(engine.id)
                        }
                        let custom = JSONList.decode(settings.customSearchEngines, as: SearchEngine.self)
                        if !custom.isEmpty {
                            Divider()
                            ForEach(custom) { engine in
                                Label(engine.name, systemImage: engine.symbol).tag(engine.id)
                            }
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } header: {
                Text("Search")
            }
            Section {
                ForEach(QuickSearch.builtIn) { engine in
                    SettingRow(symbol: engine.symbol, color: .gray, title: engine.name,
                               detail: "Type “\(engine.shortcut) …” to search \(engine.name).") {
                        Text(engine.shortcut)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.07)))
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                SettingsFooter("Start with a shortcut to use another engine, like “gh swiftui”.")
            }
            Section {
                CustomEnginesEditor()
            } header: {
                Text("Custom Engines")
            } footer: {
                SettingsFooter("Put %@ where the search words go.")
            }
            Section {
                BundleIDListEditor(list: $settings.launcherApps, placeholder: "com.apple.Safari")
            } header: {
                Text("Launcher Apps")
            } footer: {
                SettingsFooter("Your pinned apps, in this order. Running apps show too.")
            }
            RestoreDefaultsSection(keys: [SettingsKey.quickSearchEngine, SettingsKey.launcherApps,
                                          SettingsKey.customSearchEngines])
        }
    }
}

// MARK: - Files & Utilities

struct FilesSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @State private var zshHookInstalled = ShellHookInstaller.zshHookInstalled
    @State private var zshMessage: String?

    var body: some View {
        SettingsPageView(page: .files) {
            Section {
                SettingToggle(symbol: "tray.full.fill", color: .cyan, title: "File Shelf",
                              detail: "Drop files on the notch, drag them out later.",
                              isOn: $settings.shelfEnabled)
                SettingToggle(symbol: "arrow.up.forward.app.fill", color: .blue, title: "Remove After Dragging Out",
                              detail: "Remove a file once you've dragged it out.",
                              isOn: $settings.shelfRemoveOnDragOut)
                    .disabled(!settings.shelfEnabled)
                SettingToggle(symbol: "wand.and.rays", color: .purple, title: "Drop Alchemy",
                              detail: "Drop an image or PDF to cut it out, grab its text or shrink it. All on this Mac.",
                              isOn: $settings.alchemyZones, testID: "setting-alchemyZones")
                    .disabled(!settings.shelfEnabled)
                SettingStackedRow(symbol: "clock.arrow.circlepath", color: .orange, title: "Keep Files",
                                  detail: "Clear the shelf after this long. Your files stay put.") {
                    Picker("Keep files", selection: $settings.shelfRetention) {
                        ForEach(ShelfRetention.allCases, id: \.self) { r in
                            Text(r.title).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .uiTestID("setting-shelfRetention")
                }
                .disabled(!settings.shelfEnabled)
            } header: {
                Text("Shelf")
            } footer: {
                PrivacyFooter(text: "The shelf only remembers where your files are.")
            }
            Section("Popups") {
                SettingToggle(symbol: "arrow.down.circle.fill", color: .blue, title: "Downloads",
                              detail: "Show when a download starts and finishes.",
                              isOn: $settings.downloadActivity)
                SettingToggle(symbol: "externaldrive.fill", color: .gray, title: "Drive Mounted",
                              detail: "Show an Eject button when you plug in a drive.",
                              isOn: $settings.driveActivity)
                SettingToggle(symbol: "externaldrive.fill.badge.plus", color: .blue, title: "Offer to Install Apps",
                              detail: "Offer to install the app when you open a .dmg.",
                              isOn: $settings.dmgInstallOffer, testID: "setting-dmgInstallOffer")
            }
            Section {
                SettingRow(symbol: "terminal.fill", color: .gray, title: "Long-Command Islands",
                           detail: zshHookInstalled
                               ? "Installed. Long Terminal commands will ping you when done."
                               : "Get a popup when a long Terminal command finishes.") {
                    if zshHookInstalled {
                        Button("Remove") {
                            ShellHookInstaller.removeZshHook()
                            zshHookInstalled = ShellHookInstaller.zshHookInstalled
                            zshMessage = zshHookInstalled ? "Could not remove the hook." : "Hook removed. Open a new Terminal window."
                        }
                        .uiTestID("setting-zshHook-remove")
                    } else {
                        Button("Install") {
                            let ok = ShellHookInstaller.installZshHook()
                            zshHookInstalled = ShellHookInstaller.zshHookInstalled
                            zshMessage = ok ? "Done. Works in new Terminal windows."
                                            : "Could not update ~/.zshrc."
                        }
                        .uiTestID("setting-zshHook-install")
                    }
                }
                .disabled(!settings.notifyActivity)
                if let message = zshMessage {
                    Label(message, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Terminal")
            } footer: {
                SettingsFooter(settings.notifyActivity
                               ? "Only adds one small hook to ~/.zshrc. zsh only."
                               : "Turn on Show in DynaNotch under General first.")
            }
            .onAppear { zshHookInstalled = ShellHookInstaller.zshHookInstalled }
            RestoreDefaultsSection(keys: [
                SettingsKey.shelfEnabled, SettingsKey.shelfRemoveOnDragOut, SettingsKey.shelfRetention, SettingsKey.alchemyZones,
                SettingsKey.downloadActivity, SettingsKey.driveActivity, SettingsKey.dmgInstallOffer,
            ])
        }
    }
}

// MARK: - Screenshots

struct ScreenshotsSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        SettingsPageView(page: .screenshots) {
            Section {
                SettingToggle(symbol: "tray.and.arrow.down.fill", color: .cyan, title: "Add Screenshots to the Shelf",
                              detail: settings.shelfEnabled
                                  ? "Screenshots also land on the shelf."
                                  : "Turn on the File Shelf first.",
                              isOn: $settings.screenshotToShelf)
                    .disabled(!settings.shelfEnabled)
                SettingRow(symbol: "folder.fill", color: .blue, title: "Save To",
                           detail: folderDetail) {
                    HStack(spacing: 6) {
                        Button("Choose…", action: chooseFolder)
                            .uiTestID("setting-screenshotFolder-choose")
                        Button("Reset") { settings.screenshotFolder = "" }
                            .disabled(settings.screenshotFolder.isEmpty)
                            .uiTestID("setting-screenshotFolder-reset")
                    }
                }
            } header: {
                Text("Screenshots")
            } footer: {
                SettingsFooter("Screenshots go to the clipboard, and to this folder if you pick one.")
            }
            Section {
                SettingRow(symbol: "camera.viewfinder", color: .mint, title: "Capture Area",
                           detail: "Copy part of the screen.") {
                    Button("Capture") { QuickActions.captureScreenshot() }
                }
                SettingRow(symbol: "eyedropper", color: .purple, title: "Pick a Color",
                           detail: "Click anywhere to copy that colour.") {
                    Button("Pick") { QuickActions.pickColor() }
                }
                SettingRow(symbol: "record.circle.fill", color: .red, title: "Record Screen",
                           detail: "Record the whole screen.") {
                    Button("Record") { QuickActions.recordScreen() }
                        .uiTestID("setting-recordScreen")
                }
                SettingRow(symbol: "rectangle.dashed.badge.record", color: .red, title: "Record Area",
                           detail: "Record part of the screen.") {
                    Button("Record") { QuickActions.recordArea() }
                        .uiTestID("setting-recordArea")
                }
            } header: {
                Text("Try It")
            } footer: {
                SettingsFooter("Also in the panel's ⋯ menu.")
            }
            RestoreDefaultsSection(keys: [SettingsKey.screenshotToShelf, SettingsKey.screenshotFolder])
        }
    }

    private var folderDetail: String {
        if settings.screenshotFolder.isEmpty { return "Clipboard only" }
        return (settings.screenshotFolder as NSString).abbreviatingWithTildeInPath
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if !settings.screenshotFolder.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: settings.screenshotFolder)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.screenshotFolder = url.path
    }
}
