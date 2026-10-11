import SwiftUI

// MARK: - Face parts

enum EyeKind { case round, half, happy, sleepy, star, flat }

struct EyeView: View {
    var kind: EyeKind
    var open: Double = 1
    var scale: Double = 1
    var ink: Color { Palette.ink }

    var body: some View {
        ZStack {
            switch kind {
            case .round: round(w: 13, h: 16)
            case .star: starEye
            case .half: halfEye
            case .happy:
                ArcLine(up: true).stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 13, height: 5)
            case .sleepy:
                ArcLine(up: false).stroke(ink, style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
                    .frame(width: 13, height: 3.5)
            case .flat:
                Capsule().fill(ink).frame(width: 11, height: 2.8)
            }
        }
        .frame(width: 18, height: 20)
    }

    private func round(w: Double, h: Double) -> some View {
        let o = max(open, 0.1)
        return ZStack {
            Ellipse().fill(ink).frame(width: w * scale * (1 + (1 - o) * 0.12), height: h * scale * o)
            if o > 0.55 {
                Circle().fill(.white).frame(width: 5 * scale, height: 5 * scale)
                    .offset(x: -2.3 * scale, y: -3.2 * scale * o)
                Circle().fill(.white.opacity(0.9)).frame(width: 2.3 * scale, height: 2.3 * scale)
                    .offset(x: 2.6 * scale, y: 3.2 * scale * o)
            }
        }
    }

    private var starEye: some View {
        ZStack {
            Ellipse().fill(ink).frame(width: 15, height: 18)
            SparkleShape().fill(.white).frame(width: 9, height: 9).offset(x: -1.5, y: -2.5)
            Circle().fill(.white.opacity(0.9)).frame(width: 2.6, height: 2.6).offset(x: 3.2, y: 4)
        }
    }

    private var halfEye: some View {
        let cut = 9.0 * max(open, 0.15)
        return ZStack {
            Ellipse().fill(ink).frame(width: 13, height: 16)
                .mask(alignment: .bottom) { Rectangle().frame(height: cut) }
                .offset(y: 0)
            if open > 0.5 {
                Circle().fill(.white).frame(width: 3.8, height: 3.8).offset(x: -2, y: 8 - cut + 3.6)
            }
        }
    }
}

struct SparklePoint: View {
    var color: Color
    var size: Double
    var phase: Double
    var body: some View {
        let s = 0.55 + 0.45 * sin(phase * 2 * .pi)
        SparkleShape().fill(color)
            .frame(width: size, height: size)
            .scaleEffect(max(s, 0.05))
            .rotationEffect(.degrees(phase * 40))
            .opacity(0.35 + 0.65 * max(s, 0))
    }
}

// MARK: - Motion model

struct Motion {
    var sx = 1.0, sy = 1.0, dy = 0.0
    var sway = 0.0          // sprout sway degrees
    var eyeOpen = 1.0
    var yawn = 0.0
    var air = 0.0           // 0 on ground, 1 at apex (bounce)

    static func blink(_ bt: Double) -> Double {
        let ph = (bt + 1.9).truncatingRemainder(dividingBy: 3.7)
        if ph >= 0, ph < 0.12 { return 1 - 0.93 * sin(.pi * ph / 0.12) }
        return 1
    }

    static func make(_ pose: MascotPose, t: Double, blinkT: Double) -> Motion {
        var m = Motion()
        let tau = 2 * Double.pi
        switch pose {
        case .idle, .working:
            let b = sin(tau * t / 3)
            m.sy = 1 + 0.025 * b
            m.sx = 1 - 0.012 * b
            m.sway = (pose == .idle ? 6 : 3.5) * sin(tau * t / 2.6)
            m.eyeOpen = blink(blinkT)
        case .almostDone:
            let b = sin(tau * t / 4.5)
            m.sy = 1 + 0.03 * b
            m.sx = 1 - 0.015 * b
            m.sway = 3 * sin(tau * t / 3.4)
            let u = (t / 4.2).truncatingRemainder(dividingBy: 1)
            if u > 0.55, u < 0.88 {
                let w = sin(.pi * (u - 0.55) / 0.33)
                m.yawn = w
                m.sy += 0.08 * w
                m.sx -= 0.03 * w
            }
            m.eyeOpen = blink(blinkT) * (1 - 0.8 * m.yawn)
        case .breakDue:
            let ph = (t / 0.9).truncatingRemainder(dividingBy: 1)
            let air = 4 * ph * (1 - ph)
            let ground = max(0, 1 - air / 0.22)
            m.air = air
            m.dy = -15 * air
            m.sy = 1 + 0.05 * air - 0.09 * ground
            m.sx = 1 - 0.03 * air + 0.07 * ground
            m.sway = 9 * sin(tau * t / 0.9)
        case .onBreak:
            let b = sin(tau * t / 5)
            m.sy = 1 + 0.04 * b
            m.sx = 1 - 0.02 * b
            m.sway = 3 * sin(tau * t / 4)
        case .paused:
            m.sy = 0.92
            m.sx = 1.06
        }
        return m
    }
}

