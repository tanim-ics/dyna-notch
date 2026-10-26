import SwiftUI
import DynaNotchCore

struct CalendarSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        Form {
            calendarSection
            accessSection
        }
        .formStyle(.grouped)
        .navigationTitle("Calendar")
    }

    private var calendarSection: some View {
        Section("Calendar") {
            Toggle("Enable calendar", isOn: $settings.calendarEnabled)
                .toggleStyle(.switch)
            Toggle("Show events in expanded view", isOn: $settings.expandedShowsCalendar)
                .toggleStyle(.switch)
            Toggle("Alert before events", isOn: $settings.calendarActivity)
                .toggleStyle(.switch)
            Stepper(value: $settings.calendarLeadMinutes, in: 1...30) {
                LabeledContent("Alert lead time", value: "\(settings.calendarLeadMinutes) min")
            }
            .disabled(!settings.calendarActivity)
        }
    }

    private var accessSection: some View {
        Section("Access") {
            LabeledContent("Status", value: accessTitle)
            if calendar.access == .notDetermined {
                Button("Connect Calendar") { calendar.requestAccess() }
            } else if calendar.access != .granted {
                Button("Open Privacy Settings…") { Permissions.openCalendarSettings() }
            }
        }
    }

    private var accessTitle: String {
        if calendar.access == .granted { return "Granted" }
        if calendar.access == .notDetermined { return "Not requested" }
        return "Denied"
    }
}
