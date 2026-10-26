import Foundation
import SwiftUI
import AppKit
import DynaNotchCore

/// Four animated bars (Core Animation, see `VisualizerBarsLayer`).
struct AudioVisualizerView: View {
    let color: Color
    let isPlaying: Bool

    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 14

    var body: some View {
        // Core Animation layers: no per-frame work in the app (see LayerAnimations.swift).
        VisualizerBarsLayer(color: NSColor(color), isPlaying: isPlaying, barWidth: barWidth, maxHeight: maxHeight)
            .frame(width: 4 * barWidth + 3 * 2, height: maxHeight)
    }

}
