import SwiftUI
import DynaNotchCore

struct NowPlayingSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService

    var body: some View {
        Form {
            generalSection
            appearanceSection
            statusSection
        }
        .formStyle(.grouped)
        .navigationTitle("Now Playing")
    }

    private var generalSection: some View {
        Section("Now Playing") {
            Toggle("Enable Now Playing", isOn: $settings.nowPlayingEnabled)
                .toggleStyle(.switch)
            Toggle("Show compact player around the notch", isOn: $settings.showCompactNowPlaying)
                .toggleStyle(.switch)
            Toggle("Sneak peek on track change", isOn: $settings.showTrackPeek)
                .toggleStyle(.switch)
            SliderRow(title: "Keep showing after pause", value: $settings.pausedLingerSeconds,
                      range: 0...60, step: 5, format: SettingsFormat.wholeSeconds)
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Artwork style", selection: $settings.artworkStyle) {
                ForEach(ArtworkStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            Picker("Visualizer", selection: $settings.visualizerStyle) {
                ForEach(VisualizerStyle.allCases, id: \.self) { style in
                    Text(style.title).tag(style)
                }
            }
            Toggle("Artwork glow", isOn: $settings.artworkGlow)
                .toggleStyle(.switch)
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Source", value: sourceTitle)
            LabeledContent("Current track", value: trackTitle)
        }
    }

    private var sourceTitle: String {
        switch nowPlaying.source {
        case .mediaRemote: return "MediaRemote"
        case .appleScript: return "AppleScript fallback"
        default: return "Not connected"
        }
    }

    private var trackTitle: String {
        let s = nowPlaying.snapshot
        if s.isEmpty { return "Nothing playing" }
        return s.artist.isEmpty ? s.title : "\(s.title) — \(s.artist)"
    }
}
