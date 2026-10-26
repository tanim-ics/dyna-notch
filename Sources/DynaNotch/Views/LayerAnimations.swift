import AppKit
import SwiftUI

// Continuous decorative motion (visualiser bars, spinning vinyl) as Core Animation layers with repeating
// animations: the render server runs them, so the app does no per-frame work. The SwiftUI TimelineView versions
// re-rendered the hosting view 30 times a second (≈ 8 % CPU while music played).

/// Four bars pulsing at different rates; flat when not playing.
struct VisualizerBarsLayer: NSViewRepresentable {
    let color: NSColor
    let isPlaying: Bool
    var barWidth: CGFloat = 2.5
    var spacing: CGFloat = 2
    var maxHeight: CGFloat = 14

    private static let durations: [CFTimeInterval] = [0.43, 0.37, 0.51, 0.46]
    private static let offsets: [CFTimeInterval] = [0.0, 0.21, 0.09, 0.33]

    /// Lays the bars out whenever the view's size changes (SwiftUI may update before the first layout).
    final class BarsView: NSView {
        var barWidth: CGFloat = 2.5
        var spacing: CGFloat = 2
        var maxHeight: CGFloat = 14
        var bars: [CALayer] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for _ in 0..<4 {
                let bar = CALayer()
                layer?.addSublayer(bar)
                bars.append(bar)
            }
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let total = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * spacing
            let originX = (bounds.width - total) / 2
            for (i, bar) in bars.enumerated() {
                bar.cornerRadius = barWidth / 2
                bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: maxHeight)
                bar.position = CGPoint(x: originX + CGFloat(i) * (barWidth + spacing) + barWidth / 2, y: bounds.midY)
            }
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> BarsView {
        let view = BarsView()
        view.barWidth = barWidth
        view.spacing = spacing
        view.maxHeight = maxHeight
        return view
    }

    func updateNSView(_ view: BarsView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in view.bars.enumerated() {
            bar.backgroundColor = color.cgColor
            if isPlaying {
                if bar.animation(forKey: "pulse") == nil {
                    bar.transform = CATransform3DIdentity
                    let pulse = CABasicAnimation(keyPath: "transform.scale.y")
                    pulse.fromValue = 0.2
                    pulse.toValue = 1.0
                    pulse.duration = Self.durations[i % Self.durations.count]
                    pulse.autoreverses = true
                    pulse.repeatCount = .infinity
                    pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    pulse.beginTime = CACurrentMediaTime() - Self.offsets[i % Self.offsets.count]
                    bar.add(pulse, forKey: "pulse")
                }
            } else {
                bar.removeAnimation(forKey: "pulse")
                bar.transform = CATransform3DMakeScale(1, 0.25, 1)
            }
        }
        CATransaction.commit()
    }
}

/// Round artwork with a centre hole that turns slowly while playing (18°/s) and holds its angle when paused.
struct SpinningDiscLayer: NSViewRepresentable {
    let image: NSImage
    let isPlaying: Bool

    final class DiscView: NSView {
        let disc = CALayer()
        let hole = CALayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            disc.masksToBounds = true
            disc.contentsGravity = .resizeAspectFill
            hole.backgroundColor = NSColor.black.cgColor
            disc.addSublayer(hole)
            layer?.addSublayer(disc)
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let side = min(bounds.width, bounds.height)
            disc.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            disc.position = CGPoint(x: bounds.midX, y: bounds.midY)
            disc.cornerRadius = side / 2
            let holeSide = side * 0.18
            hole.bounds = CGRect(x: 0, y: 0, width: holeSide, height: holeSide)
            hole.position = CGPoint(x: side / 2, y: side / 2)
            hole.cornerRadius = holeSide / 2
            CATransaction.commit()
        }
    }

    func makeNSView(context: Context) -> DiscView {
        let view = DiscView()
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi          // clockwise on screen
        spin.duration = 20                      // 18° per second
        spin.repeatCount = .infinity
        view.disc.add(spin, forKey: "spin")
        view.disc.speed = 0                     // starts paused; updateNSView resumes
        return view
    }

    func updateNSView(_ view: DiscView, context: Context) {
        view.disc.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let layer = view.disc
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        if isPlaying && layer.speed == 0 {
            // Resume from the held angle.
            let paused = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
        } else if !isPlaying && layer.speed != 0 {
            layer.speed = 0
            layer.timeOffset = now
        }
    }
}
