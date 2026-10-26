import Foundation
import SwiftUI
import AppKit
import DynaNotchCore

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, island, panel, nowPlaying, hud, activities, productivity, weatherAI, calendar, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .island: return "Island"
        case .panel: return "Panel"
        case .productivity: return "Productivity"
        case .weatherAI: return "Weather & AI"
        case .nowPlaying: return "Now Playing"
        case .hud: return "HUD"
        case .activities: return "Live Activities"
        case .calendar: return "Calendar"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .island: return "capsule.portrait"
        case .panel: return "rectangle.topthird.inset.filled"
        case .productivity: return "checklist"
        case .weatherAI: return "cloud.sun"
        case .nowPlaying: return "music.note"
        case .hud: return "speaker.wave.2"
        case .activities: return "bolt.circle"
        case .calendar: return "calendar"
        case .about: return "info.circle"
        }
    }
}

/// Settings window content (hosted in an NSHostingController by SettingsWindowController).
struct SettingsRootView: View {
    @State private var selection: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SettingsPane.allCases) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general: GeneralSettingsPane()
        case .island: IslandSettingsPane()
        case .panel: PanelSettingsPane()
        case .productivity: ProductivitySettingsPane()
        case .weatherAI: WeatherAISettingsPane()
        case .nowPlaying: NowPlayingSettingsPane()
        case .hud: HUDSettingsPane()
        case .activities: ActivitiesSettingsPane()
        case .calendar: CalendarSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}

// MARK: - Shared rows

/// A slider with a trailing value label.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: $value, in: range, step: step)
                    .frame(minWidth: 160)
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
    }
}

/// Permission status row with an action button.
struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if granted {
                Text("Granted")
                    .foregroundStyle(.secondary)
            } else {
                Button(buttonTitle, action: action)
            }
        }
    }
}

enum SettingsFormat {
    static func seconds(_ v: Double) -> String { String(format: "%.2f s", v) }
    static func wholeSeconds(_ v: Double) -> String { String(format: "%.0f s", v) }
}
