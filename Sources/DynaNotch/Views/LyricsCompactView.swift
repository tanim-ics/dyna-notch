import SwiftUI
import AppKit
import DynaNotchCore

/// Compact now-playing row plus the current lyric line under the notch.
struct LyricsCompactView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var lyrics: LyricsService
    @EnvironmentObject var nowPlaying: NowPlayingService

    /// Redraw exactly when the next lyric line starts (not on a 4 Hz timer); rebuilt when the track, its position
    /// or its lyrics change, since those publish and re-evaluate this body.
    private var lineChanges: [Date] {
        let now = Date()
        let snapshot = nowPlaying.snapshot
        let rate = snapshot.isPlaying ? (snapshot.playbackRate > 0 ? snapshot.playbackRate : 1) : 0
        return LRCParser.changeDates(lines: lyrics.lines, elapsed: snapshot.elapsed(at: now) + settings.lyricsOffset,
                                     rate: rate, now: now)
    }

    private var radii: IslandRadii { IslandLayout.radii(for: .lyrics, hudStyle: settings.hudStyle) }

    var body: some View {
        VStack(spacing: 0) {
            CompactRow(notch: vm.notch,
                       side: IslandLayout.sideWidth(for: .lyrics, hudStyle: settings.hudStyle),
                       radii: radii) {
                CompactArtwork()
            } trailing: {
                NowPlayingIndicator()
            }
            TimelineView(.explicit(lineChanges)) { context in
                CompactLyricLine(date: context.date)
            }
            .padding(.horizontal, radii.top + 10)
            .frame(height: 26)
        }
    }
}

struct CompactLyricLine: View {
    let date: Date

    @EnvironmentObject var lyrics: LyricsService
    @EnvironmentObject var nowPlaying: NowPlayingService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var index: Int? {
        lyrics.currentIndex(at: nowPlaying.snapshot.elapsed(at: date) + AppSettings.shared.lyricsOffset)
    }

    private var text: String {
        guard !lyrics.lines.isEmpty else { return "♪ Lyrics appear here" }
        guard let index = index, lyrics.lines.indices.contains(index) else { return "♪" }
        let line = lyrics.lines[index].text
        return line.isEmpty ? "♪" : line
    }

    var body: some View {
        ZStack {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(lyrics.lines.isEmpty ? 0.6 : 0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
                .id(index ?? -1)
                .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: index ?? -1)
    }
}
