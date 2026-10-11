import SwiftUI

// MARK: - Face parts

enum EyeKind { case round, half, happy, sleepy, star, flat }

struct EyeView: View, Equatable {
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

// MARK: - Static layers (value-equal so SwiftUI skips them while only transforms change)

private enum Face {
    static let bw = 116.0, bh = 92.0
    static let lx = 34.0, rx = 82.0
    static func eyeY(_ pose: MascotPose) -> Double { pose == .paused ? 50 : 47 }
}

/// The squircle body with its gradients, outline and highlight.
struct StaticBody: View, Equatable {
    var body: some View {
        ZStack {
            MochiBodyShape().fill(Palette.body)
            MochiBodyShape().fill(
                RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)],
                               center: UnitPoint(x: 0.28, y: 0.2), startRadius: 0, endRadius: 75))
            MochiBodyShape().fill(
                LinearGradient(colors: [Palette.blush.opacity(0), Palette.blush.opacity(0.28)],
                               startPoint: UnitPoint(x: 0.4, y: 0.5), endPoint: UnitPoint(x: 0.9, y: 1)))
            MochiBodyShape().stroke(Palette.ink.opacity(0.15), lineWidth: 1.5)
            Ellipse().fill(.white.opacity(0.55)).frame(width: 17, height: 8)
                .rotationEffect(.degrees(-28)).position(x: 24, y: 17).blur(radius: 1.2)
        }
        .frame(width: Face.bw, height: Face.bh)
    }
}

