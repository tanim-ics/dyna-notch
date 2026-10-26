import SwiftUI
import DynaNotchCore

struct NowPlayingSettingsPane: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService
    @ObservedObject private var history = ListeningHistoryService.shared
    @State private var musicApps: [MusicApps.App] = MusicApps.installed()

    var body: some View {
        SettingsPageView(page: .nowPlaying) {
            statusSection
            generalSection
            appearanceSection
            lyricsSection
            historySection
            mediaKeysSection
            RestoreDefaultsSection(keys: [
                SettingsKey.peekOnHover, SettingsKey.mediaKeysControlPlayer, SettingsKey.preventMusicAutoLaunch,
                SettingsKey.nowPlayingEnabled, SettingsKey.showCompactNowPlaying, SettingsKey.showTrackPeek,
                SettingsKey.pausedLingerSeconds, SettingsKey.artworkStyle, SettingsKey.visualizerStyle,
                SettingsKey.artworkGlow, SettingsKey.lyricsEnabled, SettingsKey.lyricsInCompact, SettingsKey.lyricsOffset,
                SettingsKey.trackInfoMode, SettingsKey.desktopLyrics, SettingsKey.listeningHistory, SettingsKey.defaultMusicApp,
            ])
        }
    }

    private var generalSection: some View {
        Section("Island") {
            SettingToggle(symbol: "music.note", color: .pink, title: "Now Playing",
                          detail: "Follow music from Spotify, Apple Music, browsers and any app that reports to macOS.",
                          isOn: $settings.nowPlayingEnabled)
            Group {
                SettingToggle(symbol: "rectangle.split.3x1.fill", color: .purple, title: "Compact Player",
                              detail: "Artwork and a visualiser beside the notch while music plays.",
                              isOn: $settings.showCompactNowPlaying)
                SettingToggle(symbol: "text.below.photo.fill", color: .orange, title: "Track Peek",
                              detail: "Briefly shows the title and artist under the notch when the song changes.",
                              isOn: $settings.showTrackPeek)
                SettingStackedRow(symbol: "textformat", color: .orange, title: "Track Info Under the Notch",
                                  detail: "When to show the title and artist below the compact player.") {
                    Picker("Track info", selection: $settings.trackInfoMode) {
                        ForEach(TrackInfoMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .uiTestID("setting-trackInfoMode")
                }
                SettingToggle(symbol: "cursorarrow.motionlines", color: .orange, title: "Peek on Hover",
                              detail: "Hovering the compact player shows the title and artist under the notch.",
                              isOn: $settings.peekOnHover, testID: "setting-peekOnHover")
                SliderRow(symbol: "pause.circle.fill", color: .gray, title: "Keep Showing After Pause",
                          detail: "How long the compact player stays after you pause.",
                          value: $settings.pausedLingerSeconds, range: 0...60, step: 5,
                          format: SettingsFormat.wholeSeconds)
            }
            .disabled(!settings.nowPlayingEnabled)
        }
    }

    private var appearanceSection: some View {
        Section("Look") {
            SettingRow(symbol: "photo.fill", color: .blue, title: "Artwork Style",
                       detail: "Rounded square, or a vinyl disc that spins while playing.") {
                Picker("Artwork style", selection: $settings.artworkStyle) {
                    ForEach(ArtworkStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingRow(symbol: "waveform", color: .green, title: "Visualizer",
                       detail: "Animated bars tinted with the artwork's colour.") {
                Picker("Visualizer", selection: $settings.visualizerStyle) {
                    ForEach(VisualizerStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingToggle(symbol: "sun.max.fill", color: .yellow, title: "Artwork Glow",
                          detail: "A soft glow in the artwork's colour behind the player.",
                          isOn: $settings.artworkGlow)
        }
        .disabled(!settings.nowPlayingEnabled)
    }

    private var lyricsSection: some View {
        Section {
            SettingToggle(symbol: "quote.bubble.fill", color: .indigo, title: "Synced Lyrics",
                          detail: "Time-synced lyrics in the Now Playing tab. Uses the network (LRCLIB).",
                          isOn: $settings.lyricsEnabled)
            Group {
                SettingToggle(symbol: "text.aligncenter", color: .purple, title: "Current Line Under the Notch",
                              detail: "Shows the line being sung below the compact player.",
                              isOn: $settings.lyricsInCompact)
                SettingToggle(symbol: "macwindow", color: .indigo, title: "Desktop Lyrics",
                              detail: "The current line floats above your desktop and lets clicks pass through.",
                              isOn: $settings.desktopLyrics, testID: "setting-desktopLyrics")
                SliderRow(symbol: "metronome.fill", color: .orange, title: "Timing Offset",
                          detail: "Shift the lyrics if they run ahead of (−) or behind (+) the music.",
                          value: $settings.lyricsOffset, range: -5...5, step: 0.1,
                          format: SettingsFormat.signedSeconds)
            }
            .disabled(!settings.lyricsEnabled)
        } header: {
            Text("Lyrics")
        } footer: {
            SettingsFooter("Only the song title, artist and album are sent to LRCLIB. Lyrics are cached on this Mac.")
        }
        .disabled(!settings.nowPlayingEnabled)
    }

    private var historySection: some View {
        Section {
            SettingToggle(symbol: "clock.arrow.circlepath", color: .pink, title: "Listening History",
                          detail: "Keep a list of the songs you play, with bookmarks, in the Now Playing tab.",
                          isOn: $settings.listeningHistory, testID: "setting-listeningHistory")
            SettingRow(symbol: "trash.fill", color: .red, title: "Clear History",
                       detail: historyDetail) {
                InlineConfirmButton(title: "Clear…", confirmTitle: "Clear") { history.clear() }
                    .disabled(history.history.entries.isEmpty)
                    .uiTestID("setting-clearListeningHistory")
            }
        } header: {
            Text("History")
        } footer: {
            PrivacyFooter(text: "Stays on this Mac. Bookmarked songs are kept when you clear the history.")
        }
        .disabled(!settings.nowPlayingEnabled)
    }

    private var historyDetail: String {
        let n = history.history.entries.count
        return n == 0 ? "No songs recorded yet." : "\(n) song\(n == 1 ? "" : "s") recorded."
    }

    private var mediaKeysSection: some View {
        Section {
            SettingToggle(symbol: "playpause.fill", color: .blue, title: "Media Keys Control the Player",
                          detail: "Play/pause and skip go to the app that's playing instead of opening Music. Needs Accessibility.",
                          isOn: $settings.mediaKeysControlPlayer, testID: "setting-mediaKeysControlPlayer")
                .disabled(!settings.nowPlayingEnabled)
            SettingToggle(symbol: "xmark.app.fill", color: .red, title: "Stop Music From Opening on Its Own",
                          detail: "Closes the Music app when it opens by itself, e.g. after pressing Play with nothing playing.",
                          isOn: $settings.preventMusicAutoLaunch, testID: "setting-preventMusicAutoLaunch")
            SettingRow(symbol: "music.note.house.fill", color: .pink, title: "Default Music App",
                       detail: "What the Play key opens when nothing is playing. Needs Media Keys Control the Player.") {
                Picker("Default music app", selection: $settings.defaultMusicApp) {
                    Text("Automatic").tag("")
                    Divider()
                    ForEach(musicApps) { app in
                        Text(app.name).tag(app.id)
                    }
                    if !settings.defaultMusicApp.isEmpty && !musicApps.contains(where: { $0.id == settings.defaultMusicApp }) {
                        Text(settings.defaultMusicApp).tag(settings.defaultMusicApp)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .uiTestID("setting-defaultMusicApp")
            }
            .disabled(!settings.mediaKeysControlPlayer)
        } header: {
            Text("Media Keys")
        }
    }

    private var statusSection: some View {
        Section("Status") {
            SettingValueRow(symbol: "antenna.radiowaves.left.and.right", color: nowPlaying.source == .none ? .gray : .green,
                            title: "Source", detail: "How DynaNotch reads what's playing.",
                            value: sourceTitle)
            SettingValueRow(symbol: "play.circle.fill", color: .pink, title: "Current Track",
                            detail: nowPlaying.appName.isEmpty ? "No app is playing." : "Playing in \(nowPlaying.appName).",
                            value: trackTitle)
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
