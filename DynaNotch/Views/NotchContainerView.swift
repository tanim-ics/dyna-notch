import SwiftUI
import Combine

struct NotchContainerView: View {
    @EnvironmentObject var vm: NotchViewModel
    @ObservedObject private var musicVM = MusicViewModel.shared

    var body: some View {
        Group {
            if vm.isTucked {
                // Ultra-thin 2px hairline capsule when tucked
                Capsule()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 64, height: 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.untuck()
                    }
            } else {
                ZStack(alignment: .center) {
                    // Black pill background
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black)
                        .shadow(color: .black.opacity(vm.isExpanded ? 0.5 : 0.25),
                                radius: vm.isExpanded ? 24 : 8,
                                y:      vm.isExpanded ? 12 : 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                        )

                    // Content
                    if vm.isExpanded {
                        expandedView
                            .transition(.asymmetric(
                                insertion: .opacity.animation(.easeIn(duration: 0.12).delay(0.1)),
                                removal:   .opacity.animation(.easeOut(duration: 0.08))
                            ))
                    } else {
                        collapsedView
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity((vm.hovering || vm.isExpanded) ? 1.0 : vm.idleOpacity)
                .animation(.easeInOut(duration: 0.25), value: vm.hovering)
                .animation(.easeInOut(duration: 0.25), value: vm.isExpanded)
                .animation(.easeInOut(duration: 0.25), value: vm.idleOpacity)
                .onHover { vm.setHovering($0) }
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            vm.toggleTuck()
                        }
                        .exclusively(before:
                            TapGesture(count: 1)
                                .onEnded {
                                    vm.toggleExpand()
                                }
                        )
                )
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onEnded { val in
                            let dx = val.translation.width
                            let dy = val.translation.height
                            if abs(dx) > abs(dy) && abs(dx) > 28 {
                                if dx > 0 {
                                    vm.nextTrack()
                                } else {
                                    vm.prevTrack()
                                }
                            } else if dy < -10 {
                                vm.tuck()
                            } else if dy > 18 && !vm.isExpanded {
                                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                    vm.toggleExpand()
                                }
                            }
                        }
                )
                .animation(.spring(response: 0.36, dampingFraction: 0.76), value: vm.isExpanded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var cornerRadius: CGFloat { vm.isExpanded ? 24 : 17 }

    private func formatTime(_ t: Double) -> String {
        let t = Int(max(t, 0))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    @ViewBuilder
    private func collapsedArtwork(size: CGFloat) -> some View {
        if let art = musicVM.albumArt {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        } else if musicVM.appName.localizedCaseInsensitiveContains("youtube") {
            ZStack {
                LinearGradient(colors: [Color(red: 0.92, green: 0.1, blue: 0.14), Color(red: 0.65, green: 0.05, blue: 0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "play.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.20), lineWidth: 0.5)
            )
        } else {
            ZStack {
                Color.white.opacity(0.12)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.48))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    // MARK: – Collapsed pill
    private var collapsedView: some View {
        Group {
            if vm.showMusicWidget && !musicVM.title.isEmpty {
                // Unified, continuous Dynamic Island capsule
                HStack(spacing: 8) {
                    collapsedArtwork(size: 24)

                    // Title & Artist
                    VStack(alignment: .leading, spacing: 1) {
                        Text(musicVM.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if !musicVM.artist.isEmpty {
                            Text(musicVM.artist)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: 150, alignment: .leading)

                    Spacer(minLength: 8)

                    // Current Elapsed Time / Total Song Duration
                    Text("\(formatTime(musicVM.progress)) / \(formatTime(musicVM.duration))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))

                    if musicVM.isPlaying {
                        EqualizerBarsView()
                            .frame(width: 15, height: 11)
                    } else {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, 12)
            } else {
                // Quick glanceable status (Alcove Clock & Date)
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))

                    Text(Date.now.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))

                    Circle()
                        .fill(.white.opacity(0.3))
                        .frame(width: 3, height: 3)

                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).day()))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: – Expanded content
    @ViewBuilder
    private var expandedView: some View {
        Group {
            switch vm.activeContent {
            case .music, .none:
                MusicPlayerView()
                    .environmentObject(musicVM)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            case .hud(let type):
                HUDView(type: type)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            case .notification(let n):
                NotificationView(notification: n)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: – Animated equalizer bars
struct EqualizerBarsView: View {
    @State private var heights: [CGFloat] = [0.4, 0.7, 0.5, 0.9, 0.6]
    private let timer = Timer.publish(every: 0.18, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.4))
                    .frame(width: 2, height: max(12 * heights[i], 2))
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                var next = heights
                for i in next.indices {
                    next[i] = .random(in: 0.2...1.0)
                }
                heights = next
            }
        }
    }
}
