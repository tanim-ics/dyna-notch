import SwiftUI
import DynaNotchCore

struct PanelSettingsPane: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            tabsSection
            behaviourSection
            hotkeysSection
            displaySection
        }
        .formStyle(.grouped)
        .navigationTitle("Panel")
    }

    // MARK: Tabs

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
                                    note: featureNote(entry.element),
                                    canMoveUp: entry.offset > 0,
                                    canMoveDown: entry.offset < ordered.count - 1,
                                    onToggle: { setEnabled(entry.element, $0) },
                                    onMove: { move(entry.element, by: $0) })
            }
        } header: {
            Text("Tabs")
        } footer: {
            Text("Tabs appear left of the notch in this order. At least one tab stays on.")
        }
    }

    private func featureNote(_ tab: PanelTab) -> String? {
        switch tab {
        case .clipboard where !settings.clipboardEnabled: return "Clipboard history is off"
        case .shelf where !settings.shelfEnabled: return "Shelf is off"
        case .aiUsage where !settings.aiUsageEnabled: return "AI usage is off"
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

    // MARK: Other sections

    private var behaviourSection: some View {
        Section {
            Picker("Panel material", selection: $settings.islandMaterial) {
                ForEach(IslandMaterial.allCases, id: \.self) { material in
                    Text(material.title).tag(material)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Remember the last tab", isOn: $settings.rememberLastTab)
                .toggleStyle(.switch)
            Button("Show Welcome Again") {
                NotificationCenter.default.post(name: .dynaNotchShowWelcome, object: nil)
            }
        } header: {
            Text("Behaviour")
        } footer: {
            Text("Pin the panel with the pin button in its header to keep it open while the mouse is elsewhere — handy for the timer, notes or the shelf. Click the pin again to release it.")
        }
    }

    private var hotkeysSection: some View {
        Section {
            Toggle("Global hotkeys", isOn: $settings.hotkeysEnabled)
                .toggleStyle(.switch)
        } header: {
            Text("Hotkeys")
        } footer: {
            Text("⌃⌥N toggle panel · ⌃⌥V clipboard")
        }
    }

    private var displaySection: some View {
        Section {
            Picker("Style on displays without a notch", selection: $settings.nonNotchStyle) {
                ForEach(NonNotchStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
        } header: {
            Text("Displays without a notch")
        }
    }
}

struct PanelTabSettingsRow: View {
    let tab: PanelTab
    let isOn: Bool
    let note: String?
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: (Bool) -> Void
    let onMove: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tab.symbolName)
                .frame(width: 20)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                if let note = note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
