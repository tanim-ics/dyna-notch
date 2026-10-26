import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Size of the (physical or simulated) notch on a screen, in points.
public struct NotchMetrics: Equatable {
    public var width: CGFloat
    public var height: CGFloat
    public var hasPhysicalNotch: Bool

    public init(width: CGFloat, height: CGFloat, hasPhysicalNotch: Bool) {
        self.width = width
        self.height = height
        self.hasPhysicalNotch = hasPhysicalNotch
    }

    /// 185 × 32, no physical notch.
    public static let fallback = NotchMetrics(width: 185, height: 32, hasPhysicalNotch: false)

    static let defaultWidth: CGFloat = 185

    /// Physical notch if `safeAreaTop > 0`: height = safeAreaTop, width = screenWidth - leftAux - rightAux
    /// (when both aux widths are given and the result lies in 80...400), else 185.
    /// No notch: width 185, height = max(24, menuBarHeight).
    public static func compute(screenWidth: CGFloat, safeAreaTop: CGFloat, leftAuxWidth: CGFloat?,
                               rightAuxWidth: CGFloat?, menuBarHeight: CGFloat) -> NotchMetrics {
        if safeAreaTop > 0 {
            var width = defaultWidth
            if let left = leftAuxWidth, let right = rightAuxWidth {
                let candidate = screenWidth - left - right
                if candidate >= 80 && candidate <= 400 {
                    width = candidate
                }
            }
            return NotchMetrics(width: width, height: safeAreaTop, hasPhysicalNotch: true)
        }
        return NotchMetrics(width: defaultWidth, height: max(24, menuBarHeight), hasPhysicalNotch: false)
    }
}
