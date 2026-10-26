import SwiftUI
import AppKit
import DynaNotchCore

/// Album artwork in rounded or spinning-record (circle) style, with a placeholder.
struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let style: ArtworkStyle
    let isPlaying: Bool
    let cornerRadius: CGFloat
    /// Shown when there is no artwork (e.g. a browser video): the source app's icon.
    let fallbackIcon: NSImage?

    init(image: NSImage?, size: CGFloat, style: ArtworkStyle, isPlaying: Bool, cornerRadius: CGFloat,
         fallbackIcon: NSImage? = nil) {
        self.image = image
        self.fallbackIcon = fallbackIcon
        self.size = size
        self.style = style
        self.isPlaying = isPlaying
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if style == .circle, let image = image {
                // Spins on the render server (see LayerAnimations.swift), not in a 30 fps TimelineView.
                SpinningDiscLayer(image: image, isPlaying: isPlaying)
            } else if style == .circle {
                circleArt(angle: 0)
            } else {
                roundedArt
            }
        }
        .frame(width: size, height: size)
    }

    private var roundedArt: some View {
        imageContent
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Static disc (no artwork yet).
    private func circleArt(angle: Double) -> some View {
        ZStack {
            imageContent
                .frame(width: size, height: size)
                .clipShape(Circle())
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.18, height: size * 0.18)
        }
        .rotationEffect(.degrees(angle))
    }

    @ViewBuilder
    private var imageContent: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.08)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            if let icon = fallbackIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.62, height: size * 0.62)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: max(6, size * 0.42), weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
    }
}