// MARK: - Figure

/// Pure, static drawing of Mochi at time `t` (seconds). Deterministic.
public struct MascotFigure: View {
    public static let canvasSize = CGSize(width: 200, height: 150)

    let pose: MascotPose
    let t: Double
    let blinkT: Double
    let hover: Bool
    let squish: Double
    let celebrate: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let bw = 116.0, bh = 92.0
    private let groundY = 140.0

    public init(pose: MascotPose, t: Double, hover: Bool = false, squish: Double = 0) {
        self.init(pose: pose, t: t, blinkT: t, hover: hover, squish: squish, celebrate: 0)
    }

    nonisolated init(pose: MascotPose, t: Double, blinkT: Double, hover: Bool, squish: Double, celebrate: Double) {
        self.pose = pose; self.t = t; self.blinkT = blinkT; self.hover = hover; self.squish = squish
        self.celebrate = celebrate
    }

    public var body: some View {
        let m = motion()
        let s = max(0, min(1, squish))
        let leaning = hover && !reduceMotion
        ZStack {
            shadow(m)
            bodyGroup(m)
                .scaleEffect(x: m.sx * (1 + 0.15 * s), y: m.sy * (1 - 0.15 * s), anchor: .bottom)
                .rotationEffect(.degrees(leaning ? 4 : 0), anchor: .bottom)
                .offset(y: m.dy)
                .position(x: 100, y: groundY - bh / 2)
            if pose == .breakDue { twinkles }
            if celebrate > 0 { burst }
            if pose == .onBreak { zLetters }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: hover)
    }

    private func motion() -> Motion {
        var m = Motion.make(pose, t: t, blinkT: blinkT)
        if celebrate > 0 {
            // Happy hop after finishing a break: one hop, then a soft landing squash.
            let hp = min(celebrate / 0.5, 1)
            m.dy -= 24 * sin(.pi * hp)
            let land = celebrate > 0.5 ? sin(.pi * min((celebrate - 0.5) / 0.2, 1)) : 0
            m.sy -= 0.08 * land; m.sx += 0.05 * land
            m.air = max(m.air, sin(.pi * hp))
        }
        return m
    }

    // MARK: pieces

    private func shadow(_ m: Motion) -> some View {
        let k = 1 - 0.28 * m.air
        let wide = pose == .paused ? 1.1 : 1.0
        return Ellipse().fill(Palette.ink.opacity(0.16 * (1 - 0.35 * m.air)))
            .frame(width: 92 * k * wide, height: 11 * k)
            .blur(radius: 2.5)
            .position(x: 100, y: groundY + 1)
    }

    private func bodyGroup(_ m: Motion) -> some View {
        ZStack {
            sprout(m)
            bodyShape
            face(m)
            if pose == .breakDue { arm }
        }
        .frame(width: bw, height: bh)
    }

