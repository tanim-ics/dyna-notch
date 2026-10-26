import SwiftUI
import AppKit
import DynaNotchCore

/// Now Playing: player on the left, synced lyrics on the right.
struct NowPlayingTab: View {
    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var settings: AppSettings
    /// Right column shows the listening history instead of the lyrics.
    @State private var showsHistory = false

    var body: some View {
        if nowPlaying.snapshot.isEmpty {
            PanelEmptyState(symbol: "music.note",
                            title: "Nothing playing",
                            detail: "Play something in Spotify, Music or your browser")
        } else {
            HStack(alignment: .top, spacing: 18) {
                NowPlayingPlayer(showsHistory: $showsHistory)
                    .frame(width: 310)
                if showsHistory && settings.listeningHistory {
                    ListeningHistoryPanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LyricsPanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - Player

struct NowPlayingPlayer: View {
    @Binding var showsHistory: Bool

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService
    @ObservedObject private var listening = ListeningHistoryService.shared

    /// History entry of the track playing now (if recorded).
    private var currentEntry: ListenEntry? {
        listening.history.entries.first {
            $0.title == nowPlaying.snapshot.title && $0.artist == nowPlaying.snapshot.artist
        }
    }

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
        historyButtons
    }

    /// ☆ bookmark + History toggle (Settings → Now Playing → Listening History).
    @ViewBuilder
    private var historyButtons: some View {
        if settings.listeningHistory {
            HStack(spacing: 2) {
                let bookmarked = currentEntry?.bookmarked ?? false
                PanelIconButton(symbol: bookmarked ? "star.fill" : "star", size: 11, frame: 22,
                                tint: bookmarked ? Color.yellow : Color.white.opacity(0.7),
                                help: bookmarked ? "Remove bookmark" : "Bookmark this track") {
                    if let entry = currentEntry, entry.bookmarked {
                        listening.toggleBookmark(entry)
                    } else {
                        listening.bookmarkCurrent()
                    }
                }
                .uiTestID("np.bookmark")
                PanelIconButton(symbol: "clock.arrow.circlepath", size: 11, frame: 22,
                                tint: showsHistory ? Color.white : Color.white.opacity(0.7),
                                help: showsHistory ? "Show lyrics" : "Listening history") {
                    showsHistory.toggle()
                }
                .uiTestID("np.history")
            }
            .padding(.top, 2)
        }
    }
}

/// Recent plays and bookmarks (ListeningHistoryService).
struct ListeningHistoryPanel: View {
    @ObservedObject private var listening = ListeningHistoryService.shared
    @State private var bookmarksOnly = false

    private var entries: [ListenEntry] {
        Array((bookmarksOnly ? listening.history.bookmarks : listening.history.entries).prefix(40))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("History")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                Spacer(minLength: 4)
                ForEach([false, true], id: \.self) { only in
                    Button {
                        bookmarksOnly = only
                    } label: {
                        Text(only ? "Bookmarks" : "Recent")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(bookmarksOnly == only ? Color.white : PanelStyle.secondary)
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Capsule().fill(Color.white.opacity(bookmarksOnly == only ? 0.16 : 0.05)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .uiTestID(only ? "np.history.bookmarks" : "np.history.recent")
                }
            }
            if entries.isEmpty {
                PanelEmptyState(symbol: bookmarksOnly ? "star" : "music.note.list",
                                title: bookmarksOnly ? "No bookmarks yet" : "No history yet",
                                detail: bookmarksOnly ? "Tap ☆ next to a track to keep it here" : "Tracks you play show up here")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
    }

    private func row(_ entry: ListenEntry) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                Text(entry.artist)
                    .font(.system(size: 9.5))
                    .foregroundStyle(PanelStyle.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(entry.playedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                .font(.system(size: 9))
                .foregroundStyle(PanelStyle.tertiary)
                .lineLimit(1)
            Button {
                listening.toggleBookmark(entry)
            } label: {
                Image(systemName: entry.bookmarked ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundStyle(entry.bookmarked ? Color.yellow : PanelStyle.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .frame(height: 28)
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
        .accessibilityLabel(currentName)
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
                                 current: lyrics.currentIndex(at: nowPlaying.snapshot.elapsed(at: context.date) + AppSettings.shared.lyricsOffset))
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
