import SwiftUI

/// The handwritten "hello" from the iPhone/Mac setup screen, as one continuous stroke so it can be drawn on
/// with `.trim(from:to:)`. Designed in a 720 × 340 box and scaled to fit the rect (aspect preserved).
struct HelloShape: Shape {
    static let designSize = CGSize(width: 720, height: 340)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / HelloShape.designSize.width, rect.height / HelloShape.designSize.height)
        let dx = rect.midX - HelloShape.designSize.width * scale / 2
        let dy = rect.midY - HelloShape.designSize.height * scale / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: dx + x * scale, y: dy + y * scale) }

        var path = Path()
        path.move(to: p(30, 300))
        // h
        path.addCurve(to: p(150, 42), control1: p(80, 280), control2: p(195, 95))
        path.addCurve(to: p(112, 300), control1: p(108, 8), control2: p(105, 230))
        path.addCurve(to: p(185, 205), control1: p(125, 235), control2: p(160, 205))
        path.addCurve(to: p(220, 292), control1: p(212, 205), control2: p(205, 280))
        // e
        path.addCurve(to: p(325, 225), control1: p(240, 305), control2: p(318, 268))
        path.addCurve(to: p(285, 185), control1: p(332, 196), control2: p(305, 180))
        path.addCurve(to: p(262, 260), control1: p(262, 190), control2: p(255, 235))
        path.addCurve(to: p(335, 295), control1: p(270, 300), control2: p(315, 305))
        // l
        path.addCurve(to: p(420, 42), control1: p(375, 280), control2: p(465, 95))
        path.addCurve(to: p(385, 300), control1: p(378, 8), control2: p(380, 230))
        path.addCurve(to: p(430, 295), control1: p(392, 312), control2: p(415, 305))
        // l
        path.addCurve(to: p(515, 42), control1: p(470, 280), control2: p(560, 95))
        path.addCurve(to: p(480, 300), control1: p(473, 8), control2: p(475, 230))
        path.addCurve(to: p(530, 292), control1: p(487, 312), control2: p(512, 305))
        // o
        path.addCurve(to: p(590, 205), control1: p(512, 240), control2: p(548, 203))
        path.addCurve(to: p(543, 250), control1: p(563, 205), control2: p(543, 225))
        path.addCurve(to: p(585, 296), control1: p(543, 280), control2: p(562, 296))
        path.addCurve(to: p(628, 250), control1: p(610, 296), control2: p(628, 275))
        path.addCurve(to: p(592, 206), control1: p(628, 222), control2: p(612, 204))
        path.addCurve(to: p(690, 205), control1: p(580, 214), control2: p(640, 218))
        return path
    }
}
