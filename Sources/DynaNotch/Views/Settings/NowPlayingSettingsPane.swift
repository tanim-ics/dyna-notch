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
                          detail: "Show music from Spotify, Apple Music, browsers and more.",
                          isOn: $settings.nowPlayingEnabled)
            Group {
                SettingToggle(symbol: "rectangle.split.3x1.fill", color: .purple, title: "Compact Player",
                              detail: "Artwork and a visualiser next to the notch.",
                              isOn: $settings.showCompactNowPlaying)
                SettingToggle(symbol: "text.below.photo.fill", color: .orange, title: "Track Peek",
                              detail: "Show the song name for a moment when it changes.",
                              isOn: $settings.showTrackPeek)
                SettingStackedRow(symbol: "textformat", color: .orange, title: "Track Info Under the Notch",
                                  detail: "When to show the song name under the player.") {
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
                              detail: "Hover the player to see the song name.",
                              isOn: $settings.peekOnHover, testID: "setting-peekOnHover")
                SliderRow(symbol: "pause.circle.fill", color: .gray, title: "Keep Showing After Pause",
                          detail: "How long the player stays after you pause.",
                          value: $settings.pausedLingerSeconds, range: 0...60, step: 5,
                          format: SettingsFormat.wholeSeconds)
            }
            .disabled(!settings.nowPlayingEnabled)
        }
    }

    private var appearanceSection: some View {
        Section("Look") {
            SettingRow(symbol: "photo.fill", color: .blue, title: "Artwork Style",
                       detail: "A rounded square, or a spinning record.") {
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
                       detail: "Little bars in the artwork's colour.") {
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
                          detail: "A soft glow behind the player.",
                          isOn: $settings.artworkGlow)
        }
        .disabled(!settings.nowPlayingEnabled)
    }

    private var lyricsSection: some View {
        Section {
            SettingToggle(symbol: "quote.bubble.fill", color: .indigo, title: "Synced Lyrics",
                          detail: "Synced lyrics from LRCLIB.",
                          isOn: $settings.lyricsEnabled)
            Group {
                SettingToggle(symbol: "text.aligncenter", color: .purple, title: "Current Line Under the Notch",
                              detail: "Show the current line under the player.",
                              isOn: $settings.lyricsInCompact)
                SettingToggle(symbol: "macwindow", color: .indigo, title: "Desktop Lyrics",
                              detail: "Float the current line on your desktop.",
                              isOn: $settings.desktopLyrics, testID: "setting-desktopLyrics")
                SliderRow(symbol: "metronome.fill", color: .orange, title: "Timing Offset",
                          detail: "Nudge the lyrics if they're early or late.",
                          value: $settings.lyricsOffset, range: -5...5, step: 0.1,
                          format: SettingsFormat.signedSeconds)
            }
            .disabled(!settings.lyricsEnabled)
        } header: {
            Text("Lyrics")
        } footer: {
            SettingsFooter("Only the song, artist and album go to LRCLIB. Lyrics are kept on this Mac.")
        }
        .disabled(!settings.nowPlayingEnabled)
    }

    private var historySection: some View {
        Section {
            SettingToggle(symbol: "clock.arrow.circlepath", color: .pink, title: "Listening History",
                          detail: "Remember the songs you play.",
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
            PrivacyFooter(text: "Stays on this Mac. Bookmarks survive a clear.")
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
                          detail: "Play and skip go to whatever's playing. Needs Accessibility.",
                          isOn: $settings.mediaKeysControlPlayer, testID: "setting-mediaKeysControlPlayer")
                .disabled(!settings.nowPlayingEnabled)
            SettingToggle(symbol: "xmark.app.fill", color: .red, title: "Stop Music From Opening on Its Own",
                          detail: "Stop Music from opening by itself.",
                          isOn: $settings.preventMusicAutoLaunch, testID: "setting-preventMusicAutoLaunch")
            SettingRow(symbol: "music.note.house.fill", color: .pink, title: "Default Music App",
                       detail: "What Play opens when nothing's playing.") {
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
