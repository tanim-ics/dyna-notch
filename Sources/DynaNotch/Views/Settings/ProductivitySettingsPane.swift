import SwiftUI
import Combine
import DynaNotchCore

struct ProductivitySettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @State private var accessibilityGranted = Permissions.accessibilityGranted

    private let permissionPoll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            timerSection
            clipboardSection
            shelfSection
            lyricsSection
        }
        .formStyle(.grouped)
        .navigationTitle("Productivity")
        .onReceive(permissionPoll) { _ in
            accessibilityGranted = Permissions.accessibilityGranted
        }
    }

    private var timerSection: some View {
        Section("Timer") {
            Stepper("Focus: \(settings.pomodoroWorkMinutes) min",
                    value: $settings.pomodoroWorkMinutes, in: 5...120, step: 5)
            Stepper("Short break: \(settings.pomodoroShortBreakMinutes) min",
                    value: $settings.pomodoroShortBreakMinutes, in: 1...30)
            Stepper("Long break: \(settings.pomodoroLongBreakMinutes) min",
                    value: $settings.pomodoroLongBreakMinutes, in: 5...60, step: 5)
            Stepper("Long break after \(settings.pomodoroCycles) sessions",
                    value: $settings.pomodoroCycles, in: 2...8)
            Toggle("Play a sound when a timer ends", isOn: $settings.timerSound)
                .toggleStyle(.switch)
            Toggle("Show running timer around the notch", isOn: $settings.showCompactTimer)
                .toggleStyle(.switch)
            Toggle("Prefer the timer over Now Playing", isOn: $settings.timerOverNowPlaying)
                .toggleStyle(.switch)
                .disabled(!settings.showCompactTimer)
        }
    }

    private var clipboardSection: some View {
        Section {
            Toggle("Clipboard history", isOn: $settings.clipboardEnabled)
                .toggleStyle(.switch)
            Stepper("Keep \(settings.clipboardLimit) items",
                    value: $settings.clipboardLimit, in: 10...500, step: 10)
                .disabled(!settings.clipboardEnabled)
            Toggle("Remove tracking parameters from copied links", isOn: $settings.cleanLinks)
                .toggleStyle(.switch)
                .disabled(!settings.clipboardEnabled)
            Toggle("Paste when clicking an item", isOn: $settings.pasteOnClick)
                .toggleStyle(.switch)
                .disabled(!settings.clipboardEnabled)
            PermissionRow(title: "Accessibility",
                          detail: "Needed to paste into the frontmost app (⌘V). Without it, items are only copied.",
                          granted: accessibilityGranted,
                          buttonTitle: "Grant…") {
                Permissions.requestAccessibility()
            }
        } header: {
            Text("Clipboard")
        } footer: {
            Text("History stays on this Mac. ⌥-click an item to paste it as plain text.")
        }
    }

    private var shelfSection: some View {
        Section {
            Toggle("File shelf", isOn: $settings.shelfEnabled)
                .toggleStyle(.switch)
            Toggle("Remove files from the shelf after dragging them out", isOn: $settings.shelfRemoveOnDragOut)
                .toggleStyle(.switch)
                .disabled(!settings.shelfEnabled)
        } header: {
            Text("Shelf")
        } footer: {
            Text("Drag files onto the notch to park them; drag them out into any app. The shelf only stores references, never copies.")
        }
    }

    private var lyricsSection: some View {
        Section("Lyrics") {
            Toggle("Synced lyrics (from LRCLIB)", isOn: $settings.lyricsEnabled)
                .toggleStyle(.switch)
            Toggle("Show the current line under the notch", isOn: $settings.lyricsInCompact)
                .toggleStyle(.switch)
                .disabled(!settings.lyricsEnabled)
        }
    }
}
