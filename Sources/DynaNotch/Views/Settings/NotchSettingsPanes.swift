import SwiftUI
import DynaNotchCore

// MARK: - Tabs

struct TabsSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        SettingsPageView(page: .tabs) {
            tabsSection
            headerSection
            hotkeysSection
            RestoreDefaultsSection(keys: [
                SettingsKey.panelTabs, SettingsKey.headerButtons,
            ])
        }
    }

    // MARK: Tab list

    private var enabled: [PanelTab] { PanelTab.parseList(settings.panelTabs) }

    /// Enabled tabs in their order, then the disabled ones.
    private var ordered: [PanelTab] {
        let on = enabled
        return on + PanelTab.allCases.filter { !on.contains($0) }
    }

    private var tabsSection: some View {
        Section {
            ForEach(Array(ordered.enumerated()), id: \.element) { entry in
                PanelTabSettingsRow(tab: entry.element,
                                    isOn: enabled.contains(entry.element),
                                    detail: tabDetail(entry.element),
                                    note: featureNote(entry.element),
                                    canMoveUp: entry.offset > 0,
                                    canMoveDown: entry.offset < ordered.count - 1,
                                    onToggle: { setEnabled(entry.element, $0) },
                                    onMove: { move(entry.element, by: $0) })
            }
        } header: {
            Text("Tabs")
        } footer: {
            SettingsFooter("Tabs appear in the panel's tab menu in this order (⌘1–⌘9 for the first nine). Use the arrows to reorder. At least one tab stays on.")
        }
    }

    private func tabDetail(_ tab: PanelTab) -> String {
        switch tab {
        case .home: return "Music, weather, timer, calendar and Up Next at a glance."
        case .nowPlaying: return "Full player with synced lyrics and the sound output menu."
        case .timer: return "Countdowns, Pomodoro and a stopwatch."
        case .clipboard: return "Search and paste anything you copied recently."
        case .shelf: return "Files you dropped on the notch, ready to drag out or AirDrop."
        case .notes: return "A scratch pad and a to-do list. Stored only on this Mac."
        case .calculator: return "Type a sum, get the answer, copy it."
        case .emoji: return "Search emoji by name and copy them."
        case .quickSearch: return "Search the web with Google, DuckDuckGo, GitHub and more."
        case .launcher: return "Your pinned and running apps, plus app search."
        case .shortcuts: return "Run your Shortcuts from the notch."
        case .reminders: return "Your reminders: add and tick them off."
        case .mirror: return "A camera preview to check how you look."
        case .system: return "CPU, memory, network, disk, battery and screen time."
        case .aiUsage: return "Claude Code and Codex usage from local logs."
        case .calendar: return "This month, your events and due reminders; add and edit events."
        case .quickSettings: return "Your favourite switches, one click away in the notch."
        }
    }

    private func featureNote(_ tab: PanelTab) -> String? {
        switch tab {
        case .clipboard where !settings.clipboardEnabled: return "Clipboard history is off"
        case .shelf where !settings.shelfEnabled: return "Shelf is off"
        case .aiUsage where !settings.aiUsageEnabled: return "AI usage is off"
        case .mirror: return "Uses the camera"
        case .reminders: return "Needs Reminders access"
        default: return nil
        }
    }

    private func setEnabled(_ tab: PanelTab, _ on: Bool) {
        var list = ordered.filter { $0 == tab ? on : enabled.contains($0) }
        if list.isEmpty { list = [tab] }
        settings.panelTabs = PanelTab.serialize(list)
    }

    private func move(_ tab: PanelTab, by delta: Int) {
        var all = ordered
        guard let index = all.firstIndex(of: tab) else { return }
        let target = index + delta
        guard all.indices.contains(target) else { return }
        let on = Set(enabled)
        all.swapAt(index, target)
        settings.panelTabs = PanelTab.serialize(all.filter { on.contains($0) })
    }

    // MARK: Header buttons

    private var headerSet: Set<HeaderButtonID> { Set(HeaderButtonID.parseList(settings.headerButtons)) }

    private func headerBinding(_ id: HeaderButtonID) -> Binding<Bool> {
        Binding(get: { headerSet.contains(id) }, set: { on in
            var set = headerSet
            if on { set.insert(id) } else { set.remove(id) }
            settings.headerButtons = HeaderButtonID.serialize(set)
        })
    }

    private func headerDetail(_ id: HeaderButtonID) -> String {
        switch id {
        case .battery: return "Battery level; click for Mac health and accessory batteries."
        case .timer: return "Start or show the running timer."
        case .output: return "Pick the speakers or headphones for sound."
        case .keepAwake: return "Stop your Mac from sleeping while it's on."
        case .mic: return "Mute or unmute the microphone for every app."
        case .screenshot: return "Capture an area of the screen to the clipboard."
        case .colorPicker: return "Copy the colour under the pointer."
        case .actions: return "Stopwatch, Pomodoro, screenshot, colour picker and more."
        case .pin: return "Keep the panel open when the pointer leaves."
        case .lock: return "Lock your Mac right away."
        case .stopwatch: return "Start or reset a stopwatch."
        case .pomodoro: return "Start a Pomodoro focus session."
        case .volume: return "A volume slider for the current output."
        case .scanQR: return "Select a QR code on screen and copy what it says."
        case .ports: return "Apps listening on network ports; stop one with a click."
        case .systemStats: return "CPU and memory at a glance; click for details."
        }
    }

    private var headerSection: some View {
        Section {
            ForEach(HeaderButtonID.allCases, id: \.self) { id in
                SettingToggle(symbol: id.symbolName, color: .gray, title: id.title,
                              detail: headerDetail(id), isOn: headerBinding(id))
            }
        } header: {
            Text("Header Buttons")
        } footer: {
            SettingsFooter("Buttons on the right of the panel header, in this order.")
        }
    }

    private var hotkeysSection: some View {
        Section {
            SettingNavigationRow(page: .behavior,
                                 detail: "Shortcuts for the panel, actions and each tab live under Behavior → Keyboard Shortcuts.")
        } header: {
            Text("Keyboard Shortcuts")
        }
    }
}

