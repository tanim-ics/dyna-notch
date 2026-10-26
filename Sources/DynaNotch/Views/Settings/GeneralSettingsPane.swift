import SwiftUI
import AppKit
import Combine
import DynaNotchCore

struct GeneralSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var focus: FocusService

    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var accessibilityGranted: Bool = Permissions.accessibilityGranted

    private let permissionTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            startupSection
            displaySection
            permissionsSection
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onReceive(permissionTimer) { _ in
            accessibilityGranted = Permissions.accessibilityGranted
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
            Toggle("Launch at login", isOn: launchBinding)
                .toggleStyle(.switch)
            Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                .toggleStyle(.switch)
            Toggle("Haptic feedback", isOn: $settings.hapticFeedback)
                .toggleStyle(.switch)
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Show island on", selection: $settings.displayMode) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Toggle("Hide in full screen apps", isOn: $settings.hideInFullscreen)
                .toggleStyle(.switch)
            Toggle("Show on displays without a notch", isOn: $settings.showOnNonNotchDisplays)
                .toggleStyle(.switch)
        }
    }

    private var permissionsSection: some View {
        Section("Permissions") {
            PermissionRow(title: "Accessibility",
                          detail: "Replace the system volume and brightness HUD",
                          granted: accessibilityGranted,
                          buttonTitle: "Grant…") {
                Permissions.requestAccessibility()
                Permissions.openAccessibilitySettings()
            }
            PermissionRow(title: "Calendar",
                          detail: "Upcoming events in the island",
                          granted: calendar.access == .granted,
                          buttonTitle: calendar.access == .notDetermined ? "Grant…" : "Open Settings…") {
                if calendar.access == .notDetermined {
                    calendar.requestAccess()
                } else {
                    Permissions.openCalendarSettings()
                }
            }
            PermissionRow(title: "Full Disk Access",
                          detail: "Needed to detect the current Focus mode",
                          granted: focus.isReadable,
                          buttonTitle: "Open Settings…") {
                Permissions.openFullDiskAccessSettings()
            }
        }
    }
}