/// Two leaves and a stem, anchored at the bottom centre of a 56x36 box.
struct SproutLeaves: View, Equatable {
    var drooped: Bool
    var body: some View {
        let leafAngle: Double = drooped ? 72 : 34
        ZStack(alignment: .bottom) {
            leaf(angle: -leafAngle - (drooped ? 22 : 0))
            leaf(angle: leafAngle)
            Capsule().fill(Palette.sprout).frame(width: 4.5, height: 9)
        }
        .frame(width: 56, height: 36, alignment: .bottom)
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
}

struct BlushGroup: View, Equatable {
    var pose: MascotPose
    var hover: Bool
    var body: some View {
        let y = Face.eyeY(pose) + 14
        ZStack {
            ForEach([20.0, 96.0], id: \.self) { x in
                Ellipse().fill(Palette.blush.opacity(hover ? 1 : 0.8))
                    .frame(width: 18, height: 11)
                    .blur(radius: 0.6)
                    .position(x: x, y: y)
            }
        }
        .frame(width: Face.bw, height: Face.bh)
    }
}

struct EyesGroup: View, Equatable {
    var pose: MascotPose
    var open: Double
    var star: Bool
    var body: some View {
        let y = Face.eyeY(pose)
        let kind: EyeKind
        var scale = 1.0
        var dy = 0.0
        switch pose {
        case .idle: kind = .round
        case .working: kind = .round; scale = 0.82
        case .almostDone: kind = .half; dy = 1
        case .breakDue: kind = star ? .star : .happy
        case .onBreak: kind = .sleepy
        case .paused: kind = .flat
        }
        return ZStack {
            EyeView(kind: kind, open: open, scale: scale).position(x: Face.lx, y: y + dy)
            EyeView(kind: kind, open: open, scale: scale).position(x: Face.rx, y: y + dy)
        }
        .frame(width: Face.bw, height: Face.bh)
    }
}

struct MouthGroup: View, Equatable {
    var pose: MascotPose
    var yawn: Double = 0
    var body: some View {
        let y = Face.eyeY(pose)
        ZStack {
            switch pose {
            case .idle:
                OmegaMouth().stroke(Palette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 9, height: 3.5).position(x: 58, y: y + 12)
            case .working:
                Capsule().fill(Palette.ink).frame(width: 6, height: 2.2).position(x: 58, y: y + 13)
            case .almostDone:
                if yawn > 0.05 {
                    ZStack {
                        Ellipse().fill(Palette.ink)
                        Ellipse().fill(Palette.blush).frame(width: 6 * yawn, height: 5 * yawn).offset(y: 3 * yawn)
                    }
                    .frame(width: 5 + 6 * yawn, height: 3 + 11 * yawn)
                    .position(x: 58, y: y + 13)
                } else {
                    Capsule().fill(Palette.ink).frame(width: 5, height: 2.2).position(x: 58, y: y + 13)
                }
            case .breakDue:
                ZStack {
                    HappyMouth().fill(Palette.ink)
                    HappyMouth().fill(Palette.blush).frame(width: 7, height: 4).offset(y: 2.5)
                        .mask(HappyMouth())
                }
                .frame(width: 11, height: 6).position(x: 58, y: y + 12)
            case .onBreak:
                Ellipse().fill(Palette.ink).frame(width: 4, height: 3.4).position(x: 58, y: y + 13)
            case .paused:
                Capsule().fill(Palette.ink).frame(width: 7, height: 2.2).position(x: 58, y: y + 13)
            }
        }
        .frame(width: Face.bw, height: Face.bh)
    }
}

struct ShadowLayer: View, Equatable {
    var air: Double
    var wide: Bool
    var body: some View {
        // Soft radial falloff instead of a blur filter (cheap to redraw, no offscreen pass).
        let k = 1 - 0.28 * air
        Ellipse()
            .fill(RadialGradient(colors: [Palette.ink.opacity(0.2 * (1 - 0.35 * air)), Palette.ink.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: 52 * k * (wide ? 1.1 : 1)))
            .frame(width: 108 * k * (wide ? 1.1 : 1), height: 16 * k)
            .position(x: 100, y: 141)
            .frame(width: 200, height: 150)
    }
}

struct ArmView: View {
    var angle: Double
    var body: some View {
        ZStack {
            Capsule().fill(Palette.body)
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
            Capsule().stroke(Palette.ink.opacity(0.15), lineWidth: 1.2)
        }
        .frame(width: 11, height: 22)
        .rotationEffect(.degrees(angle), anchor: .bottom)
        .position(x: Face.bw - 3, y: 52)
        .frame(width: Face.bw, height: Face.bh)
    }
}

/// Positions the sprout on top of the body, rotating around its base.
private struct SproutSlot: View {
    var pose: MascotPose
    var rotation: Double
    var body: some View {
        SproutLeaves(drooped: pose == .paused).equatable()
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .position(x: Face.bw / 2, y: 5 - 18)
            .frame(width: Face.bw, height: Face.bh)
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
            ShadowLayer(air: 0, wide: pose == .paused).equatable()
                .scaleEffect(1 - 0.28 * m.air, anchor: UnitPoint(x: 0.5, y: 141.0 / 150))
                .opacity(1 - 0.3 * m.air)
            bodyGroup(m)
                .scaleEffect(x: m.sx * (1 + 0.15 * s), y: m.sy * (1 - 0.15 * s), anchor: .bottom)
                .rotationEffect(.degrees(leaning ? 4 : 0), anchor: .bottom)
                .offset(y: m.dy)
                .position(x: 100, y: groundY - Face.bh / 2)
            if pose == .breakDue { twinkles }
            if pose == .onBreak { ZFloat(p: t / 3.6) }
            if celebrate > 0 { SparkleBurst(c: celebrate) }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: hover)
    }

    private func motion() -> Motion {
        var m = Motion.make(pose, t: t, blinkT: blinkT)
        if celebrate > 0 { m.applyCelebrate(celebrate) }
        return m
    }

    private func bodyGroup(_ m: Motion) -> some View {
        let star = Int(floor(t / 1.8)) % 2 == 1
        return ZStack {
            SproutSlot(pose: pose, rotation: pose == .paused ? 14 : m.sway)
            StaticBody().equatable()
            BlushGroup(pose: pose, hover: hover).equatable()
            EyesGroup(pose: pose, open: m.eyeOpen, star: star).equatable()
            MouthGroup(pose: pose, yawn: m.yawn).equatable()
            if pose == .breakDue { ArmView(angle: 28 + 30 * sin(2 * .pi * t / 0.45)) }
        }
        .frame(width: Face.bw, height: Face.bh)
    }

