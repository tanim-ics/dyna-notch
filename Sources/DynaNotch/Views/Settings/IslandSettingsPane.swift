import Foundation
import SwiftUI
import DynaNotchCore

struct IslandSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var vm: IslandViewModel

    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        Form {
            interactionSection
            expandedSection
            previewSection
        }
        .formStyle(.grouped)
        .navigationTitle("Island")
    }

    private var interactionSection: some View {
        Section("Interaction") {
            Toggle("Expand on hover", isOn: $settings.expandOnHover)
                .toggleStyle(.switch)
            SliderRow(title: "Hover delay", value: $settings.hoverDelay,
                      range: 0...1, step: 0.05, format: SettingsFormat.seconds)
                .disabled(!settings.expandOnHover)
            SliderRow(title: "Collapse delay", value: $settings.collapseDelay,
                      range: 0...2, step: 0.05, format: SettingsFormat.seconds)
            Toggle("Click to expand", isOn: $settings.clickToExpand)
                .toggleStyle(.switch)
            Toggle("Swipe gestures", isOn: $settings.gesturesEnabled)
                .toggleStyle(.switch)
        }
    }

    private var expandedSection: some View {
        Section("Expanded view") {
            Toggle("Show calendar", isOn: $settings.expandedShowsCalendar)
                .toggleStyle(.switch)
            Toggle("Show battery", isOn: $settings.expandedShowsBattery)
                .toggleStyle(.switch)
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(DemoActivity.allCases, id: \.self) { demo in
                    Button(demoTitle(demo)) { vm.simulate(demo) }
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func demoTitle(_ demo: DemoActivity) -> String {
        switch demo {
        case .lowBattery: return "Low Battery"
        case .airpods: return "AirPods"
        case .peek: return "Track Peek"
        default: return demo.rawValue.capitalized
        }
    }
}