    private var bodyShape: some View {
        ZStack {
            MochiBodyShape().fill(Palette.body)
            MochiBodyShape().fill(
                RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)],
                               center: UnitPoint(x: 0.28, y: 0.2), startRadius: 0, endRadius: 75))
            MochiBodyShape().fill(
                LinearGradient(colors: [Palette.blush.opacity(0), Palette.blush.opacity(0.28)],
                               startPoint: UnitPoint(x: 0.4, y: 0.5), endPoint: UnitPoint(x: 0.9, y: 1)))
            MochiBodyShape().stroke(Palette.ink.opacity(0.15), lineWidth: 1.5)
            // soft highlight
            Ellipse().fill(.white.opacity(0.55)).frame(width: 17, height: 8)
                .rotationEffect(.degrees(-28)).position(x: 24, y: 17).blur(radius: 1.2)
        }
        .frame(width: bw, height: bh)
    }

    private func sprout(_ m: Motion) -> some View {
        let drooped = pose == .paused
        let leafAngle: Double = drooped ? 72 : 34
        return ZStack(alignment: .bottom) {
            leaf(angle: -leafAngle - (drooped ? 22 : 0))
            leaf(angle: leafAngle)
            Capsule().fill(Palette.sprout).frame(width: 4.5, height: 9)
        }
        .frame(width: 56, height: 36, alignment: .bottom)
        .rotationEffect(.degrees(drooped ? 14 : m.sway), anchor: .bottom)
        .position(x: bw / 2, y: 5 - 18)
    }

    private func leaf(angle: Double) -> some View {
        ZStack {
            LeafShape().fill(Palette.sprout)
            LeafShape().fill(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
            LeafShape().stroke(Palette.ink.opacity(0.13), lineWidth: 1)
            Capsule().fill(Palette.ink.opacity(0.10)).frame(width: 1.2, height: 14).offset(y: 3)
        }
        .frame(width: 21, height: 31)
        .rotationEffect(.degrees(angle), anchor: .bottom)
    }

    private var arm: some View {
        let ang = 28 + 30 * sin(2 * .pi * t / 0.45)
        return ZStack {
            Capsule().fill(Palette.body)
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
            Capsule().stroke(Palette.ink.opacity(0.15), lineWidth: 1.2)
        }
        .frame(width: 11, height: 22)
        .rotationEffect(.degrees(ang), anchor: .bottom)
        .position(x: bw - 3, y: 52)
    }

    // MARK: face

    @ViewBuilder
    private func face(_ m: Motion) -> some View {
        let eyeY = pose == .paused ? 50.0 : 47.0
        let lx = 34.0, rx = 82.0
        ZStack {
            // blush
            ForEach([20.0, 96.0], id: \.self) { x in
                Ellipse().fill(Palette.blush.opacity(hover ? 1 : 0.8))
                    .frame(width: 18, height: 11)
                    .blur(radius: 0.6)
                    .position(x: x, y: eyeY + 14)
            }
            switch pose {
            case .idle:
                EyeView(kind: .round, open: m.eyeOpen).position(x: lx, y: eyeY)
                EyeView(kind: .round, open: m.eyeOpen).position(x: rx, y: eyeY)
                OmegaMouth().stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 9, height: 3.5).position(x: 58, y: eyeY + 12)
            case .working:
                EyeView(kind: .round, open: m.eyeOpen, scale: 0.82).position(x: lx, y: eyeY)
                EyeView(kind: .round, open: m.eyeOpen, scale: 0.82).position(x: rx, y: eyeY)
                Capsule().fill(Palette.ink).frame(width: 6, height: 2.2).position(x: 58, y: eyeY + 13)
            case .almostDone:
                EyeView(kind: .half, open: m.eyeOpen).position(x: lx, y: eyeY + 1)
                EyeView(kind: .half, open: m.eyeOpen).position(x: rx, y: eyeY + 1)
                if m.yawn > 0.05 {
                    ZStack {
                        Ellipse().fill(Palette.ink)
                        Ellipse().fill(Palette.blush).frame(width: 6 * m.yawn, height: 5 * m.yawn).offset(y: 3 * m.yawn)
                    }
                    .frame(width: 5 + 6 * m.yawn, height: 3 + 11 * m.yawn)
                    .position(x: 58, y: eyeY + 13)
                } else {
                    Capsule().fill(Palette.ink).frame(width: 5, height: 2.2).position(x: 58, y: eyeY + 13)
                }
            case .breakDue:
                let star = Int(floor(t / 1.8)) % 2 == 1
                EyeView(kind: star ? .star : .happy).position(x: lx, y: eyeY)
                EyeView(kind: star ? .star : .happy).position(x: rx, y: eyeY)
                ZStack {
                    HappyMouth().fill(Palette.ink)
                    HappyMouth().fill(Palette.blush).frame(width: 7, height: 4).offset(y: 2.5)
                        .mask(HappyMouth())
                }
                .frame(width: 11, height: 6).position(x: 58, y: eyeY + 12)
            case .onBreak:
                EyeView(kind: .sleepy).position(x: lx, y: eyeY)
                EyeView(kind: .sleepy).position(x: rx, y: eyeY)
                Ellipse().fill(Palette.ink).frame(width: 4, height: 3.4).position(x: 58, y: eyeY + 13)
            case .paused:
                EyeView(kind: .flat).position(x: lx, y: eyeY)
                EyeView(kind: .flat).position(x: rx, y: eyeY)
                Capsule().fill(Palette.ink).frame(width: 7, height: 2.2).position(x: 58, y: eyeY + 13)
            }
        }
        .frame(width: bw, height: bh)
    }

    // MARK: effects (figure space)

    private var twinkles: some View {
        ZStack {
            SparklePoint(color: Palette.peach, size: 15, phase: t / 1.1).position(x: 28, y: 52)
            SparklePoint(color: Palette.breakRing, size: 11, phase: t / 1.3 + 0.35).position(x: 178, y: 36)
            SparklePoint(color: Palette.peach, size: 9, phase: t / 0.9 + 0.7).position(x: 40, y: 22)
        }
    }

    private var burst: some View {
        let c = celebrate
        let ease = 1 - pow(1 - c, 3)
        let colors = [Palette.peach, Palette.breakRing, Palette.sprout, Palette.blush]
        return ZStack {
            ForEach(0..<8, id: \.self) { k in
                let a = Double(k) / 8 * 2 * .pi + 0.3
                SparkleShape().fill(colors[k % 4])
                    .frame(width: 13 * (1 - 0.5 * c), height: 13 * (1 - 0.5 * c))
                    .rotationEffect(.degrees(c * 90))
                    .opacity(min(1, (1 - c) * 1.6))
                    .position(x: 100 + cos(a) * (38 + 52 * ease), y: 85 + sin(a) * (30 + 42 * ease))
            }
        }
    }

    private var zLetters: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { k in
                let p = (t / 3.6 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                Text(k == 1 ? "Z" : "z")
                    .font(.mochi(11 + 8 * p, .heavy))
                    .foregroundStyle(Palette.breakRing)
                    .opacity(sin(.pi * p) * 0.95)
                    .position(x: 150 + 20 * p + 4 * sin(p * 2 * .pi), y: 62 - 44 * p)
            }
        }
    }
}
