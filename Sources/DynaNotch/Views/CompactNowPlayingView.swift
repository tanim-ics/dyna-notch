import SwiftUI
import AppKit
import DynaNotchCore

/// Trailing indicator for compact now-playing rows: visualiser, dot or pause glyph.
struct NowPlayingIndicator: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService

    private var accent: Color { Color(nsColor: nowPlaying.accentColor) }
    private var isPlaying: Bool { nowPlaying.snapshot.isPlaying }

    var body: some View {
        if settings.visualizerStyle == .none {
            Circle()
                .fill(accent.opacity(isPlaying ? 1 : 0.4))
                .frame(width: 6, height: 6)
        } else if isPlaying {
            AudioVisualizerView(color: accent, isPlaying: true)
        } else {
            Image(systemName: "pause.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }
}

/// Compact artwork for now-playing rows.
struct CompactArtwork: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService

    var body: some View {
        ArtworkView(image: nowPlaying.artwork,
                    size: 22,
                    style: settings.artworkStyle,
                    isPlaying: nowPlaying.snapshot.isPlaying,
                    cornerRadius: 6,
                    fallbackIcon: nowPlaying.appIcon)
    }
}

/// Compact island while music plays: artwork left, visualiser right.
struct CompactNowPlayingView: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        CompactRow(notch: vm.notch,
                   side: IslandLayout.sideWidth(for: .nowPlaying, hudStyle: settings.hudStyle),
                   radii: IslandLayout.radii(for: .nowPlaying, hudStyle: settings.hudStyle)) {
            CompactArtwork()
        } trailing: {
            NowPlayingIndicator()
        }
    }
}
