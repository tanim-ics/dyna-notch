import Foundation
import SwiftUI
import AppKit
import Combine
import DynaNotchCore

// MARK: - Knock

struct KnockSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    @ObservedObject private var knock = KnockMonitor.shared
    @State private var axGranted = Permissions.accessibilityGranted
    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPageView(page: .knock) {
            Section {
                SettingToggle(symbol: "hand.tap.fill", color: .pink, title: "Knock",
                              detail: "Tap a modifier key on its own 1, 2 or 3 times to run an action. Needs Accessibility.",
                              isOn: $settings.knockEnabled, testID: "setting-knockEnabled")
                SettingRow(symbol: "keyboard.fill", color: .gray, title: "Knock Key",
                           detail: "The key you tap. Holding it or using it in a shortcut never counts.") {
                    Picker("Knock key", selection: $settings.knockKey) {
                        ForEach(KnockKey.allCases, id: \.self) { key in
                            Text(key.title).tag(key)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .uiTestID("setting-knockKey")
                }
                .disabled(!settings.knockEnabled)
            } header: {
                Text("Knock")
            }
            Section {
                ForEach(1...3, id: \.self) { taps in
                    SettingRow(symbol: "\(taps).circle.fill", color: .pink, title: tapTitle(taps),
                               detail: "What happens when you tap \(settings.knockKey.title) \(tapWord(taps)).") {
                        Picker(tapTitle(taps), selection: actionBinding(taps)) {
                            ForEach(KnockAction.allCases, id: \.self) { action in
                                Text(action.title).tag(action)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .uiTestID("setting-knock-\(taps)")
                    }
                }
                SettingValueRow(symbol: "waveform.path.ecg", color: knock.isRunning ? .green : .gray, title: "Last Knock",
                                detail: knock.isRunning ? "Tap the knock key now — what DynaNotch noticed shows here."
                                    : (settings.knockEnabled ? "Not listening yet. Check the Accessibility permission below."
                                                             : "Turn on Knock to start listening."),
                                value: lastKnockText)
                SettingRow(symbol: "play.fill", color: .blue, title: "Try It",
                           detail: "Runs the action for 1, 2 or 3 knocks as if you had tapped the key.") {
                    HStack(spacing: 4) {
                        ForEach(1...3, id: \.self) { n in
                            Button("\(n)×") { knock.simulate(count: n) }
                                .uiTestID("setting-knock-try-\(n)")
                        }
                    }
                }
            } header: {
                Text("Actions")
            }
            .disabled(!settings.knockEnabled)
            Section {
                PermissionRow(symbol: "accessibility", color: .blue, title: "Accessibility",
                              detail: "Lets DynaNotch notice modifier-key taps while other apps are in front.",
                              status: axGranted ? .granted : .denied, anchor: "Privacy_Accessibility",
                              request: nil)
            } header: {
                Text("Permission")
            } footer: {
                PrivacyFooter(text: "Only modifier taps are counted; no keystrokes are recorded or stored.")
            }
            RestoreDefaultsSection(keys: [SettingsKey.knockEnabled, SettingsKey.knockKey, SettingsKey.knockActions])
        }
        .onReceive(poll) { _ in axGranted = Permissions.accessibilityGranted }
    }

    private var lastKnockText: String {
        let n = knock.lastKnock
        guard n > 0 else { return "No knock yet" }
        let taps = "\(n) tap\(n == 1 ? "" : "s")"
        return knock.lastAction.isEmpty ? taps : "\(taps) → \(knock.lastAction)"
    }

    private func tapTitle(_ taps: Int) -> String {
        switch taps {
        case 1: return "Single Knock"
        case 2: return "Double Knock"
        default: return "Triple Knock"
        }
    }

    private func tapWord(_ taps: Int) -> String {
        switch taps {
        case 1: return "once"
        case 2: return "twice"
        default: return "three times"
        }
    }

    private func actionBinding(_ taps: Int) -> Binding<KnockAction> {
        Binding(get: {
            KnockAction.parseMap(settings.knockActions)[taps] ?? .none
        }, set: { action in
            var map = KnockAction.parseMap(settings.knockActions)
            map[taps] = action
            settings.knockActions = KnockAction.serializeMap(map)
        })
    }
}

// MARK: - All Tools

struct ToolCard: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    let page: SettingsPage
    let keyPath: ReferenceWritableKeyPath<AppSettings, Bool>
}

struct AllToolsSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @State private var query = ""

    static let tools: [ToolCard] = [
        ToolCard(id: "nowPlaying", title: "Now Playing", detail: "Music beside the notch with controls.",
                 symbol: "music.note", color: .pink, page: .nowPlaying, keyPath: \.nowPlayingEnabled),
        ToolCard(id: "lyrics", title: "Synced Lyrics", detail: "Lyrics in time with the song. Uses the network.",
                 symbol: "quote.bubble.fill", color: .indigo, page: .nowPlaying, keyPath: \.lyricsEnabled),
        ToolCard(id: "desktopLyrics", title: "Desktop Lyrics", detail: "The current line floating on your desktop.",
                 symbol: "text.aligncenter", color: .purple, page: .nowPlaying, keyPath: \.desktopLyrics),
        ToolCard(id: "listeningHistory", title: "Listening History", detail: "Songs you played, kept on this Mac.",
                 symbol: "clock.arrow.circlepath", color: .pink, page: .nowPlaying, keyPath: \.listeningHistory),
        ToolCard(id: "hud", title: "Volume & Brightness", detail: "Notch popups instead of the system HUD.",
                 symbol: "speaker.wave.2.fill", color: .gray, page: .hud, keyPath: \.hudEnabled),
        ToolCard(id: "timer", title: "Timer in the Notch", detail: "A ring and time left while a timer runs.",
                 symbol: "timer", color: .orange, page: .timer, keyPath: \.showCompactTimer),
        ToolCard(id: "lookAway", title: "Look Away", detail: "20-20-20 eye break reminders.",
                 symbol: BreakKind.lookAway.symbol, color: .blue, page: .timer, keyPath: \.breakLookAway),
        ToolCard(id: "standUp", title: "Stand Up", detail: "A nudge to get up and move.",
                 symbol: BreakKind.standUp.symbol, color: .green, page: .timer, keyPath: \.breakStandUp),
        ToolCard(id: "drinkWater", title: "Drink Water", detail: "Reminders to stay hydrated.",
                 symbol: BreakKind.drinkWater.symbol, color: .cyan, page: .timer, keyPath: \.breakDrinkWater),
        ToolCard(id: "clipboard", title: "Clipboard History", detail: "Paste anything you copied recently.",
                 symbol: "doc.on.clipboard.fill", color: .teal, page: .clipboard, keyPath: \.clipboardEnabled),
        ToolCard(id: "copyTwice", title: "Copy Twice to Open", detail: "⌘C ⌘C opens the clipboard history.",
                 symbol: "doc.on.doc.fill", color: .teal, page: .clipboard, keyPath: \.copyTwiceToOpen),
        ToolCard(id: "shelf", title: "File Shelf", detail: "Park files on the notch, drag them out later.",
                 symbol: "tray.full.fill", color: .cyan, page: .files, keyPath: \.shelfEnabled),
        ToolCard(id: "downloads", title: "Download Popups", detail: "When downloads start and finish.",
                 symbol: "arrow.down.circle.fill", color: .blue, page: .files, keyPath: \.downloadActivity),
        ToolCard(id: "dmg", title: "Install from Disk Images", detail: "Offers to copy the app when a .dmg opens.",
                 symbol: "externaldrive.fill.badge.plus", color: .gray, page: .files, keyPath: \.dmgInstallOffer),
        ToolCard(id: "weather", title: "Weather", detail: "Conditions on the Home tab. Uses the network.",
                 symbol: "cloud.sun.fill", color: .blue, page: .home, keyPath: \.weatherEnabled),
        ToolCard(id: "calendar", title: "Calendar", detail: "Up Next and alerts before events.",
                 symbol: "calendar", color: .red, page: .calendar, keyPath: \.calendarEnabled),
        ToolCard(id: "meetingAlert", title: "Meeting Alerts", detail: "A big alert with a Join button.",
                 symbol: "video.fill", color: .green, page: .calendar, keyPath: \.meetingAlert),
        ToolCard(id: "nextMeeting", title: "Next Meeting in Menu Bar", detail: "Your next meeting's time in the menu bar.",
                 symbol: "menubar.arrow.up.rectangle", color: .red, page: .calendar, keyPath: \.nextMeetingInMenuBar),
        ToolCard(id: "aiUsage", title: "AI Usage", detail: "Claude Code and Codex usage from local logs.",
                 symbol: "sparkles", color: .purple, page: .aiUsage, keyPath: \.aiUsageEnabled),
        ToolCard(id: "aiMenuBar", title: "AI Usage in Menu Bar", detail: "Your 5-hour block at a glance.",
                 symbol: "gauge.with.dots.needle.50percent", color: .purple, page: .aiUsage, keyPath: \.aiMenuBarReadout),
        ToolCard(id: "screenTime", title: "Screen Time", detail: "Time per app today, kept on this Mac.",
                 symbol: "hourglass", color: .green, page: .activity, keyPath: \.screenTimeEnabled),
        ToolCard(id: "knock", title: "Knock", detail: "Tap a modifier key to run an action.",
                 symbol: "hand.tap.fill", color: .pink, page: .knock, keyPath: \.knockEnabled),
        ToolCard(id: "hotkeys", title: "Keyboard Shortcuts", detail: "Global shortcuts for the panel and actions.",
                 symbol: "keyboard.fill", color: .gray, page: .behavior, keyPath: \.hotkeysEnabled),
        ToolCard(id: "edgeGlow", title: "Edge Glow", detail: "The screen edge glows when an alert appears.",
                 symbol: "rectangle.dashed", color: .orange, page: .popups, keyPath: \.edgeGlow),
        ToolCard(id: "capsLock", title: "Caps Lock Popup", detail: "Shows when Caps Lock turns on or off.",
                 symbol: "capslock.fill", color: .green, page: .popups, keyPath: \.capsLockActivity),
        ToolCard(id: "privacy", title: "Camera & Mic Guard", detail: "A popup when an app uses them.",
                 symbol: "video.fill", color: .green, page: .popups, keyPath: \.privacyActivity),
        ToolCard(id: "quietFocus", title: "Quiet During Focus", detail: "Hold back popups while Focus is on.",
                 symbol: "moon.zzz.fill", color: .indigo, page: .popups, keyPath: \.quietDuringFocus),
        ToolCard(id: "charging", title: "Charging Popups", detail: "Level when you plug in or unplug.",
                 symbol: "bolt.fill", color: .green, page: .battery, keyPath: \.chargingActivity),
        ToolCard(id: "batteryMenuBar", title: "Battery in Menu Bar", detail: "Your battery level in the menu bar.",
                 symbol: "battery.75percent", color: .green, page: .battery, keyPath: \.batteryInMenuBar),
        ToolCard(id: "drain", title: "Battery Drain Warnings", detail: "Flags apps draining the battery.",
                 symbol: "exclamationmark.triangle.fill", color: .orange, page: .battery, keyPath: \.drainWarnings),
        ToolCard(id: "bluetooth", title: "Device Popups", detail: "AirPods and accessories connecting.",
                 symbol: "airpods", color: .blue, page: .connectivity, keyPath: \.bluetoothActivity),
        ToolCard(id: "screenPrivacy", title: "Screen Sharing Privacy", detail: "Hide the island from recordings.",
                 symbol: "rectangle.dashed.badge.record", color: .red, page: .behavior, keyPath: \.screenSharingPrivacy),
    ]

    private var filtered: [ToolCard] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return AllToolsSettingsPane.tools }
        return AllToolsSettingsPane.tools.filter { tool in
            q.split(separator: " ").allSatisfy { word in
                (tool.title + " " + tool.detail + " " + tool.page.title)
                    .range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        SettingsPageView(page: .allTools) {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search tools", text: $query, prompt: Text("Search tools"))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .uiTestID("allTools-search")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                    Text("\(AllToolsSettingsPane.tools.filter { settings[keyPath: $0.keyPath] }.count) of \(AllToolsSettingsPane.tools.count) on")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Section {
                if filtered.isEmpty {
                    Text("No tools match “\(query)”.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(filtered) { tool in
                            ToolCardView(tool: tool, isOn: Binding(get: { settings[keyPath: tool.keyPath] },
                                                                   set: { settings[keyPath: tool.keyPath] = $0 }))
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                SettingsFooter("Click a tool's name to open its page with all its settings.")
            }
        }
    }
}

struct ToolCardView: View {
    let tool: ToolCard
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SettingsIcon(symbol: tool.symbol, color: isOn ? tool.color : .gray, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    SettingsNavigator.shared.go(tool.page)
                } label: {
                    HStack(spacing: 3) {
                        Text(tool.title).fontWeight(.medium).lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(tool.page.title) settings")
                .uiTestID("tool-open-\(tool.id)")
                Text(tool.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .uiTestID("tool-\(tool.id)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}
