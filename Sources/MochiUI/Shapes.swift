import SwiftUI

/// Mochi's body: a soft squircle, a bit wider at the bottom.
struct MochiBodyShape: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y)
        }
        var path = Path()
        path.move(to: p(0.5, 0))
        path.addCurve(to: p(1, 0.60), control1: p(0.80, 0), control2: p(1, 0.26))
        path.addCurve(to: p(0.5, 1), control1: p(1, 0.90), control2: p(0.80, 1))
        path.addCurve(to: p(0, 0.60), control1: p(0.20, 1), control2: p(0, 0.90))
        path.addCurve(to: p(0.5, 0), control1: p(0, 0.26), control2: p(0.20, 0))
        path.closeSubpath()
        return path
    }
}

/// A teardrop leaf growing upward from its bottom-centre.
struct LeafShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.midX - w * 0.75, y: r.maxY - h * 0.25),
                   control2: CGPoint(x: r.midX - w * 0.55, y: r.minY + h * 0.2))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.midX + w * 0.55, y: r.minY + h * 0.2),
                   control2: CGPoint(x: r.midX + w * 0.75, y: r.maxY - h * 0.25))
        p.closeSubpath()
        return p
    }
}

/// Concave four-point twinkle.
struct SparkleShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let rx = r.width / 2, ry = r.height / 2
        let k = 0.14
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - ry))
        p.addQuadCurve(to: CGPoint(x: c.x + rx, y: c.y), control: CGPoint(x: c.x + rx * k, y: c.y - ry * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + ry), control: CGPoint(x: c.x + rx * k, y: c.y + ry * k))
        p.addQuadCurve(to: CGPoint(x: c.x - rx, y: c.y), control: CGPoint(x: c.x - rx * k, y: c.y + ry * k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - ry), control: CGPoint(x: c.x - rx * k, y: c.y - ry * k))
        p.closeSubpath()
        return p
    }
}

/// A single arc spanning the rect: `up` = hill (^), otherwise a bowl (u).
struct ArcLine: Shape {
    var up: Bool
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY), control: CGPoint(x: r.midX, y: r.minY - r.height))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY + r.height))
        }
        return p
    }
}

/// Cat-like "ω" mouth.
struct OmegaMouth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.15))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY + r.height * 0.15),
                       control: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY + r.height * 0.5))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.15),
                       control: CGPoint(x: r.minX + r.width * 0.75, y: r.maxY + r.height * 0.5))
        return p
    }
}

/// Open happy mouth: flat top, round bottom ("D" rotated).
struct HappyMouth: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY),
                   control1: CGPoint(x: r.maxX - r.width * 0.05, y: r.maxY + r.height * 0.3),
                   control2: CGPoint(x: r.minX + r.width * 0.05, y: r.maxY + r.height * 0.3))
        p.closeSubpath()
        return p
    }
}
