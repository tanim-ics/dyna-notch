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
            SettingsFooter("Use the arrows to change the order. ⌘1–⌘9 open the first nine.")
        }
    }

    private func tabDetail(_ tab: PanelTab) -> String {
        switch tab {
        case .home: return "Music, weather, timer and calendar at a glance."
        case .nowPlaying: return "The player, with synced lyrics."
        case .timer: return "Countdowns, Pomodoro and a stopwatch."
        case .clipboard: return "Everything you copied lately."
        case .shelf: return "Files you dropped on the notch."
        case .notes: return "Quick notes and to-dos. Stays on this Mac."
        case .calculator: return "Type a sum, get the answer."
        case .emoji: return "Find an emoji and copy it."
        case .quickSearch: return "Search the web from the notch."
        case .launcher: return "Your apps, one click away."
        case .shortcuts: return "Run your Shortcuts."
        case .reminders: return "Add and tick off reminders."
        case .mirror: return "Check how you look before a call."
        case .system: return "CPU, memory, network, disk and battery."
        case .aiUsage: return "Claude Code and Codex usage."
        case .calendar: return "Your month, events and reminders."
        case .quickSettings: return "Your favourite switches."
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
        case .battery: return "Battery level. Click for more."
        case .timer: return "Start or show a timer."
        case .output: return "Choose where sound plays."
        case .keepAwake: return "Keep your Mac awake."
        case .mic: return "Mute or unmute your mic."
        case .screenshot: return "Grab part of the screen."
        case .colorPicker: return "Copy the colour under the pointer."
        case .actions: return "Stopwatch, Pomodoro, screenshot and more."
        case .pin: return "Keep the panel open."
        case .lock: return "Lock your Mac right away."
        case .stopwatch: return "Start or reset a stopwatch."
        case .pomodoro: return "Start a Pomodoro focus session."
        case .volume: return "Change the volume."
        case .scanQR: return "Read a QR code on screen."
        case .ports: return "Apps using network ports. Click to stop one."
        case .systemStats: return "CPU and memory. Click for more."
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
            SettingsFooter("The buttons at the top right of the panel.")
        }
    }

    private var hotkeysSection: some View {
        Section {
            SettingNavigationRow(page: .behavior,
                                 detail: "Shortcuts live under Behavior → Keyboard Shortcuts.")
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
                       detail: "More columns means smaller cards.") {
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
            SettingsFooter("Cards fill in this order (\(slotsUsed) slots used, \(settings.homeColumns) per row). Wide cards take two.")
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
                           : "Turn on the World Clock card to see these.")
        }
    }

    private var linksSection: some View {
        Section {
            SavedLinksEditor()
        } header: {
            Text("Saved Links")
        } footer: {
            SettingsFooter(HomeCard.parseList(settings.homeCards).contains(.links)
                           ? "Open them from the Saved Links card."
                           : "Turn on the Saved Links card to use these.")
        }
    }

    private var cardsSection: some View {
        Section("Card Details") {
            SettingToggle(symbol: "calendar", color: .red, title: "Calendar & Up Next",
                          detail: "Your month and next events. Needs Calendar access.",
                          isOn: $settings.expandedShowsCalendar)
            SettingToggle(symbol: "battery.75percent", color: .green, title: "Battery",
                          detail: "Your Mac's battery and charging.",
                          isOn: $settings.expandedShowsBattery)
        }
    }

    private var weatherSection: some View {
        Section {
            SettingToggle(symbol: "cloud.sun.fill", color: .blue, title: "Weather",
                          detail: "Today's weather from Open-Meteo. No account needed.",
                          isOn: $settings.weatherEnabled)
            Group {
                SettingRow(symbol: "mappin.and.ellipse", color: .red, title: "City",
                           detail: "Leave empty to use your location.") {
                    TextField("City", text: $settings.weatherCity, prompt: Text("Current location"))
                        .labelsHidden()
                        .frame(width: 180)
                        .onSubmit { weather.refresh() }
                }
                SettingRow(symbol: "thermometer.medium", color: .orange, title: "Unit",
                           detail: "Celsius or Fahrenheit.") {
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
            SettingsFooter("Updates every 30 minutes. Only the city goes to Open-Meteo.")
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
                       detail: "The format used when you pick a colour.") {
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
            SettingsFooter("Like #1E90FF, rgb(30, 144, 255) or hsl(210, 100%, 56%)")
        }
    }
}
