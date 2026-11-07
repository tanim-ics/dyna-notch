import SwiftUI
import AppKit
import Combine
import Foundation
import DynaNotchCore

struct GeneralSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var suggestions: [SettingsSuggestion] = []

    private let poll = SettingsTicker.tick

    var body: some View {
        SettingsPageView(page: .general) {
            if !suggestions.isEmpty { suggestionsSection }
            startupSection
            clockSection
            introSection
            automationSection
            recoverySection
            RestoreDefaultsSection(keys: [
                SettingsKey.showMenuBarIcon, SettingsKey.timeFormat, SettingsKey.helloIntro, SettingsKey.notifyActivity,
            ])
        }
        .onAppear(perform: refresh)
        .onReceive(poll) { _ in refresh() }
    }

    private func refresh() {
        let current = SettingsSuggestions.current(settings: settings)
        if current.map(\.id) != suggestions.map(\.id) { suggestions = current }
    }

    private var suggestionsSection: some View {
        Section {
            ForEach(suggestions) { s in
                SettingRow(symbol: s.symbol, color: s.color, title: s.title, detail: s.detail) {
                    Button(s.actionTitle) {
                        s.action()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } header: {
            Text("Suggestions")
        } footer: {
            SettingsFooter("Things left to set up. Each one goes away once it's done.")
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { launchAtLogin }, set: { newValue in
            LaunchAtLogin.setEnabled(newValue)
            launchAtLogin = LaunchAtLogin.isEnabled
        })
    }

    private var startupSection: some View {
        Section("Startup") {
            SettingToggle(symbol: "power", color: .green, title: "Open at Login",
                          detail: "Open DynaNotch when you log in.",
                          isOn: launchBinding)
            SettingToggle(symbol: "menubar.rectangle", color: .gray, title: "Menu Bar Icon",
                          detail: "Hide it and you can still reach Settings from the panel's gear.",
                          isOn: $settings.showMenuBarIcon)
        }
    }

    private var clockSection: some View {
        Section("Clock") {
            SettingRow(symbol: "clock.fill", color: .orange, title: "Time Format",
                       detail: "For the clocks in the panel and the pill.") {
                Picker("Time format", selection: $settings.timeFormat) {
                    ForEach(TimeFormat.allCases, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var introSection: some View {
        Section("Hello Intro") {
            SettingRow(symbol: "hand.wave.fill", color: .yellow, title: "Hello Intro at Launch",
                       detail: "A little handwritten “hello” each time the app starts.") {
                HStack(spacing: 8) {
                    Button {
                        WelcomeController.shared.show(greetingOnly: true)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("Play the hello animation now")
                    Toggle("", isOn: $settings.helloIntro)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }
        }
    }

    static let exampleNotifyLink = "dynanotch://notify?title=Hello&body=From%20a%20script&symbol=sparkles"

    private var automationSection: some View {
        Section {
            SettingToggle(symbol: "bubble.left.and.text.bubble.right.fill", color: .purple, title: "Show in DynaNotch",
                          detail: "Let scripts, Shortcuts and links post a message to the notch.",
                          isOn: $settings.notifyActivity, testID: "setting-notifyActivity")
            SettingRow(symbol: "link", color: .blue, title: "Example Link",
                       detail: "Run it in Terminal with “open -g …” or use it in Shortcuts.") {
                CopyButton(title: "Copy Example Link") { GeneralSettingsPane.exampleNotifyLink }
                    .uiTestID("setting-copyNotifyLink")
            }
            .disabled(!settings.notifyActivity)
        } header: {
            Text("Automation")
        } footer: {
            SettingsFooter("You can set title, body, symbol and duration.")
        }
    }

    private var recoverySection: some View {
        Section {
            SettingRow(symbol: "arrow.clockwise", color: .blue, title: "Restart DynaNotch",
                       detail: "Try this if the island gets stuck or after allowing a permission.") {
                Button("Restart") { GeneralSettingsPane.restart() }
            }
            SettingRow(symbol: "xmark.octagon.fill", color: .red, title: "Quit DynaNotch",
                       detail: "Closes the island and the menu bar icon until you open the app again.") {
                DestructiveButton(title: "Quit") { NSApp.terminate(nil) }
            }
            ShortcutRow(key: HotKeyAction.emergencyQuit.rawValue, symbol: "keyboard.fill", color: .red,
                        title: "Emergency Quit Shortcut",
                        detail: "Quit from anywhere, even if the island is in the way.")
                .disabled(!settings.hotkeysEnabled)
            SettingRow(symbol: "bolt.horizontal.circle.fill", color: .red, title: "Force Quit",
                       detail: "Forces DynaNotch to close if it stops responding.") {
                InlineConfirmButton(title: "Force Quit…", confirmTitle: "Force Quit") { exit(0) }
                    .uiTestID("setting-forceQuit")
            }
        } header: {
            Text("Recovery")
        } footer: {
            SettingsFooter("Change or turn off any shortcut under Behavior → Keyboard Shortcuts.")
        }
    }

    /// Relaunches the bundle shortly after this instance quits.
    static func restart() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.8; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            return
        }
        NSApp.terminate(nil)
    }
}
