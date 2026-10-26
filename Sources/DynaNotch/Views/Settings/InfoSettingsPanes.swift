import SwiftUI
import AppKit
import DynaNotchCore

// MARK: - Activity

struct ActivitySettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var screenTime = ScreenTimeService.shared

    var body: some View {
        SettingsPageView(page: .activity) {
            Section {
                SettingToggle(symbol: "hourglass", color: .green, title: "Track Screen Time",
                              detail: "Records which app is in front, shown in the System tab. Pauses while idle or locked.",
                              isOn: $settings.screenTimeEnabled)
                SettingValueRow(symbol: "chart.bar.fill", color: .blue, title: "Today",
                                detail: "Total time in front of apps since midnight.",
                                value: Format.countdown(screenTime.totalToday()))
                SettingRow(symbol: "trash.fill", color: .red, title: "Clear Screen Time Data",
                           detail: "Deletes every recorded day. This can't be undone.") {
                    InlineConfirmButton(title: "Clear…", confirmTitle: "Clear") { screenTime.clear() }
                }
            } header: {
                Text("Screen Time")
            } footer: {
                PrivacyFooter(text: "Stays on this Mac. Nothing is uploaded.")
            }
            RestoreDefaultsSection(keys: [SettingsKey.screenTimeEnabled])
        }
    }
}

// MARK: - AI Usage

struct AIUsageSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var usage = AIUsageService.shared

    private static let hookExample =
        "open -g \"dynanotch://notify?title=Claude%20Code&body=Waiting%20for%20you&symbol=sparkles\""

    @State private var copied = false
    @State private var costHookInstalled = ShellHookInstaller.claudeCostHookInstalled
    @State private var hookMessage: String?

    var body: some View {
        SettingsPageView(page: .aiUsage) {
            aiSection
            warningsSection
            costHookSection
            hookSection
            RestoreDefaultsSection(keys: [
                SettingsKey.aiUsageEnabled, SettingsKey.aiLimitWarnings, SettingsKey.aiLimitWarnPercent,
                SettingsKey.aiMenuBarReadout, SettingsKey.aiHidePersonalInfo,
            ])
        }
    }

    private var aiSection: some View {
        Section {
            SettingToggle(symbol: "sparkles", color: .purple, title: "AI Usage Tab",
                          detail: "Token usage, 5-hour blocks and estimated cost in the panel.",
                          isOn: $settings.aiUsageEnabled)
            Group {
                SettingValueRow(symbol: "c.circle.fill", color: .orange, title: "Claude Code",
                                detail: "Session logs in ~/.claude/projects.",
                                value: usage.hasClaudeData ? "Found" : "No logs found",
                                valueColor: usage.hasClaudeData ? .green : .secondary)
                SettingValueRow(symbol: "chevron.left.forwardslash.chevron.right", color: .gray, title: "Codex",
                                detail: "Rate-limit windows from ~/.codex/sessions.",
                                value: usage.hasCodexData ? "Found" : "No logs found",
                                valueColor: usage.hasCodexData ? .green : .secondary)
                SettingRow(symbol: "arrow.clockwise", color: .blue, title: "Refresh",
                           detail: "Logs are re-read every minute; refresh to update right now.") {
                    Button("Refresh Now") { usage.refresh() }
                }
            }
            .disabled(!settings.aiUsageEnabled)
        } header: {
            Text("AI Usage")
        } footer: {
            PrivacyFooter(text: "Read locally from the log files; nothing is uploaded.")
        }
    }

    private var warningsSection: some View {
        Section {
            SettingToggle(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Limit Warnings",
                          detail: "A popup when a Claude 5-hour block or a Codex limit passes the threshold, and before it runs out.",
                          isOn: $settings.aiLimitWarnings, testID: "setting-aiLimitWarnings")
            IntSliderRow(symbol: "gauge.with.dots.needle.67percent", color: .orange, title: "Warn At",
                         detail: "How much of a limit may be used before the warning appears.",
                         value: $settings.aiLimitWarnPercent, range: 50...95, step: 5, format: { "\($0)%" },
                         testID: "setting-aiLimitWarnPercent")
                .disabled(!settings.aiLimitWarnings)
            SettingToggle(symbol: "menubar.rectangle", color: .purple, title: "Menu Bar Readout",
                          detail: "Shows the current block's usage next to the DynaNotch menu bar icon.",
                          isOn: $settings.aiMenuBarReadout, testID: "setting-aiMenuBarReadout")
            SettingToggle(symbol: "eye.slash.fill", color: .gray, title: "Hide Personal Info",
                          detail: "Hide project names and paths in the AI Usage tab, e.g. while sharing your screen.",
                          isOn: $settings.aiHidePersonalInfo, testID: "setting-aiHidePersonalInfo")
        } header: {
            Text("Warnings & Display")
        }
        .disabled(!settings.aiUsageEnabled)
    }

    private var costHookSection: some View {
        Section {
            SettingRow(symbol: "dollarsign.circle.fill", color: .green, title: "Session Cost After Each Reply",
                       detail: costHookInstalled
                           ? "Installed: Claude Code shows what each session has cost in the notch when it finishes replying."
                           : "Adds a Stop hook to ~/.claude/settings.json that shows the session's cost in the notch.") {
                if costHookInstalled {
                    Button("Remove") {
                        ShellHookInstaller.removeClaudeCostHook()
                        costHookInstalled = ShellHookInstaller.claudeCostHookInstalled
                        hookMessage = costHookInstalled ? "Could not remove the hook." : "Hook removed."
                    }
                    .uiTestID("setting-claudeCostHook-remove")
                } else {
                    Button("Install") {
                        let ok = ShellHookInstaller.installClaudeCostHook()
                        costHookInstalled = ShellHookInstaller.claudeCostHookInstalled
                        hookMessage = ok ? "Hook installed. It runs from the next Claude Code reply."
                                         : "Could not install the hook — is ~/.claude/settings.json valid JSON?"
                    }
                    .uiTestID("setting-claudeCostHook-install")
                }
            }
            if let message = hookMessage {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Claude Code Hook")
        } footer: {
            SettingsFooter("Your other hooks are left untouched. The cost is estimated locally from the session log.")
        }
        .onAppear { costHookInstalled = ShellHookInstaller.claudeCostHookInstalled }
    }

    private var hookSection: some View {
        Section {
            SettingStackedRow(symbol: "terminal.fill", color: .gray, title: "Notify Command",
                              detail: "Use as a Claude Code hook (Notification or Stop in ~/.claude/settings.json) or from any script to show a message in the notch.") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AIUsageSettingsPane.hookExample)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                    Button(copied ? "Copied" : "Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AIUsageSettingsPane.hookExample, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }
                }
            }
        } header: {
            Text("Notifications from Scripts")
        } footer: {
            SettingsFooter("Parameters: title, body, symbol (SF Symbol name), duration (1–30 s).")
        }
    }
}
