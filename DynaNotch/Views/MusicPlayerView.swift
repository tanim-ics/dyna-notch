import SwiftUI

struct MusicPlayerView: View {
    @EnvironmentObject var musicVM: MusicViewModel

    var body: some View {
        HStack(spacing: 14) {
            // Album art / thumbnail
            albumArtView

            // Right side: info + progress + controls
            VStack(alignment: .leading, spacing: 8) {
                // App source badge
                if !musicVM.appName.isEmpty {
                    Text(musicVM.appName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }

                // Title & artist
                VStack(alignment: .leading, spacing: 2) {
                    Text(musicVM.title.isEmpty ? "Nothing Playing" : musicVM.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(musicVM.artist.isEmpty ? "Open Spotify, Apple Music or YouTube Music" : musicVM.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                // Progress bar
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.12))
                        .frame(height: 3)
                    GeometryReader { g in
                        Capsule()
                            .fill(.white.opacity(0.8))
                            .frame(width: g.size.width * progressFraction, height: 3)
                    }
                    .frame(height: 3)
                }
                .animation(.linear(duration: 0.5), value: progressFraction)

                // Time labels
                HStack {
                    Text(formatTime(musicVM.progress))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text(formatTime(musicVM.duration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }

                // Playback controls
                HStack(spacing: 0) {
                    Spacer()
                    mediaButton("backward.fill",      size: 12) { musicVM.prevTrack() }
                    Spacer()
                    mediaButton(musicVM.isPlaying ? "pause.fill" : "play.fill", size: 17) { musicVM.playPause() }
                    Spacer()
                    mediaButton("forward.fill",       size: 12) { musicVM.nextTrack() }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Helpers
    private var progressFraction: Double {
        guard musicVM.duration > 0 else { return 0 }
        return min(max(musicVM.progress / musicVM.duration, 0.0), 1.0)
    }

    private func formatTime(_ t: Double) -> String {
        let t = Int(max(t, 0))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    @ViewBuilder
    private var albumArtView: some View {
        Group {
            if let art = musicVM.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if musicVM.appName.localizedCaseInsensitiveContains("youtube") {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.9, green: 0.12, blue: 0.18), Color(red: 0.45, green: 0.04, blue: 0.08)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 5) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("YT Music")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            } else {
                // Placeholder with gradient
                LinearGradient(colors: [Color(white: 0.18), Color(white: 0.10)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        Image(systemName: musicVM.isPlaying ? "music.note" : "music.note.list")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.white.opacity(0.25))
                    )
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    }

    private func mediaButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(BounceButtonStyle())
    }
}

// MARK: – Button press bounce style
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1.0)
            .opacity(configuration.isPressed ? 0.75 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
