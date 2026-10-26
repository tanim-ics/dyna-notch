import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Colour components in 0...1.
public struct RGB: Equatable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}

public enum ColorMath {
    /// Saturation-weighted average, then brightness lifted to >= 0.55 (HSB) so it reads on black. Empty → white.
    public static func accent(fromPixels pixels: [RGB]) -> RGB {
        guard !pixels.isEmpty else { return RGB(r: 1, g: 1, b: 1) }
        var total = 0.0, r = 0.0, g = 0.0, b = 0.0
        for pixel in pixels {
            let p = RGB(r: clamp(pixel.r), g: clamp(pixel.g), b: clamp(pixel.b))
            let hsbValue = hsb(p)
            let weight = hsbValue.s * hsbValue.s * hsbValue.b + 0.02
            total += weight
            r += p.r * weight
            g += p.g * weight
            b += p.b * weight
        }
        let average = RGB(r: r / total, g: g / total, b: b / total)
        var (h, s, v) = hsb(average)
        if v < 0.55 { v = 0.55 }
        if s > 0.9 { s = 0.9 }
        return rgb(h: h, s: s, b: v)
    }

    /// Standard RGB → HSB, all components in 0...1 (h = 0 for greys).
    public static func hsb(_ c: RGB) -> (h: Double, s: Double, b: Double) {
        let r = clamp(c.r), g = clamp(c.g), b = clamp(c.b)
        let maxV = max(r, g, b), minV = min(r, g, b)
        let delta = maxV - minV
        let s = maxV > 0 ? delta / maxV : 0
        var h = 0.0
        if delta > 0 {
            if maxV == r {
                h = (g - b) / delta
                if h < 0 { h += 6 }
            } else if maxV == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6
        }
        return (h, s, maxV)
    }

    /// Standard HSB → RGB, h wraps around 0...1.
    public static func rgb(h: Double, s: Double, b: Double) -> RGB {
        let s = clamp(s), v = clamp(b)
        var hue = h.isFinite ? h.truncatingRemainder(dividingBy: 1) : 0
        if hue < 0 { hue += 1 }
        let scaled = hue * 6
        let sector = Int(scaled.rounded(.down)) % 6
        let f = scaled - scaled.rounded(.down)
        let p = v * (1 - s)
        let q = v * (1 - s * f)
        let t = v * (1 - s * (1 - f))
        switch sector {
        case 0: return RGB(r: v, g: t, b: p)
        case 1: return RGB(r: q, g: v, b: p)
        case 2: return RGB(r: p, g: v, b: t)
        case 3: return RGB(r: p, g: q, b: v)
        case 4: return RGB(r: t, g: p, b: v)
        default: return RGB(r: v, g: p, b: q)
        }
    }

    private static func clamp(_ x: Double) -> Double {
        x.isFinite ? min(1, max(0, x)) : 0
    }
}