    private var twinkles: some View {
        ZStack {
            SparklePoint(color: Palette.peach, size: 15, phase: t / 1.1).position(x: 28, y: 52)
            SparklePoint(color: Palette.breakRing, size: 11, phase: t / 1.3 + 0.35).position(x: 178, y: 36)
            SparklePoint(color: Palette.peach, size: 9, phase: t / 0.9 + 0.7).position(x: 40, y: 22)
        }
    }
}

extension Motion {
    /// Happy hop after finishing a break: one hop, then a soft landing squash.
    mutating func applyCelebrate(_ c: Double) {
        let hp = min(c / 0.5, 1)
        dy -= 24 * sin(.pi * hp)
        let land = c > 0.5 ? sin(.pi * min((c - 0.5) / 0.2, 1)) : 0
        sy -= 0.08 * land; sx += 0.05 * land
        air = max(air, sin(.pi * hp))
    }
}

/// Drifting "z Z z". `p` is the (unbounded) phase; animatable so a linear repeat can drive it.
struct ZFloat: View, Animatable {
    var p: Double
    nonisolated var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { k in
                let q = (p + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                Text(k == 1 ? "Z" : "z")
                    .font(.mochi(11 + 8 * q, .heavy))
                    .foregroundStyle(Palette.breakRing)
                    .opacity(sin(.pi * q) * 0.95)
                    .position(x: 150 + 20 * q + 4 * sin(q * 2 * .pi), y: 62 - 44 * q)
            }
        }
        .frame(width: 200, height: 150)
    }
}

