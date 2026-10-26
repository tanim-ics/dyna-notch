import SwiftUI
import DynaNotchCore

// MARK: - Battery

struct BatterySettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var battery: BatteryService
    @ObservedObject var devices = DeviceBatteryService.shared
    @AppStorage("dn.data.batteryHistoryRange") private var historyRange: String = "day"

    var body: some View {
        SettingsPageView(page: .battery) {
            statusSection
            popupsSection
            extrasSection
            RestoreDefaultsSection(keys: [
                SettingsKey.chargingActivity, SettingsKey.lowBatteryActivity,
                SettingsKey.lowBatteryThreshold, SettingsKey.fullChargeActivity, SettingsKey.unplugActivity,
                SettingsKey.fullChargeLevel, SettingsKey.batteryInMenuBar, SettingsKey.drainWarnings,
            ])
        }
    }

    private var mac: DeviceBattery? { devices.devices.first { $0.kind == .mac } }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            if let info = battery.info {
                SettingValueRow(symbol: info.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                                color: levelColor(info.level), title: "Battery Level",
                                detail: chargeDetail(info),
                                value: Format.percent(info.level),
                                valueColor: levelColor(info.level))
                SettingValueRow(symbol: "heart.fill", color: .pink, title: "Health & Cycles",
                                detail: "Maximum capacity compared with new, charge cycles and temperature.",
                                value: mac?.detail ?? "Reading…")
            } else {
                SettingRow(symbol: "powerplug.fill", color: .gray, title: "No Battery",
                           detail: "This Mac runs on mains power, so battery popups never appear.")
            }
        }
    }

    private func chargeDetail(_ info: BatteryInfo) -> String {
        if info.isCharging {
            if let m = info.minutesToFull, m > 0 { return "Charging · full in \(Format.countdown(Double(m) * 60))" }
            return "Charging"
        }
        if info.isPluggedIn { return "Plugged in, not charging" }
        if let m = info.minutesToEmpty, m > 0 { return "On battery · \(Format.countdown(Double(m) * 60)) left" }
        return "On battery"
    }

    private func levelColor(_ level: Double) -> Color {
        level <= Double(settings.lowBatteryThreshold) / 100 ? .red : .green
    }

    private var extrasSection: some View {
        Section {
            SettingRow(symbol: "chart.xyaxis.line", color: .green, title: "History Range",
                       detail: "How far back the battery chart in the System tab goes. 30 days of samples are kept.") {
                Picker("History range", selection: $historyRange) {
                    Text("24 Hours").tag("day")
                    Text("7 Days").tag("week")
                    Text("30 Days").tag("month")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .uiTestID("setting-batteryHistoryRange")
            }
            SettingToggle(symbol: "menubar.rectangle", color: .green, title: "Battery in the Menu Bar",
                          detail: "Shows the battery level next to the DynaNotch menu bar icon.",
                          isOn: $settings.batteryInMenuBar, testID: "setting-batteryInMenuBar")
            SettingToggle(symbol: "flame.fill", color: .orange, title: "Drain Warnings",
                          detail: "On battery, a popup names an app that keeps using a lot of energy. Checks CPU use every minute.",
                          isOn: $settings.drainWarnings, testID: "setting-drainWarnings")
        } header: {
            Text("History & Menu Bar")
        } footer: {
            PrivacyFooter(text: "Battery history stays on this Mac.")
        }
    }

    private var popupsSection: some View {
        Section("Popups") {
            SettingToggle(symbol: "bolt.fill", color: .green, title: "Charging / Unplugged",
                          detail: "A short popup with the level when you plug in or unplug the charger.",
                          isOn: $settings.chargingActivity)
            SettingToggle(symbol: "powerplug.fill", color: .orange, title: "Unplug Popup",
                          detail: "Shows time left on battery when you unplug.",
                          isOn: $settings.unplugActivity, testID: "setting-unplugActivity")
                .disabled(!settings.chargingActivity)
            SettingToggle(symbol: "battery.25percent", color: .red, title: "Low Battery",
                          detail: "Warns once when the level drops below the threshold while on battery.",
                          isOn: $settings.lowBatteryActivity)
            IntSliderRow(symbol: "exclamationmark.triangle.fill", color: .orange, title: "Low Battery Threshold",
                         detail: "Warn at this level, and again at 10 %.",
                         value: $settings.lowBatteryThreshold, range: 5...50, step: 5, format: { "\($0)%" })
                .disabled(!settings.lowBatteryActivity)
            SettingToggle(symbol: "battery.100percent", color: .green, title: "Fully Charged",
                          detail: "A popup when the battery reaches the full-charge level (\(settings.fullChargeLevel) %) while plugged in.",
                          isOn: $settings.fullChargeActivity, testID: "setting-fullChargeActivity")
            IntSliderRow(symbol: "battery.100percent.bolt", color: .green, title: "Full Charge Level",
                         detail: "Count the battery as full at this level, e.g. 80 % with Optimised Charging.",
                         value: $settings.fullChargeLevel, range: 80...100, step: 5, format: { "\($0)%" },
                         testID: "setting-fullChargeLevel")
                .disabled(!settings.fullChargeActivity)
        }
    }
}

