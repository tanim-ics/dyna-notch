import SwiftUI
import DynaNotchCore

/// The island outline: concave "ears" at the top corners (merging into the menu bar)
/// and convex rounded corners at the bottom. Both radii are animatable.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    init(topRadius: CGFloat, bottomRadius: CGFloat) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    init(radii: IslandRadii) {
        self.topRadius = radii.top
        self.bottomRadius = radii.bottom
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        guard w > 0, h > 0 else { return path }

        let top = max(0, min(topRadius, w / 4, h / 2))
        let bottom = max(0, min(bottomRadius, (w - 2 * top) / 2, h - top))
        let x0 = rect.minX
        let y0 = rect.minY

        path.move(to: CGPoint(x: x0, y: y0))
        path.addQuadCurve(to: CGPoint(x: x0 + top, y: y0 + top),
                          control: CGPoint(x: x0 + top, y: y0))
        path.addLine(to: CGPoint(x: x0 + top, y: y0 + h - bottom))
        path.addQuadCurve(to: CGPoint(x: x0 + top + bottom, y: y0 + h),
                          control: CGPoint(x: x0 + top, y: y0 + h))
        path.addLine(to: CGPoint(x: x0 + w - top - bottom, y: y0 + h))
        path.addQuadCurve(to: CGPoint(x: x0 + w - top, y: y0 + h - bottom),
                          control: CGPoint(x: x0 + w - top, y: y0 + h))
        path.addLine(to: CGPoint(x: x0 + w - top, y: y0 + top))
        path.addQuadCurve(to: CGPoint(x: x0 + w, y: y0),
                          control: CGPoint(x: x0 + w - top, y: y0))
        path.closeSubpath()
        return path
    }
}
