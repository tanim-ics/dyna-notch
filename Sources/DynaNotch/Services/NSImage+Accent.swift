import AppKit
import Foundation
import DynaNotchCore

extension NSImage {
    /// Samples the image into a 12×12 bitmap and derives an accent colour that reads well on black
    /// (see `ColorMath.accent`). Safe to call off the main thread. Returns white for empty images.
    func dominantAccentColor() -> NSColor {
        let side = 12
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return .white }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return .white }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .medium
        draw(in: NSRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)),
             from: .zero,
             operation: .copy,
             fraction: 1.0)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return .white }
        let bytesPerRow = rep.bytesPerRow
        let bytesPerPixel = max(4, rep.bitsPerPixel / 8)
        var pixels: [RGB] = []
        pixels.reserveCapacity(side * side)
        for y in 0..<side {
            for x in 0..<side {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let alpha = Double(data[offset + 3]) / 255.0
                if alpha < 0.5 { continue }
                // The bitmap is premultiplied: undo it.
                let r = min(1.0, Double(data[offset]) / 255.0 / alpha)
                let g = min(1.0, Double(data[offset + 1]) / 255.0 / alpha)
                let b = min(1.0, Double(data[offset + 2]) / 255.0 / alpha)
                pixels.append(RGB(r: r, g: g, b: b))
            }
        }
        let accent = ColorMath.accent(fromPixels: pixels)
        return NSColor(srgbRed: CGFloat(accent.r), green: CGFloat(accent.g), blue: CGFloat(accent.b), alpha: 1)
    }
}
