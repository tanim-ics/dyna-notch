import SwiftUI
import DynaNotchCore

struct CalendarSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        SettingsPageView(page: .calendar) {
            accessSection
            calendarSection
            meetingSection
            calendarsSection
            RestoreDefaultsSection(keys: [
                SettingsKey.calendarEnabled, SettingsKey.expandedShowsCalendar, SettingsKey.calendarActivity,
                SettingsKey.calendarLeadMinutes, SettingsKey.meetingAlert, SettingsKey.meetingAlertMinutes,
                SettingsKey.meetingOnlyWithLink, SettingsKey.calendarHotkeys, SettingsKey.hiddenCalendars,
                SettingsKey.nextMeetingInMenuBar,
            ])
        }
    }

    private var calendarSection: some View {
        Section("Events") {
            SettingToggle(symbol: "calendar", color: .red, title: "Calendar",
                          detail: "Use the calendars from the Calendar app.",
                          isOn: $settings.calendarEnabled)
            Group {
                SettingToggle(symbol: "list.bullet.rectangle.fill", color: .orange, title: "Events in the Panel",
                              detail: "Show your month and next events on Home.",
                              isOn: $settings.expandedShowsCalendar)
                SettingToggle(symbol: "bell.badge.fill", color: .red, title: "Alert Before Events",
                              detail: "A heads-up before an event starts.",
                              isOn: $settings.calendarActivity)
                StepperRow(symbol: "clock.fill", color: .orange, title: "Alert Lead Time",
                           detail: "How early you get the heads-up.",
                           value: $settings.calendarLeadMinutes, range: 1...30, format: SettingsFormat.minutes)
                    .disabled(!settings.calendarActivity)
            }
            .disabled(!settings.calendarEnabled)
        }
    }

    private var meetingSection: some View {
        Section {
            SettingToggle(symbol: "video.fill", color: .green, title: "Full-Screen Meeting Alert",
                          detail: "A big alert with a Join button for video calls.",
                          isOn: $settings.meetingAlert, testID: "setting-meetingAlert")
            SettingToggle(symbol: "link.badge.plus", color: .blue, title: "Only Meetings With a Join Link",
                          detail: "Only for events with a call link.",
                          isOn: $settings.meetingOnlyWithLink, testID: "setting-meetingOnlyWithLink")
                .disabled(!settings.meetingAlert)
            SettingRow(symbol: "clock.badge.exclamationmark.fill", color: .orange, title: "Show the Alert",
                       detail: settings.meetingAlertMinutes == 0
                           ? "At the start time."
                           : "\(settings.meetingAlertMinutes) min before the meeting starts.") {
                IntValueStepper(value: $settings.meetingAlertMinutes, range: 0...15,
                                format: { $0 == 0 ? "At start" : "\($0) min" })
            }
            .disabled(!settings.meetingAlert)
            SettingRow(symbol: "eye.fill", color: .blue, title: "Preview",
                       detail: "See what a meeting alert looks like.") {
                Button("Preview") { MeetingAlertController.shared.preview() }
            }
            SettingToggle(symbol: "menubar.arrow.up.rectangle", color: .red, title: "Next Meeting in the Menu Bar",
                          detail: "Your next meeting in the menu bar. Click to join.",
                          isOn: $settings.nextMeetingInMenuBar, testID: "setting-nextMeetingInMenuBar")
            SettingToggle(symbol: "keyboard.fill", color: .gray, title: "Shortcuts",
                          detail: "⌃⌥J joins your next meeting, ⌃⌥C opens Calendar.",
                          isOn: $settings.calendarHotkeys, testID: "setting-calendarHotkeys")
        } header: {
            Text("Meetings")
        }
        .disabled(!settings.calendarEnabled)
    }

    private var hiddenIDs: [String] {
        settings.hiddenCalendars.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func shownBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { !hiddenIDs.contains(id) }, set: { shown in
            var ids = hiddenIDs.filter { $0 != id }
            if !shown { ids.append(id) }
            settings.hiddenCalendars = ids.joined(separator: ",")
        })
    }

    private var calendarsSection: some View {
        Section {
            if calendar.calendars.isEmpty {
                SettingRow(symbol: "calendar.badge.exclamationmark", color: .gray, title: "No Calendars",
                           detail: calendar.access == .granted
                               ? "No calendars found in the Calendar app."
                               : "Allow calendar access to choose calendars.")
            } else {
                ForEach(Array(calendar.calendars.enumerated()), id: \.element.id) { index, cal in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(color(for: cal))
                            .frame(width: 12, height: 12)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cal.title)
                            Text(cal.source)
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        Spacer(minLength: 12)
                        Toggle("", isOn: shownBinding(cal.id))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .uiTestID("setting-calendar-\(index)")
                    }
                    .padding(.vertical, 1)
                }
            }
        } header: {
            Text("Calendars")
        } footer: {
            SettingsFooter("Turned-off calendars won't show up or alert you.")
        }
        .disabled(!settings.calendarEnabled)
    }

    private func color(for cal: CalendarInfo) -> Color {
        guard let hex = cal.colorHex else { return .blue }
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count >= 6, let v = UInt64(s.prefix(6), radix: 16) else { return .blue }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }

    private var accessSection: some View {
        Section {
            if calendar.access == .granted {
                SettingValueRow(symbol: "checkmark.circle.fill", color: .green, title: "Calendar Access",
                                detail: "DynaNotch can read your events.",
                                value: "Granted", valueColor: .green)
            } else {
                SettingRow(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Calendar Access",
                           detail: calendar.access == .notDetermined
                               ? "Allow access to see your events."
                               : "Access is off. Turn it on in System Settings → Calendars.") {
                    if calendar.access == .notDetermined {
                        Button("Allow…") { calendar.requestAccess() }
                    } else {
                        Button("Open…") { Permissions.openCalendarSettings() }
                    }
                }
            }
        } header: {
            Text("Access")
        } footer: {
            PrivacyFooter(text: "Your events never leave this Mac.")
        }
    }
}