struct PanelTabSettingsRow: View {
    let tab: PanelTab
    let isOn: Bool
    let detail: String
    let note: String?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: (Bool) -> Void
    let onMove: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: tab.symbolName, color: isOn ? Color.accentColor : Color.gray, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tab.title)
                    if let note = note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .opacity(isOn ? 1 : 0.6)
            Spacer(minLength: 8)
            Button { onMove(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .help("Move up")
            Button { onMove(1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .help("Move down")
            Toggle("", isOn: Binding(get: { isOn }, set: { onToggle($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

// MARK: - Home

struct HomeSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var weather = WeatherService.shared
    @ObservedObject var colors = ColorHistory.shared

    var body: some View {
        SettingsPageView(page: .home) {
            gridSection
            cardsSection
            worldClockSection
            linksSection
            weatherSection
            colorSection
            RestoreDefaultsSection(keys: [
                SettingsKey.expandedShowsCalendar, SettingsKey.expandedShowsBattery, SettingsKey.weatherEnabled,
                SettingsKey.weatherCity, SettingsKey.temperatureUnit, SettingsKey.colorFormat,
                SettingsKey.homeCards, SettingsKey.homeColumns, SettingsKey.worldClocks, SettingsKey.savedLinks,
            ])
        }
    }

    private var slotsUsed: Int { HomeCard.slotsUsed(HomeCard.parseList(settings.homeCards)) }

    private var gridSection: some View {
        Section {
            SettingRow(symbol: "square.grid.3x2.fill", color: .orange, title: "Columns",
                       detail: "How many cards sit side by side. More columns make each card smaller.") {
                Picker("Columns", selection: $settings.homeColumns) {
                    ForEach(2...4, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .uiTestID("setting-homeColumns")
            }
            HomeCardsEditor()
        } header: {
            Text("Card Grid")
        } footer: {
            SettingsFooter("Cards fill the grid in this order, row by row (\(slotsUsed) slots in use, \(settings.homeColumns) per row). Wide cards take two slots.")
        }
    }

    private var worldClockSection: some View {
        Section {
            WorldClocksEditor()
        } header: {
            Text("World Clock")
        } footer: {
            SettingsFooter(HomeCard.parseList(settings.homeCards).contains(.worldClock)
                           ? "Shown on the World Clock card."
                           : "Turn on the World Clock card above to see these cities on the Home tab.")
        }
    }

    private var linksSection: some View {
        Section {
            SavedLinksEditor()
        } header: {
            Text("Saved Links")
        } footer: {
            SettingsFooter(HomeCard.parseList(settings.homeCards).contains(.links)
                           ? "Open in your default browser from the Saved Links card."
                           : "Turn on the Saved Links card above to use these on the Home tab.")
        }
    }

    private var cardsSection: some View {
        Section("Card Details") {
            SettingToggle(symbol: "calendar", color: .red, title: "Calendar & Up Next",
                          detail: "A month view and your next events. Needs Calendar access.",
                          isOn: $settings.expandedShowsCalendar)
            SettingToggle(symbol: "battery.75percent", color: .green, title: "Battery",
                          detail: "Your Mac's battery level and charging state.",
                          isOn: $settings.expandedShowsBattery)
        }
    }

    private var weatherSection: some View {
        Section {
            SettingToggle(symbol: "cloud.sun.fill", color: .blue, title: "Weather",
                          detail: "Current conditions and today's high / low. Uses the network (Open-Meteo, no account).",
                          isOn: $settings.weatherEnabled)
            Group {
                SettingRow(symbol: "mappin.and.ellipse", color: .red, title: "City",
                           detail: "Leave empty to use your location (asks for Location Services once).") {
                    TextField("City", text: $settings.weatherCity, prompt: Text("Current location"))
                        .labelsHidden()
                        .frame(width: 180)
                        .onSubmit { weather.refresh() }
                }
                SettingRow(symbol: "thermometer.medium", color: .orange, title: "Unit",
                           detail: "Temperature unit for the weather card.") {
                    Picker("Unit", selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingRow(symbol: "info.circle.fill", color: .gray, title: "Status",
                           detail: weatherStatus) {
                    Button("Refresh") { weather.refresh() }
                }
            }
            .disabled(!settings.weatherEnabled)
        } header: {
            Text("Weather")
        } footer: {
            SettingsFooter("Refreshed every 30 minutes. Only the city name or rough coordinates are sent to Open-Meteo.")
        }
    }

    private var weatherStatus: String {
        if let s = weather.snapshot {
            let place = s.locationName.isEmpty ? "" : "\(s.locationName) · "
            return "\(place)\(Int(s.temperature.rounded()))\(settings.temperatureUnit.symbol), \(s.summary)"
        }
        return weather.status.isEmpty ? "No data yet" : weather.status
    }

    private var colorSection: some View {
        Section {
            SettingRow(symbol: "eyedropper", color: .purple, title: "Copy Picked Colours As",
                       detail: "Pick a Color (⋯ actions menu) copies the colour under the pointer in this format.") {
                Picker("Copy picked colours as", selection: $settings.colorFormat) {
                    Text("HEX").tag("hex")
                    Text("RGB").tag("rgb")
                    Text("HSL").tag("hsl")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(symbol: "swatchpalette.fill", color: .pink, title: "Colour History",
                       detail: colors.colors.isEmpty ? "No colours picked yet."
                                                     : "\(colors.colors.count) colours picked. Stored only on this Mac.") {
                InlineConfirmButton(title: "Clear…", confirmTitle: "Clear") { colors.clear() }
                    .disabled(colors.colors.isEmpty)
            }
        } header: {
            Text("Colour Tools")
        } footer: {
            SettingsFooter("Examples: HEX #1E90FF · RGB rgb(30, 144, 255) · HSL hsl(210, 100%, 56%)")
        }
    }
}