// MARK: - Connectivity

struct ConnectivitySettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var devices = DeviceBatteryService.shared
    @ObservedObject var network = NetworkInfoService.shared
    @ObservedObject var traffic = TrafficService.shared

    private var accessories: [DeviceBattery] { devices.devices.filter { $0.kind != .mac } }

    var body: some View {
        SettingsPageView(page: .connectivity) {
            networkSection
            trafficSection
            Section("Popups") {
                SettingToggle(symbol: "airpods", color: .blue, title: "Device Connected / Disconnected",
                              detail: "AirPods, headphones, mice, keyboards and trackpads, with their battery when known.",
                              isOn: $settings.bluetoothActivity)
                SettingToggle(symbol: "battery.25percent", color: .orange, title: "Accessory Battery Alerts",
                              detail: "A popup when an accessory's battery runs low or is fully charged.",
                              isOn: $settings.accessoryAlerts)
            }
            Section {
                if accessories.isEmpty {
                    SettingRow(symbol: "dot.radiowaves.left.and.right", color: .gray, title: "No Accessories",
                               detail: "Connected Bluetooth accessories that report a battery level appear here.")
                } else {
                    ForEach(accessories) { device in
                        SettingValueRow(symbol: device.kind.symbolName, color: .blue, title: device.name,
                                        detail: accessoryDetail(device),
                                        value: device.displayLevel.map { "\($0)%" } ?? "—")
                    }
                }
                SettingRow(symbol: "gearshape.fill", color: .gray, title: "Bluetooth Settings",
                           detail: "Pair, rename or forget devices in System Settings.") {
                    Button("Open…") { Permissions.openBluetoothSettings() }
                }
            } header: {
                Text("Connected Devices")
            } footer: {
                SettingsFooter("Battery levels also show in the battery pill of the panel header. Refreshed every minute.")
            }
            RestoreDefaultsSection(keys: [SettingsKey.bluetoothActivity, SettingsKey.accessoryAlerts])
        }
    }

    private var networkSection: some View {
        Section {
            SettingValueRow(symbol: network.interfaceName == "Ethernet" ? "cable.connector" : "wifi",
                            color: network.isOnline ? .blue : .gray,
                            title: network.interfaceName ?? "Network",
                            detail: networkDetail,
                            value: network.isOnline ? "Online" : "Offline",
                            valueColor: network.isOnline ? .green : .secondary)
            SettingRow(symbol: "arrow.clockwise", color: .gray, title: "Refresh",
                       detail: "The network is checked automatically when it changes.") {
                Button("Refresh") { network.refresh() }
            }
        } header: {
            Text("Network")
        } footer: {
            SettingsFooter("The Wi-Fi name is only visible to apps with Location access (macOS rule).")
        }
    }

    private var networkDetail: String {
        var parts: [String] = []
        if let ssid = network.ssid { parts.append(ssid) }
        if let ip = network.localIP { parts.append("IP \(ip)") }
        return parts.isEmpty ? "No details available." : parts.joined(separator: " · ")
    }

    private func trafficValue(_ days: Int) -> String {
        let t = traffic.ledger.total(lastDays: days, now: Date())
        return "↓ \(Format.bytes(Double(t.received)))  ↑ \(Format.bytes(Double(t.sent)))"
    }

    private var trafficSection: some View {
        Section {
            SettingValueRow(symbol: "calendar.day.timeline.left", color: .blue, title: "Today",
                            detail: "Downloaded and uploaded since midnight.", value: trafficValue(1))
            SettingValueRow(symbol: "calendar", color: .indigo, title: "Last 7 Days",
                            detail: "Including today.", value: trafficValue(7))
            SettingValueRow(symbol: "calendar.badge.clock", color: .purple, title: "Last 30 Days",
                            detail: "Including today.", value: trafficValue(30))
            SettingRow(symbol: "trash.fill", color: .red, title: "Clear Traffic History",
                       detail: "Forget every recorded day. This can't be undone.") {
                InlineConfirmButton(title: "Clear…", confirmTitle: "Clear") { traffic.clear() }
                    .disabled(traffic.ledger.days.isEmpty)
                    .uiTestID("setting-clearTraffic")
            }
        } header: {
            Text("Traffic")
        } footer: {
            PrivacyFooter(text: "Counted from this Mac's network interfaces while DynaNotch runs. Stays on this Mac.")
        }
    }

    private func accessoryDetail(_ d: DeviceBattery) -> String {
        var parts: [String] = []
        if let l = d.left { parts.append("Left \(l)%") }
        if let r = d.right { parts.append("Right \(r)%") }
        if let c = d.caseLevel { parts.append("Case \(c)%") }
        if d.isCharging { parts.append("Charging") }
        if let detail = d.detail { parts.append(detail) }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }
}
