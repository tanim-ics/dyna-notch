import SwiftUI
import AppKit
import Combine
import DynaNotchCore

// MARK: - Timer

struct TimerSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        SettingsPageView(page: .timer) {
            pomodoroSection
            displaySection
            breaksSection
            RestoreDefaultsSection(keys: [
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
                       detail: "How long each focus session lasts.",
                       value: $settings.pomodoroWorkMinutes, range: 5...120, step: 5, format: SettingsFormat.minutes)
            StepperRow(symbol: "cup.and.saucer.fill", color: .green, title: "Short Break",
                       detail: "The break after each focus session.",
                       value: $settings.pomodoroShortBreakMinutes, range: 1...30, format: SettingsFormat.minutes)
            StepperRow(symbol: "sofa.fill", color: .teal, title: "Long Break",
                       detail: "The longer break after a full round.",
                       value: $settings.pomodoroLongBreakMinutes, range: 5...60, step: 5, format: SettingsFormat.minutes)
            StepperRow(symbol: "repeat", color: .blue, title: "Sessions Before a Long Break",
                       detail: "Focus sessions in one round.",
                       value: $settings.pomodoroCycles, range: 2...8, format: { "\($0)" })
            SettingToggle(symbol: "forward.fill", color: .indigo, title: "Continue Automatically",
                          detail: "Start the next focus or break by itself. When off, the timer waits for you.",
                          isOn: $settings.pomodoroAutoContinue)
            SettingToggle(symbol: "brain.head.profile", color: .orange, title: "Pomodoro Only",
                          detail: "The Timer tab shows just Pomodoro, without countdown presets and the stopwatch.",
                          isOn: $settings.pomodoroOnly, testID: "setting-pomodoroOnly")
        }
    }

    private var displaySection: some View {
        Section("Alerts & Display") {
            SettingToggle(symbol: "bell.fill", color: .red, title: "Sound When a Timer Ends",
                          detail: "Plays a short chime together with the “timer finished” popup.",
                          isOn: $settings.timerSound)
            SettingToggle(symbol: "repeat.circle.fill", color: .orange, title: "Repeat Timer",
                          detail: "When a countdown ends, start it again with the same length until you stop it.",
                          isOn: $settings.repeatTimer, testID: "setting-repeatTimer")
            SettingToggle(symbol: "alarm.waves.left.and.right.fill", color: .red, title: "Repeat Alarm Until Dismissed",
                          detail: "Keep ringing until you stop it in the notch, instead of chiming once.",
                          isOn: $settings.repeatAlarm, testID: "setting-repeatAlarm")
                .disabled(!settings.timerSound)
            SettingToggle(symbol: "timer", color: .orange, title: "Running Timer Around the Notch",
                          detail: "A small ring and the remaining time beside the notch while a timer runs.",
                          isOn: $settings.showCompactTimer)
            SettingToggle(symbol: "music.note", color: .pink, title: "Prefer Timer Over Now Playing",
                          detail: "When music plays too, show the timer beside the notch instead of the player.",
                          isOn: $settings.timerOverNowPlaying)
                .disabled(!settings.showCompactTimer)
            SettingToggle(symbol: "hand.point.up.left.fill", color: .blue, title: "Controls on Hover",
                          detail: "Hover the running timer for pause, +1 min and stop.",
                          isOn: $settings.timerHoverControls, testID: "setting-timerHoverControls")
                .disabled(!settings.showCompactTimer)
        }
    }

    private var breaksSection: some View {
        Section {
            SettingToggle(symbol: BreakKind.lookAway.symbol, color: .blue, title: "Look Away (20-20-20)",
                          detail: "Every 20 minutes, look at something 20 feet away for 20 seconds.",
                          isOn: $settings.breakLookAway)
            SettingToggle(symbol: BreakKind.standUp.symbol, color: .green, title: "Stand Up",
                          detail: "A nudge to get up and move.",
                          isOn: $settings.breakStandUp)
            StepperRow(symbol: "clock.fill", color: .green, title: "Stand-Up Interval",
                       detail: "Remind me to stand up this often.",
                       value: $settings.standUpMinutes, range: 15...180, step: 15, format: SettingsFormat.minutes)
                .disabled(!settings.breakStandUp)
                .padding(.leading, 20)
            SettingToggle(symbol: BreakKind.drinkWater.symbol, color: .cyan, title: "Drink Water",
                          detail: "A reminder to stay hydrated.",
                          isOn: $settings.breakDrinkWater)
            StepperRow(symbol: "clock.fill", color: .cyan, title: "Drink-Water Interval",
                       detail: "Remind me to drink this often.",
                       value: $settings.drinkWaterMinutes, range: 15...180, step: 15, format: SettingsFormat.minutes)
                .disabled(!settings.breakDrinkWater)
                .padding(.leading, 20)
        } header: {
            Text("Break Reminders")
        } footer: {
            SettingsFooter("Reminders pause while you are idle or in full screen.")
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
            pasteSection
            ignoredSection
            RestoreDefaultsSection(keys: [
                SettingsKey.clipboardEnabled, SettingsKey.clipboardLimit, SettingsKey.cleanLinks,
                SettingsKey.pasteOnClick, SettingsKey.pasteWithNumbers, SettingsKey.clipboardIgnoredApps,
                SettingsKey.clipboardAutoClearMinutes, SettingsKey.clipboardCaptureSound,
                SettingsKey.copyTwiceToOpen, SettingsKey.offerCleanCopy,
            ])
        }
        .onReceive(permissionPoll) { _ in
            accessibilityGranted = Permissions.accessibilityGranted
        }
    }

    private var historySection: some View {
        Section {
            SettingToggle(symbol: "doc.on.clipboard.fill", color: .teal, title: "Clipboard History",
                          detail: "Remember what you copy so you can paste it again from the Clipboard tab.",
                          isOn: $settings.clipboardEnabled)
            Group {
                SettingValueRow(symbol: "tray.full.fill", color: .gray, title: "Stored Items",
                                detail: "Pinned items are kept even when the history is full.",
                                value: "\(clipboard.history.items.count) of \(settings.clipboardLimit)")
                SettingRow(symbol: "list.number", color: .blue, title: "History Limit",
                           detail: "The oldest unpinned items are dropped beyond this.") {
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
                           detail: "Remove unpinned items older than this.") {
                    Picker("Auto-clear", selection: $settings.clipboardAutoClearMinutes) {
                        Text("Never").tag(0)
                        Text("After 5 minutes").tag(5)
                        Text("After 15 minutes").tag(15)
                        Text("After 30 minutes").tag(30)
                        Text("After 1 hour").tag(60)
                        Text("After 2 hours").tag(120)
                        if ![0, 5, 15, 30, 60, 120].contains(settings.clipboardAutoClearMinutes) {
                            Text("After \(settings.clipboardAutoClearMinutes) minutes").tag(settings.clipboardAutoClearMinutes)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                SettingToggle(symbol: "link", color: .indigo, title: "Clean Links",
                              detail: "Strip tracking parameters (utm_, fbclid …) from copied links.",
                              isOn: $settings.cleanLinks)
                SettingRow(symbol: "link.badge.plus", color: .indigo, title: "Tracking Links",
                           detail: settings.offerCleanCopy
                               ? "Keep the link as copied and offer a clean copy in the notch."
                               : "Replace the copied link with the clean one right away.") {
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
                              detail: "Press ⌘C twice quickly to open the clipboard history in the notch.",
                              isOn: $settings.copyTwiceToOpen, testID: "setting-copyTwiceToOpen")
                SettingToggle(symbol: "speaker.wave.2.fill", color: .pink, title: "Capture Sound",
                              detail: "A soft click each time something new is added to the history.",
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
            PrivacyFooter(text: "History is stored only on this Mac. Concealed items (passwords) are never recorded.")
        }
    }

    private var pasteSection: some View {
        Section {
            SettingToggle(symbol: "cursorarrow.click.2", color: .blue, title: "Paste on Click",
                          detail: "Clicking an item pastes it into the app you were using. Needs Accessibility.",
                          isOn: $settings.pasteOnClick)
            SettingToggle(symbol: "number", color: .purple, title: "Paste with 1–9",
                          detail: "Press a number while the Clipboard tab is open to paste that item.",
                          isOn: $settings.pasteWithNumbers)
            ShortcutRow(key: HotKeyAction.pastePlainText.rawValue, symbol: "doc.plaintext.fill", color: .teal,
                        title: "Paste as Plain Text",
                        detail: "Paste the clipboard without formatting from any app. Needs Accessibility.")
                .disabled(!settings.hotkeysEnabled)
            if accessibilityGranted {
                SettingValueRow(symbol: "accessibility", color: .green, title: "Accessibility",
                                detail: "Lets DynaNotch press ⌘V in the frontmost app.",
                                value: "Granted", valueColor: .green)
            } else {
                SettingRow(symbol: "accessibility", color: .orange, title: "Accessibility",
                           detail: "Needed to paste into the frontmost app. Without it, items are only copied.") {
                    Button("Allow…") { Permissions.requestAccessibility() }
                }
            }
        } header: {
            Text("Pasting")
        } footer: {
            SettingsFooter("⌥-click an item to paste it as plain text.")
        }
        .disabled(!settings.clipboardEnabled)
    }

    private var ignoredSection: some View {
        Section {
            BundleIDListEditor(list: $settings.clipboardIgnoredApps, placeholder: "com.example.app")
        } header: {
            Text("Ignored Apps")
        } footer: {
            SettingsFooter("Copies made in these apps are never recorded. Password managers are ignored by default.")
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
                           detail: "Used when you type a query without a shortcut. Searches open in your browser.") {
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
                SettingsFooter("Type a shortcut before the query to use another engine, e.g. “gh swiftui”.")
            }
            Section {
                CustomEnginesEditor()
            } header: {
                Text("Custom Engines")
            } footer: {
                SettingsFooter("Put %@ where the search words go. Custom engines are used with their shortcut, or as the default engine.")
            }
            Section {
                BundleIDListEditor(list: $settings.launcherApps, placeholder: "com.apple.Safari")
            } header: {
                Text("Launcher Apps")
            } footer: {
                SettingsFooter("Pinned in the Launcher tab, in this order. Running apps and a search of /Applications are always shown too.")
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
                              detail: "Drag files onto the notch to park them, then drag them out into any app.",
                              isOn: $settings.shelfEnabled)
                SettingToggle(symbol: "arrow.up.forward.app.fill", color: .blue, title: "Remove After Dragging Out",
                              detail: "Take a file off the shelf once you've dragged it somewhere.",
                              isOn: $settings.shelfRemoveOnDragOut)
                    .disabled(!settings.shelfEnabled)
                SettingStackedRow(symbol: "clock.arrow.circlepath", color: .orange, title: "Keep Files",
                                  detail: "Take files off the shelf after this long. The files themselves are never deleted.") {
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
                PrivacyFooter(text: "The shelf only remembers where files are; it never copies or uploads them.")
            }
            Section("Popups") {
                SettingToggle(symbol: "arrow.down.circle.fill", color: .blue, title: "Downloads",
                              detail: "When a download starts and finishes in ~/Downloads.",
                              isOn: $settings.downloadActivity)
                SettingToggle(symbol: "externaldrive.fill", color: .gray, title: "Drive Mounted",
                              detail: "A popup with an Eject button when you connect a disk or USB stick.",
                              isOn: $settings.driveActivity)
                SettingToggle(symbol: "externaldrive.fill.badge.plus", color: .blue, title: "Offer to Install Apps",
                              detail: "When a disk image with an app opens, offer to copy the app to Applications.",
                              isOn: $settings.dmgInstallOffer, testID: "setting-dmgInstallOffer")
            }
            Section {
                SettingRow(symbol: "terminal.fill", color: .gray, title: "Long-Command Islands",
                           detail: zshHookInstalled
                               ? "Installed: long-running Terminal commands show a popup when they finish."
                               : "Adds a small hook to ~/.zshrc so long Terminal commands show a popup when they finish.") {
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
                            zshMessage = ok ? "Hook installed. It works in new Terminal windows."
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
                               ? "The hook only calls dynanotch://notify; the rest of ~/.zshrc is left untouched. zsh only."
                               : "Turn on Show in DynaNotch (General → Automation) to use this.")
            }
            .onAppear { zshHookInstalled = ShellHookInstaller.zshHookInstalled }
            RestoreDefaultsSection(keys: [
                SettingsKey.shelfEnabled, SettingsKey.shelfRemoveOnDragOut, SettingsKey.shelfRetention,
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
                                  ? "Captures are copied to the clipboard and also parked on the shelf."
                                  : "Turn on the File Shelf in Files & Utilities to use this.",
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
                SettingsFooter("Captures always go to the clipboard; with a folder they're also saved there as PNG files.")
            }
            Section {
                SettingRow(symbol: "camera.viewfinder", color: .mint, title: "Capture Area",
                           detail: "Select part of the screen; it's copied to the clipboard.") {
                    Button("Capture") { QuickActions.captureScreenshot() }
                }
                SettingRow(symbol: "eyedropper", color: .purple, title: "Pick a Color",
                           detail: "Click anywhere on screen to copy that colour.") {
                    Button("Pick") { QuickActions.pickColor() }
                }
                SettingRow(symbol: "record.circle.fill", color: .red, title: "Record Screen",
                           detail: "Starts a recording of the whole screen.") {
                    Button("Record") { QuickActions.recordScreen() }
                        .uiTestID("setting-recordScreen")
                }
                SettingRow(symbol: "rectangle.dashed.badge.record", color: .red, title: "Record Area",
                           detail: "Select part of the screen, then record just that area.") {
                    Button("Record") { QuickActions.recordArea() }
                        .uiTestID("setting-recordArea")
                }
            } header: {
                Text("Try It")
            } footer: {
                SettingsFooter("Capture Area and Pick a Color are also in the panel's ⋯ actions menu.")
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
