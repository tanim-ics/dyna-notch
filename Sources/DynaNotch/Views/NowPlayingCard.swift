import SwiftUI
import AppKit
import DynaNotchCore

/// Button style that shrinks while pressed.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Expanded now-playing card: artwork, title, artist, scrubber, times and controls.
struct NowPlayingCard: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService

    private var accent: Color { Color(nsColor: nowPlaying.accentColor) }

    var body: some View {
        if nowPlaying.snapshot.isEmpty {
            emptyState
        } else {
            playingState
        }
    }

    // MARK: - Playing

    private var playingState: some View {
        HStack(spacing: 14) {
            artwork
            VStack(alignment: .leading, spacing: 6) {
                titles
                progressSection
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var artwork: some View {
        ArtworkView(image: nowPlaying.artwork,
                    size: 92,
                    style: settings.artworkStyle,
                    isPlaying: nowPlaying.snapshot.isPlaying,
                    cornerRadius: 14,
                    fallbackIcon: nowPlaying.appIcon)
            .shadow(color: settings.artworkGlow ? accent.opacity(0.6) : Color.clear, radius: 16, x: 0, y: 0)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nowPlaying.snapshot.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            Text(nowPlaying.snapshot.artist)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var progressSection: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            ProgressBlock(snapshot: nowPlaying.snapshot, date: context.date, accent: accent)
        }
    }

    private var controls: some View {
        HStack(spacing: 22) {
            controlButton(symbol: "backward.fill", size: 15) { nowPlaying.previous() }
            controlButton(symbol: nowPlaying.snapshot.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                nowPlaying.togglePlayPause()
            }
            controlButton(symbol: "forward.fill", size: 15) { nowPlaying.next() }
        }
        .frame(maxWidth: .infinity)
    }

    private func controlButton(symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Empty

    private var emptyState: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Image(systemName: "music.note")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing playing")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                Text("Play something in Spotify, Music or your browser")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Scrub bar plus elapsed / duration labels for a given moment.
struct ProgressBlock: View {
    let snapshot: NowPlayingSnapshot
    let date: Date
    let accent: Color

    var body: some View {
        VStack(spacing: 2) {
            ScrubBar(progress: snapshot.progress(at: date), duration: snapshot.duration, color: accent)
            HStack {
                Text(Format.time(snapshot.elapsed(at: date)))
                Spacer(minLength: 8)
                Text(Format.time(snapshot.duration))
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(0.5))
        }
    }
}
