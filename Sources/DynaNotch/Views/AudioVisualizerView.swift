import Foundation
import SwiftUI
import DynaNotchCore

/// Four animated bars, deterministic pseudo-random motion.
struct AudioVisualizerView: View {
    let color: Color
    let isPlaying: Bool

    private static let frequencies: [Double] = [7.1, 9.3, 5.7, 8.4]
    private static let phases: [Double] = [0.0, 1.7, 3.1, 4.6]
    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            bars(time: context.date.timeIntervalSinceReferenceDate)
        }
        .frame(height: maxHeight)
    }

    private func bars(time: Double) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: maxHeight * fraction(index: index, time: time))
            }
        }
    }

    private func fraction(index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return 0.25 }
        let f = Self.frequencies[index % Self.frequencies.count]
        let p = Self.phases[index % Self.phases.count]
        let a = sin(time * f + p)
        let b = sin(time * f * 0.53 + p * 2.1)
        let v = 0.55 + 0.3 * a + 0.15 * b
        return CGFloat(max(0.15, min(1.0, v)))
    }
}
