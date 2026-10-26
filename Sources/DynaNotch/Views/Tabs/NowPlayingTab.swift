import SwiftUI
import AppKit
import DynaNotchCore

/// Now Playing: player on the left, synced lyrics on the right.
struct NowPlayingTab: View {
    @EnvironmentObject var nowPlaying: NowPlayingService

    var body: some View {
        if nowPlaying.snapshot.isEmpty {
            PanelEmptyState(symbol: "music.note",
                            title: "Nothing playing",
                            detail: "Play something in Spotify, Music or your browser")
        } else {
            HStack(alignment: .top, spacing: 18) {
                NowPlayingPlayer()
                    .frame(width: 310)
                LyricsPanel()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Player

struct NowPlayingPlayer: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService

    private var accent: Color { Color(nsColor: nowPlaying.accentColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ArtworkView(image: nowPlaying.artwork,
                            size: 80,
                            style: settings.artworkStyle,
                            isPlaying: nowPlaying.snapshot.isPlaying,
                            cornerRadius: 12,
                            fallbackIcon: nowPlaying.appIcon)
                    .shadow(color: settings.artworkGlow ? accent.opacity(0.55) : Color.clear, radius: 14)
                titles
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                ProgressBlock(snapshot: nowPlaying.snapshot, date: context.date, accent: accent)
            }
            NowPlayingTransport()
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(nowPlaying.snapshot.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)
            Text(nowPlaying.snapshot.artist)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
            sourceBadge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if !nowPlaying.appName.isEmpty || nowPlaying.appIcon != nil {
            HStack(spacing: 4) {
                if let icon = nowPlaying.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 13, height: 13)
                }
                Text(nowPlaying.appName)
                    .font(.system(size: 10))
                    .foregroundStyle(PanelStyle.tertiary)
                    .lineLimit(1)
            }
            .padding(.top, 2)
        }
    }
}

struct NowPlayingTransport: View {
    @EnvironmentObject var nowPlaying: NowPlayingService

    var body: some View {
        HStack(spacing: 6) {
            button("gobackward.15", size: 13) { skip(by: -15) }
            button("backward.fill", size: 14) { nowPlaying.previous() }
            button(nowPlaying.snapshot.isPlaying ? "pause.fill" : "play.fill", size: 20) {
                nowPlaying.togglePlayPause()
            }
            button("forward.fill", size: 14) { nowPlaying.next() }
            button("goforward.15", size: 13) { skip(by: 15) }
            Spacer(minLength: 4)
            OutputDeviceMenu()
        }
    }

    private func button(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 26)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func skip(by delta: Double) {
        let snapshot = nowPlaying.snapshot
        var target = snapshot.elapsed(at: Date()) + delta
        target = max(0, target)
        if snapshot.duration > 0 { target = min(target, snapshot.duration) }
        nowPlaying.seek(to: target)
    }
}

struct OutputDeviceMenu: View {
    @EnvironmentObject var audio: AudioDeviceService

    var body: some View {
        Menu {
            if audio.outputs.isEmpty {
                Text("No output devices")
            }
            ForEach(audio.outputs) { device in
                Button {
                    audio.select(device)
                } label: {
                    if device.id == audio.currentOutputID {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: "hifispeaker.2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(currentName)
    }

    private var currentName: String {
        audio.outputs.first(where: { $0.id == audio.currentOutputID })?.name ?? "Output device"
    }
}

// MARK: - Lyrics

struct LyricsPanel: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var lyrics: LyricsService
    @EnvironmentObject var nowPlaying: NowPlayingService

    var body: some View {
        content
            .mask(fadeMask)
    }

    @ViewBuilder
    private var content: some View {
        if !settings.lyricsEnabled {
            LyricsMessage(text: "Lyrics are off")
        } else if !lyrics.lines.isEmpty {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                SyncedLyricsList(lines: lyrics.lines,
                                 current: lyrics.currentIndex(at: nowPlaying.snapshot.elapsed(at: context.date)))
            }
        } else if !lyrics.plain.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                Text(lyrics.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            }
        } else if lyrics.isLoading {
            LyricsMessage(text: "Searching lyrics…")
        } else {
            LyricsMessage(text: "No lyrics")
        }
    }

    private var fadeMask: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.12),
            .init(color: .black, location: 0.88),
            .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}

struct LyricsMessage: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "quote.bubble")
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(PanelStyle.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SyncedLyricsList: View {
    let lines: [LyricLine]
    let current: Int?

    @EnvironmentObject var nowPlaying: NowPlayingService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    Color.clear.frame(height: 40)
                    ForEach(Array(lines.enumerated()), id: \.offset) { item in
                        lineView(item.element, index: item.offset)
                            .id(item.offset)
                    }
                    Color.clear.frame(height: 40)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { scroll(proxy, animated: false) }
            .onChange(of: current) {
                scroll(proxy, animated: true)
            }
        }
    }

    private func lineView(_ line: LyricLine, index: Int) -> some View {
        let isCurrent = index == current
        return Text(line.text.isEmpty ? "♪" : line.text)
            .font(.system(size: isCurrent ? 13 : 12, weight: isCurrent ? .bold : .medium))
            .foregroundStyle(Color.white.opacity(isCurrent ? 1 : 0.45))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { nowPlaying.seek(to: line.time) }
            .animation(.easeInOut(duration: 0.2), value: isCurrent)
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let current = current else { return }
        if animated && !reduceMotion {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                proxy.scrollTo(current, anchor: .center)
            }
        } else {
            proxy.scrollTo(current, anchor: .center)
        }
    }
}
