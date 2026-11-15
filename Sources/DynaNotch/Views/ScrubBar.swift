import SwiftUI
import AppKit
import DynaNotchCore

/// Draggable progress bar; sends `seek` on release.
struct ScrubBar: View {
    let progress: Double
    let duration: Double
    let color: Color

    @EnvironmentObject var nowPlaying: NowPlayingService
    @EnvironmentObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragFraction: Double?

    /// Colourful Now Playing: the played part is a wave while the music plays, a plain bar otherwise.
    private var isWavy: Bool { settings.colorfulNowPlaying && nowPlaying.snapshot.isPlaying && !isDragging }

    private var isDragging: Bool { dragFraction != nil }

    private var shownFraction: CGFloat {
        let value = dragFraction ?? progress
        return CGFloat(max(0, min(1, value.isFinite ? value : 0)))
    }

    var body: some View {
        GeometryReader { geo in
            track(width: geo.size.width)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: geo.size.width))
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    private func track(width: CGFloat) -> some View {
        let barHeight: CGFloat = isDragging ? 6 : 4
        let played = width * shownFraction
        return ZStack(alignment: .leading) {
            if isWavy {
                // The rest of the track starts after the knob, so the wave has room to move.
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: max(0, width - played - 5), height: 3)
                    .offset(x: played + 5)
                WavyLineLayer(color: NSColor(color), isMoving: !reduceMotion)
                    .frame(width: max(0, played - 1), height: 12)
                    .allowsHitTesting(false)
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 11)
                    .offset(x: max(0, played - 1))
            } else {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: width, height: barHeight)
                Capsule()
                    .fill(color)
                    .frame(width: played, height: barHeight)
            }
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragFraction = fraction(x: value.location.x, width: width)
            }
            .onEnded { value in
                let f = fraction(x: value.location.x, width: width)
                if duration > 0 {
                    nowPlaying.seek(to: f * duration)
                }
                dragFraction = nil
            }
    }

    private func fraction(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(max(0, min(1, x / width)))
    }
}
