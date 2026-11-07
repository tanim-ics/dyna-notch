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
                              detail: "Track which apps you use, shown in the System tab. Pauses when you're away.",
                              isOn: $settings.screenTimeEnabled)
                SettingValueRow(symbol: "chart.bar.fill", color: .blue, title: "Today",
                                detail: "Time in apps since midnight.",
                                value: Format.countdown(screenTime.totalToday()))
                SettingRow(symbol: "trash.fill", color: .red, title: "Clear Screen Time Data",
                           detail: "Deletes every day you've tracked. Can't be undone.") {
                    InlineConfirmButton(title: "Clear…", confirmTitle: "Clear") { screenTime.clear() }
                }
            } header: {
                Text("Screen Time")
            } footer: {
                PrivacyFooter(text: "Stays on this Mac. Nothing is uploaded.")
            }
            Section {
                SettingToggle(symbol: "sparkles", color: .yellow, title: "Daily Wrap",
                              detail: "A short recap of your day in the notch.",
                              isOn: $settings.dailyWrap, testID: "setting-dailyWrap")
                SettingRow(symbol: "clock.fill", color: .orange, title: "Show At",
                           detail: "If you're away, it waits for you.") {
                    DatePicker("Show at", selection: wrapTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .uiTestID("setting-dailyWrapTime")
                }
                .disabled(!settings.dailyWrap)
                SettingToggle(symbol: "calendar", color: .blue, title: "Weekdays Only",
                              detail: "Skip Saturdays and Sundays.",
                              isOn: $settings.dailyWrapWeekdays, testID: "setting-dailyWrapWeekdays")
                    .disabled(!settings.dailyWrap)
                SettingRow(symbol: "play.fill", color: .green, title: "Show It Now",
                           detail: "See today's wrap so far.") {
                    Button("Show") { DailyWrapService.shared.showNow() }
                        .uiTestID("setting-dailyWrap-now")
                }
            } header: {
                Text("Daily Wrap")
            } footer: {
                PrivacyFooter(text: "Commits are counted on this Mac. Nothing is uploaded.")
            }
            RestoreDefaultsSection(keys: [SettingsKey.screenTimeEnabled, SettingsKey.dailyWrap,
                                          SettingsKey.dailyWrapMinutes, SettingsKey.dailyWrapWeekdays])
        }
    }

    /// dn.dailyWrapMinutes (minutes past midnight) as a time of day for the picker.
    private var wrapTime: Binding<Date> {
        Binding(get: {
            Calendar.current.date(byAdding: .minute, value: Int(settings.dailyWrapMinutes),
                                  to: Calendar.current.startOfDay(for: Date())) ?? Date()
        }, set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            settings.dailyWrapMinutes = Double((parts.hour ?? 18) * 60 + (parts.minute ?? 0))
        })
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
    @State private var agentHooksInstalled = ShellHookInstaller.agentHooksInstalled
    @State private var agentMessage: String?

    var body: some View {
        SettingsPageView(page: .aiUsage) {
            aiSection
            warningsSection
            agentSection
            costHookSection
            hookSection
            RestoreDefaultsSection(keys: [
                SettingsKey.agentIsland, SettingsKey.agentStatus, SettingsKey.agentTimeout,
                SettingsKey.aiUsageEnabled, SettingsKey.aiLimitWarnings, SettingsKey.aiLimitWarnPercent,
                SettingsKey.aiMenuBarReadout, SettingsKey.aiHidePersonalInfo,
            ])
        }
    }

    private var aiSection: some View {
        Section {
            SettingToggle(symbol: "sparkles", color: .purple, title: "AI Usage Tab",
                          detail: "Claude Code and Codex usage in the panel.",
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
                           detail: "Updates every minute. Refresh to update now.") {
                    Button("Refresh Now") { usage.refresh() }
                }
            }
            .disabled(!settings.aiUsageEnabled)
        } header: {
            Text("AI Usage")
        } footer: {
            PrivacyFooter(text: "Read from local logs. Nothing is uploaded.")
        }
    }

    private var warningsSection: some View {
        Section {
            SettingToggle(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Limit Warnings",
                          detail: "A heads-up when you're close to a limit.",
                          isOn: $settings.aiLimitWarnings, testID: "setting-aiLimitWarnings")
            IntSliderRow(symbol: "gauge.with.dots.needle.67percent", color: .orange, title: "Warn At",
                         detail: "Warn at this much use.",
                         value: $settings.aiLimitWarnPercent, range: 50...95, step: 5, format: { "\($0)%" },
                         testID: "setting-aiLimitWarnPercent")
                .disabled(!settings.aiLimitWarnings)
            SettingToggle(symbol: "menubar.rectangle", color: .purple, title: "Menu Bar Readout",
                          detail: "Show your current usage in the menu bar.",
                          isOn: $settings.aiMenuBarReadout, testID: "setting-aiMenuBarReadout")
            SettingToggle(symbol: "eye.slash.fill", color: .gray, title: "Hide Personal Info",
                          detail: "Hide project names, handy when sharing your screen.",
                          isOn: $settings.aiHidePersonalInfo, testID: "setting-aiHidePersonalInfo")
        } header: {
            Text("Warnings & Display")
        }
        .disabled(!settings.aiUsageEnabled)
    }

    private var agentSection: some View {
        Section {
            SettingToggle(symbol: "sparkle", color: .orange, title: "Agent Island",
                          detail: "Answer Claude Code's permission requests from the notch. Off: answer in the terminal.",
                          isOn: $settings.agentIsland, testID: "setting-agentIsland")
            SettingToggle(symbol: "text.bubble.fill", color: .blue, title: "Session Status in the Pill",
                          detail: "See what Claude is working on and when it's done.",
                          isOn: $settings.agentStatus, testID: "setting-agentStatus")
                .disabled(!settings.agentIsland)
            SliderRow(symbol: "hourglass", color: .gray, title: "Answer Within",
                      detail: "After this, Claude asks in the terminal instead.",
                      value: $settings.agentTimeout, range: 15...300, step: 15,
                      format: { "\(Int($0)) s" }, testID: "setting-agentTimeout")
                .disabled(!settings.agentIsland)
            SettingRow(symbol: "link", color: .purple, title: "Claude Code Hooks",
                       detail: agentHooksInstalled
                           ? "Installed. Claude Code now talks to the notch."
                           : "Adds hooks to Claude Code's settings (with a backup). Needed once.") {
                if agentHooksInstalled {
                    Button("Remove") {
                        ShellHookInstaller.removeAgentHooks()
                        agentHooksInstalled = ShellHookInstaller.agentHooksInstalled
                        agentMessage = agentHooksInstalled ? "Could not remove the hooks." : "Hooks removed."
                    }
                    .uiTestID("setting-agentHooks-remove")
                } else {
                    Button("Install") {
                        let ok = ShellHookInstaller.installAgentHooks(timeout: Int(settings.agentTimeout))
                        agentHooksInstalled = ShellHookInstaller.agentHooksInstalled
                        agentMessage = ok ? "Done. Works from your next Claude Code session."
                                          : "Couldn't install. Is ~/.claude/settings.json valid JSON?"
                    }
                    .uiTestID("setting-agentHooks-install")
                }
            }
            if let message = agentMessage {
                Label(message, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Agent Island")
        } footer: {
            PrivacyFooter(text: "Everything stays on this Mac.")
        }
        .onAppear { agentHooksInstalled = ShellHookInstaller.agentHooksInstalled }
    }

    private var costHookSection: some View {
        Section {
            SettingRow(symbol: "dollarsign.circle.fill", color: .green, title: "Session Cost After Each Reply",
                       detail: costHookInstalled
                           ? "Installed. You'll see each session's cost when Claude finishes."
                           : "Show each Claude Code session's cost in the notch.") {
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
                        hookMessage = ok ? "Done. Works from Claude's next reply."
                                         : "Couldn't install. Is ~/.claude/settings.json valid JSON?"
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
            SettingsFooter("Your other hooks are left alone.")
        }
        .onAppear { costHookInstalled = ShellHookInstaller.claudeCostHookInstalled }
    }

    private var hookSection: some View {
        Section {
            SettingStackedRow(symbol: "terminal.fill", color: .gray, title: "Notify Command",
                              detail: "Use it in a Claude Code hook or any script to post a message.") {
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
            SettingsFooter("You can set title, body, symbol and duration (1–30 s).")
        }
    }
}
