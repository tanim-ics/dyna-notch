import SwiftUI
import AppKit
import DynaNotchCore

struct WeatherAISettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var weather = WeatherService.shared
    @ObservedObject var usage = AIUsageService.shared

    private static let hookExample =
        "open -g \"dynanotch://notify?title=Claude%20Code&body=Waiting%20for%20you&symbol=sparkles\""

    var body: some View {
        Form {
            weatherSection
            aiSection
            hookSection
        }
        .formStyle(.grouped)
        .navigationTitle("Weather & AI")
    }

    // MARK: Weather

    private var weatherSection: some View {
        Section {
            Toggle("Show weather on the Home tab", isOn: $settings.weatherEnabled)
                .toggleStyle(.switch)
            TextField("City", text: $settings.weatherCity, prompt: Text("Leave empty to use your location"))
                .disabled(!settings.weatherEnabled)
                .onSubmit { weather.refresh() }
            Picker("Unit", selection: $settings.temperatureUnit) {
                ForEach(TemperatureUnit.allCases, id: \.self) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            .disabled(!settings.weatherEnabled)
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    Text(weatherStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Refresh") { weather.refresh() }
                        .disabled(!settings.weatherEnabled)
                }
            }
        } header: {
            Text("Weather")
        } footer: {
            Text("Forecasts from Open-Meteo, refreshed every 30 minutes. With no city, your location is looked up once (Location Services permission).")
        }
    }

    private var weatherStatus: String {
        if let s = weather.snapshot {
            let place = s.locationName.isEmpty ? "" : "\(s.locationName) · "
            return "\(place)\(Int(s.temperature.rounded()))\(settings.temperatureUnit.symbol), \(s.summary)"
        }
        return weather.status.isEmpty ? "No data yet" : weather.status
    }

    // MARK: AI usage

    private var aiSection: some View {
        Section {
            Toggle("AI Usage tab", isOn: $settings.aiUsageEnabled)
                .toggleStyle(.switch)
            LabeledContent("Claude Code", value: usage.hasClaudeData ? "Found" : "No logs found")
            LabeledContent("Codex", value: usage.hasCodexData ? "Found" : "No logs found")
            Button("Refresh now") { usage.refresh() }
                .disabled(!settings.aiUsageEnabled)
        } header: {
            Text("AI Usage")
        } footer: {
            Text("Read locally, nothing is uploaded: Claude Code session logs in ~/.claude/projects (token usage, 5-hour blocks, estimated cost) and Codex session logs in ~/.codex/sessions (rate-limit windows).")
        }
    }

    private var hookSection: some View {
        Section {
            Text(WeatherAISettingsPane.hookExample)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(WeatherAISettingsPane.hookExample, forType: .string)
            }
        } header: {
            Text("Notifications from scripts")
        } footer: {
            Text("Use this as a Claude Code hook (e.g. Notification or Stop in ~/.claude/settings.json) — or from any script — to show a notification in the notch. Parameters: title, body, symbol (SF Symbol), duration (1–30 s).")
        }
    }
}
