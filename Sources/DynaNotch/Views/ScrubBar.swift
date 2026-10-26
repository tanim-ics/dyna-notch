import SwiftUI
import DynaNotchCore

/// Draggable progress bar; sends `seek` on release.
struct ScrubBar: View {
    let progress: Double
    let duration: Double
    let color: Color

    @EnvironmentObject var nowPlaying: NowPlayingService
    @State private var dragFraction: Double?

    private var isDragging: Bool { dragFraction != nil }

    private var shownFraction: CGFloat {
        let value = dragFraction ?? progress
        return CGFloat(max(0, min(1, value.isFinite ? value : 0)))
    }

    var body: some View {
        GeometryReader { geo in
            track(width: geo.size.width)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(dragGesture(width: geo.size.width))
        }
        .frame(height: 12)
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    private func track(width: CGFloat) -> some View {
        let barHeight: CGFloat = isDragging ? 6 : 4
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: width, height: barHeight)
            Capsule()
                .fill(color)
                .frame(width: width * shownFraction, height: barHeight)
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
