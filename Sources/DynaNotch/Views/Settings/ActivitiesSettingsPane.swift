import SwiftUI
import DynaNotchCore

struct ActivitiesSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var focus: FocusService

    var body: some View {
        Form {
            powerSection
            devicesSection
            focusSection
            systemSection
        }
        .formStyle(.grouped)
        .navigationTitle("Live Activities")
    }

    private var powerSection: some View {
        Section("Power") {
            Toggle("Charging", isOn: $settings.chargingActivity)
                .toggleStyle(.switch)
            Toggle("Low battery", isOn: $settings.lowBatteryActivity)
                .toggleStyle(.switch)
        }
    }

    private var devicesSection: some View {
        Section("Devices") {
            Toggle("Bluetooth devices", isOn: $settings.bluetoothActivity)
                .toggleStyle(.switch)
            Button("Open Bluetooth Settings…") { Permissions.openBluetoothSettings() }
        }
    }

    private var focusSection: some View {
        Section("Focus") {
            Toggle("Focus changes", isOn: $settings.focusActivity)
                .toggleStyle(.switch)
            if !focus.isReadable {
                HStack {
                    Text("Focus detection needs Full Disk Access")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings…") { Permissions.openFullDiskAccessSettings() }
                }
            }
        }
    }

    private var systemSection: some View {
        Section {
            Toggle("Downloads (start / finish in ~/Downloads)", isOn: $settings.downloadActivity)
                .toggleStyle(.switch)
            Toggle("Camera & microphone in use", isOn: $settings.privacyActivity)
                .toggleStyle(.switch)
            Toggle("Caps Lock", isOn: $settings.capsLockActivity)
                .toggleStyle(.switch)
            Toggle("Notifications from scripts (dynanotch://notify)", isOn: $settings.notifyActivity)
                .toggleStyle(.switch)
        } header: {
            Text("System")
        }
    }
}
