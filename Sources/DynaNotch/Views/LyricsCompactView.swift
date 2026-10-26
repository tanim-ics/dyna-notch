import SwiftUI
import AppKit
import DynaNotchCore

/// Compact now-playing row plus the current lyric line under the notch.
struct LyricsCompactView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings

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
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
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
        lyrics.currentIndex(at: nowPlaying.snapshot.elapsed(at: date))
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