struct SparkleBurst: View {
    var c: Double
    var body: some View {
        let ease = 1 - pow(1 - c, 3)
        let colors = [Palette.peach, Palette.breakRing, Palette.sprout, Palette.blush]
        ZStack {
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
}

// MARK: - Calm figure

/// Low-CPU Mochi. The pose is rasterized once into a few CALayers (crisp 3x images, cached) and all
/// motion is Core Animation (`CABasicAnimation` / keyframes running in the render server), so the
/// app does no per-frame work at all. Click squish / the celebrate hop are applied as plain transforms.
struct CalmFigure: View {
    let pose: MascotPose
    let hover: Bool
    let squish: Double
    let celebrate: Double
    @Environment(\.colorScheme) private var scheme

    nonisolated init(pose: MascotPose, hover: Bool, squish: Double, celebrate: Double) {
        self.pose = pose; self.hover = hover; self.squish = squish; self.celebrate = celebrate
    }

    var body: some View {
        ZStack {
            LayerFigure(pose: pose, hover: hover, squish: squish, celebrate: celebrate, scheme: scheme)
                .frame(width: 200, height: 150)
            if celebrate > 0 { SparkleBurst(c: celebrate) }
        }
        .frame(width: 200, height: 150)
        .allowsHitTesting(false)
    }
}

private struct LayerFigure: NSViewRepresentable {
    let pose: MascotPose
    let hover: Bool
    let squish: Double
    let celebrate: Double
    let scheme: ColorScheme

    func makeNSView(context: Context) -> CalmLayerHost {
        let v = CalmLayerHost()
        v.build(pose: pose, scheme: scheme)
        v.apply(hover: hover, squish: squish, celebrate: celebrate)
        return v
    }

    func updateNSView(_ v: CalmLayerHost, context: Context) {
        if v.pose != pose || v.scheme != scheme { v.build(pose: pose, scheme: scheme) }
        v.apply(hover: hover, squish: squish, celebrate: celebrate)
    }
}

/// Rasterized parts of one pose.
private struct CalmParts {
    var shadow: CGImage?, sprout: CGImage?, body: CGImage?, blush: CGImage?, blushStrong: CGImage?
    var eyes: CGImage?, eyesStar: CGImage?, mouth: CGImage?, mouthOpen: CGImage?, arm: CGImage?
    var twinkles: [CGImage?] = [], zs: [CGImage?] = []
}

@MainActor
private enum CalmImageCache {
    static let scale: CGFloat = 3
    static var cache: [String: CalmParts] = [:]

    static func render<V: View>(_ view: V, scheme: ColorScheme) -> CGImage? {
        let r = ImageRenderer(content: view.frame(width: 200, height: 150).environment(\.colorScheme, scheme))
        r.scale = scale
        return r.cgImage
    }

    /// Places a 116x92 body-space view on the 200x150 canvas.
    private static func inBody<V: View>(_ v: V) -> some View {
        v.frame(width: 116, height: 92).position(x: 100, y: 94).frame(width: 200, height: 150)
    }

    static func parts(_ pose: MascotPose, scheme: ColorScheme) -> CalmParts {
        let key = "\(pose.rawValue)-\(scheme == .dark ? "d" : "l")"
        if let c = cache[key] { return c }
        var p = CalmParts()
        p.shadow = render(ShadowLayer(air: 0, wide: pose == .paused), scheme: scheme)
        p.sprout = render(inBody(SproutSlot(pose: pose, rotation: pose == .paused ? 14 : 0)), scheme: scheme)
        p.body = render(inBody(StaticBody()), scheme: scheme)
        p.blush = render(inBody(BlushGroup(pose: pose, hover: false)), scheme: scheme)
        p.blushStrong = render(inBody(BlushGroup(pose: pose, hover: true)), scheme: scheme)
        p.eyes = render(inBody(EyesGroup(pose: pose, open: pose == .almostDone ? 0.55 : 1, star: false)), scheme: scheme)
        p.mouth = render(inBody(MouthGroup(pose: pose)), scheme: scheme)
        switch pose {
        case .breakDue:
            p.eyesStar = render(inBody(EyesGroup(pose: pose, open: 1, star: true)), scheme: scheme)
            p.arm = render(inBody(ArmView(angle: 0)), scheme: scheme)
            let spots: [(CGPoint, Double, Color)] = [
                (CGPoint(x: 28, y: 52), 15, Palette.peach), (CGPoint(x: 178, y: 36), 11, Palette.breakRing),
                (CGPoint(x: 40, y: 22), 9, Palette.peach)]
            p.twinkles = spots.map { sp in
                render(SparkleShape().fill(sp.2).frame(width: sp.1, height: sp.1).position(sp.0), scheme: scheme)
            }
        case .almostDone:
            p.mouthOpen = render(inBody(MouthGroup(pose: pose, yawn: 1)), scheme: scheme)
        case .onBreak:
            p.zs = (0..<3).map { k in
                render(Text(k == 1 ? "Z" : "z").font(.mochi(15, .heavy)).foregroundStyle(Palette.breakRing)
                    .position(x: 150, y: 62), scheme: scheme)
            }
        default: break
        }
        cache[key] = p
        return p
    }
}

/// Plain NSView hosting the layer tree; never takes mouse events (SwiftUI handles taps/drags).
final class CalmLayerHost: NSView {
    private(set) var pose: MascotPose?
    private(set) var scheme: ColorScheme?
    private let lean = CALayer(), squishL = CALayer()
    private var strong: CALayer?
    private let canvas = CGRect(x: 0, y: 0, width: 200, height: 150)

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 150))
        wantsLayer = true
        layer?.masksToBounds = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 150) }

    /// A canvas-sized layer showing `image`, whose anchor is at `anchor` (top-left canvas coords).
    private func part(_ image: CGImage?, anchor: CGPoint = CGPoint(x: 100, y: 75)) -> CALayer {
        let l = CALayer()
        l.bounds = canvas
        l.anchorPoint = CGPoint(x: anchor.x / 200, y: 1 - anchor.y / 150)
        l.position = CGPoint(x: anchor.x, y: 150 - anchor.y)
        l.contentsScale = CalmImageCache.scale
        l.contents = image
        return l
    }

    private func container(_ anchor: CGPoint = CGPoint(x: 100, y: 140)) -> CALayer { part(nil, anchor: anchor) }

    private static func loop(_ key: String, from: Double, to: Double, half: Double, delay: Double = 0) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from; a.toValue = to
        a.duration = half
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.beginTime = delay == 0 ? 0 : CACurrentMediaTime() + delay
        a.fillMode = .both
        return a
    }

    private static func keyframes(_ key: String, values: [Double], times: [Double], duration: Double) -> CAKeyframeAnimation {
        let a = CAKeyframeAnimation(keyPath: key)
        a.values = values; a.keyTimes = times.map { NSNumber(value: $0) }
        a.duration = duration
        a.repeatCount = .infinity
        a.calculationMode = .linear
        return a
    }

    func build(pose: MascotPose, scheme: ColorScheme) {
        self.pose = pose; self.scheme = scheme
        guard let root = layer else { return }
        root.sublayers?.forEach { $0.removeFromSuperlayer() }
        let parts = MainActor.assumeIsolated { CalmImageCache.parts(pose, scheme: scheme) }

        let still = pose == .paused
        let shadow = part(parts.shadow, anchor: CGPoint(x: 100, y: 141))
        root.addSublayer(shadow)

        // lean (hover) > squish/celebrate > stretch (yawn) > breath > bounce > parts
        let stretch = container(), breath = container(), bounce = container()
        for l in [lean, squishL] { l.sublayers = nil; l.anchorPoint = CGPoint(x: 0.5, y: 1 - 140.0 / 150); l.bounds = canvas; l.position = CGPoint(x: 100, y: 10) }
        root.addSublayer(lean); lean.addSublayer(squishL)
        squishL.addSublayer(stretch); stretch.addSublayer(breath); breath.addSublayer(bounce)

        let sprout = part(parts.sprout, anchor: CGPoint(x: 100, y: 53))
        bounce.addSublayer(sprout)
        bounce.addSublayer(part(parts.body))
        bounce.addSublayer(part(parts.blush))
        let strongL = part(parts.blushStrong); strongL.opacity = 0
        bounce.addSublayer(strongL); strong = strongL

        let eyesAnchor = CGPoint(x: 100, y: 48 + Double(pose == .paused ? 50 : 47))
        let eyes = part(parts.eyes, anchor: eyesAnchor)
        let mouth = part(parts.mouth)
        bounce.addSublayer(eyes)
        var eyesStar: CALayer?
        if let img = parts.eyesStar { eyesStar = part(img, anchor: eyesAnchor); bounce.addSublayer(eyesStar!) }
        bounce.addSublayer(mouth)
        var mouthOpen: CALayer?
        if let img = parts.mouthOpen {
            mouthOpen = part(img, anchor: CGPoint(x: 100, y: 48 + 47 + 13)); mouthOpen!.opacity = 0
            bounce.addSublayer(mouthOpen!)
        }
        var arm: CALayer?
        if let img = parts.arm { arm = part(img, anchor: CGPoint(x: 155, y: 111)); bounce.addSublayer(arm!) }

        var twinkleLayers: [CALayer] = []
        let tw: [CGPoint] = [CGPoint(x: 28, y: 52), CGPoint(x: 178, y: 36), CGPoint(x: 40, y: 22)]
        for (i, img) in parts.twinkles.enumerated() { let l = part(img, anchor: tw[i]); root.addSublayer(l); twinkleLayers.append(l) }
        var zLayers: [CALayer] = []
        for img in parts.zs { let l = part(img, anchor: CGPoint(x: 150, y: 62)); root.addSublayer(l); zLayers.append(l) }

        guard !still else { return }

        // ---- animations (all run in the render server) ----
        let breathAmp: Double, breathHalf: Double, swayDeg: Double, swayHalf: Double
        switch pose {
        case .almostDone: (breathAmp, breathHalf, swayDeg, swayHalf) = (0.03, 2.25, 3, 1.7)
        case .onBreak: (breathAmp, breathHalf, swayDeg, swayHalf) = (0.04, 2.5, 3, 2)
        case .breakDue: (breathAmp, breathHalf, swayDeg, swayHalf) = (0, 1, 9, 0.5)
        default: (breathAmp, breathHalf, swayDeg, swayHalf) = (0.025, 1.5, pose == .idle ? 6 : 3.5, 1.3)
        }
        if breathAmp > 0 {
            breath.add(Self.loop("transform.scale.y", from: 1 - breathAmp, to: 1 + breathAmp, half: breathHalf), forKey: "by")
            breath.add(Self.loop("transform.scale.x", from: 1 + breathAmp * 0.5, to: 1 - breathAmp * 0.5, half: breathHalf), forKey: "bx")
        }
        sprout.add(Self.loop("transform.rotation.z", from: swayDeg * .pi / 180, to: -swayDeg * .pi / 180, half: swayHalf), forKey: "sway")

        // blink: one quick squash every ~4.6 s
        if pose == .idle || pose == .working || pose == .almostDone {
            eyes.add(Self.keyframes("transform.scale.y", values: [1, 1, 0.08, 1], times: [0, 0.955, 0.975, 1], duration: 4.6), forKey: "blink")
        }
        switch pose {
        case .almostDone:
            let d = 8.4
            let t = [0, 0.55, 0.62, 0.78, 0.86, 1.0]
            stretch.add(Self.keyframes("transform.scale.y", values: [1, 1, 1.08, 1.08, 1, 1], times: t, duration: d), forKey: "stretch")
            mouth.add(Self.keyframes("opacity", values: [1, 1, 0, 0, 1, 1], times: t, duration: d), forKey: "m")
            mouthOpen?.add(Self.keyframes("opacity", values: [0, 0, 1, 1, 0, 0], times: t, duration: d), forKey: "mo")
            mouthOpen?.add(Self.keyframes("transform.scale", values: [0.2, 0.2, 1, 1, 0.2, 0.2], times: t, duration: d), forKey: "ms")
        case .breakDue:
            let half = 0.5
            bounce.add(Self.loop("transform.translation.y", from: 0, to: 15, half: half), forKey: "hop")
            bounce.add(Self.loop("transform.scale.y", from: 0.92, to: 1.05, half: half), forKey: "hy")
            bounce.add(Self.loop("transform.scale.x", from: 1.07, to: 0.97, half: half), forKey: "hx")
            shadow.add(Self.loop("transform.scale", from: 1, to: 0.78, half: half), forKey: "sh")
            arm?.add(Self.loop("transform.rotation.z", from: -(-2.0) * .pi / 180, to: -58.0 * .pi / 180, half: 0.3), forKey: "wave")
            // happy eyes <-> sparkle eyes every 1.8 s
            let d = 3.6
            eyes.add(Self.keyframes("opacity", values: [1, 1, 0, 0, 1], times: [0, 0.48, 0.5, 0.98, 1], duration: d), forKey: "o")
            eyesStar?.add(Self.keyframes("opacity", values: [0, 0, 1, 1, 0], times: [0, 0.48, 0.5, 0.98, 1], duration: d), forKey: "o")
            for (i, l) in twinkleLayers.enumerated() {
                l.add(Self.loop("transform.scale", from: 0.35, to: 1, half: 0.55 + 0.12 * Double(i), delay: 0.2 * Double(i)), forKey: "s")
                l.add(Self.loop("opacity", from: 0.35, to: 1, half: 0.55 + 0.12 * Double(i), delay: 0.2 * Double(i)), forKey: "o")
            }
        case .onBreak:
            let d = 3.6
            for (k, l) in zLayers.enumerated() {
                let up = Self.keyframes("transform.translation.y", values: [0, 44], times: [0, 1], duration: d)
                let dx = Self.keyframes("transform.translation.x", values: [0, 20], times: [0, 1], duration: d)
                let op = Self.keyframes("opacity", values: [0, 0.95, 0], times: [0, 0.5, 1], duration: d)
                let sc = Self.keyframes("transform.scale", values: [0.73, 1.27], times: [0, 1], duration: d)
                let g = CAAnimationGroup()
                g.animations = [up, dx, op, sc]
                g.duration = d; g.repeatCount = .infinity
                g.timeOffset = Double(k) * d / 3
                l.opacity = 0
                l.add(g, forKey: "z")
            }
        default: break
        }
    }

    /// Hover lean (implicitly animated) and click-squish / celebrate hop (applied directly).
    func apply(hover: Bool, squish: Double, celebrate: Double) {
        let s = max(0, min(1, squish))
        var m = Motion()
        if celebrate > 0 { m.applyCelebrate(celebrate) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var t = CATransform3DMakeTranslation(0, CGFloat(-m.dy), 0)
        t = CATransform3DScale(t, CGFloat(m.sx * (1 + 0.15 * s)), CGFloat(m.sy * (1 - 0.15 * s)), 1)
        squishL.transform = t
        CATransaction.commit()

        let target = CATransform3DMakeRotation(hover ? -4 * .pi / 180 : 0, 0, 0, 1)
        if !CATransform3DEqualToTransform(lean.transform, target) {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.25)
            lean.transform = target
            CATransaction.commit()
        }
        let strongOpacity: Float = hover ? 1 : 0
        if strong?.opacity != strongOpacity {
            CATransaction.begin(); CATransaction.setAnimationDuration(0.2)
            strong?.opacity = strongOpacity
            CATransaction.commit()
        }
    }
}
