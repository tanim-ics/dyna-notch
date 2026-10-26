import SwiftUI
import DynaNotchCore

/// Slim capsule level indicator.
struct LevelBar: View {
    let level: Double
    var color: Color = .white

    private var clamped: CGFloat {
        CGFloat(max(0, min(1, level.isFinite ? level : 0)))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: level)
    }
}
