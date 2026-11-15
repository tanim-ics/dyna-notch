import SwiftUI
import AppKit
import CoreImage
import DynaNotchCore

/// Colourful Now Playing: the artwork, stretched sideways and blurred into soft streaks behind the Now Playing tab.
/// It fades to black under the notch row so the island still merges with the notch. A still picture: nothing here
/// redraws while a song plays.
struct NowPlayingBackdrop: View {
    @EnvironmentObject var vm: IslandViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var nowPlaying: NowPlayingService

    /// For `dynanotch://state`.
    static func isShown(vm: IslandViewModel) -> Bool {
        AppSettings.shared.colorfulNowPlaying && vm.visibleTab == .nowPlaying && vm.presentation == .expanded
            && NowPlayingService.shared.artwork != nil && !NowPlayingService.shared.snapshot.isEmpty
    }

    private var isShown: Bool {
        settings.colorfulNowPlaying && vm.visibleTab == .nowPlaying && nowPlaying.artwork != nil
            && !nowPlaying.snapshot.isEmpty
    }

    var body: some View {
        ZStack {
            if isShown, let art = nowPlaying.artwork, let streaks = BackdropRenderer.shared.streaks(for: art) {
                Image(decorative: streaks, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: vm.islandSize.width, height: vm.islandSize.height)
                    .opacity(0.8)
                    .mask(fade)
                    .transition(.opacity)
                    .id(ObjectIdentifier(art))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isShown)
        .animation(.easeInOut(duration: 0.6), value: nowPlaying.artwork.map { ObjectIdentifier($0) })
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Black through the notch row, then the colours come in.
    private var fade: some View {
        let notchStop = vm.islandSize.height > 0 ? min(0.9, vm.notch.height / vm.islandSize.height) : 0.2
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: notchStop * 0.8),
            .init(color: .black, location: min(1, notchStop + 0.3)),
            .init(color: .black, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// Turns a cover into a small, soft picture of sideways colour streaks (drawn once per cover, on the main queue;
/// 96 × 32 pixels, so it costs next to nothing and SwiftUI only has to stretch it).
final class BackdropRenderer {
    static let shared = BackdropRenderer()

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    private var lastArt: ObjectIdentifier?
    private var lastImage: CGImage?

    func streaks(for art: NSImage) -> CGImage? {
        let id = ObjectIdentifier(art)
        if id == lastArt { return lastImage }
        lastArt = id
        lastImage = render(art)
        return lastImage
    }

    private func render(_ art: NSImage) -> CGImage? {
        let size = CGSize(width: 96, height: 32)
        guard let source = art.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let bitmap = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        bitmap.interpolationQuality = .high
        bitmap.draw(source, in: CGRect(origin: .zero, size: size))   // squeezed flat: the stretch makes the streaks
        guard let small = bitmap.makeImage() else { return nil }
        let extent = CGRect(origin: .zero, size: size)
        var image = CIImage(cgImage: small).clampedToExtent()
        image = image.applyingFilter("CIMotionBlur", parameters: [kCIInputRadiusKey: 14, kCIInputAngleKey: 0])
        image = image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 2.5])
        image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.9,
                                                                     kCIInputBrightnessKey: -0.06,
                                                                     kCIInputContrastKey: 1.1])
        return context.createCGImage(image, from: extent)
    }
}
