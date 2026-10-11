import SwiftUI

/// Soft ground ring: a flattened ellipse with a rounded progress arc.
public struct ProgressRing: View {
    public var progress: Double
    public var tint: Color

    public init(progress: Double, tint: Color) {
        self.progress = progress
        self.tint = tint
    }

    public var body: some View {
        let p = max(0, min(1, progress))
        ZStack {
            Ellipse().stroke(tint.opacity(0.15), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            Ellipse().trim(from: 0, to: p)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(180))
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((p * 100).rounded())) percent")
    }
}

/// Rounded speech bubble with a tail pointing down at the mascot.
public struct SpeechBubble: View {
    public var text: String
    var maxWidth: CGFloat = 216
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(text: String) { self.text = text }
    init(text: String, maxWidth: CGFloat) { self.text = text; self.maxWidth = maxWidth }

    public var body: some View {
        Text(text)
            .font(.mochi(13))
            .foregroundStyle(Palette.text)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: maxWidth)
            .padding(.bottom, 8) // room for the tail
            .background(
                BubbleShape()
                    .fill(Palette.bubbleBackground)
                    .overlay(BubbleShape().stroke(Palette.ink.opacity(0.12), lineWidth: 1))
                    .shadow(color: Palette.ink.opacity(0.14), radius: 5, y: 2)
            )
            .scaleEffect(shown || reduceMotion ? 1 : 0.6, anchor: .bottom)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { shown = true }
            }
            .accessibilityLabel(text)
    }
}

struct BubbleShape: Shape {
    func path(in r: CGRect) -> Path {
        let tailH = 8.0, tailW = 14.0
        let body = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - tailH)
        var p = Path(roundedRect: body, cornerRadius: 16, style: .continuous)
        var tail = Path()
        tail.move(to: CGPoint(x: r.midX - tailW / 2, y: body.maxY - 0.5))
        tail.addQuadCurve(to: CGPoint(x: r.midX, y: r.maxY), control: CGPoint(x: r.midX - 2, y: body.maxY + 1))
        tail.addQuadCurve(to: CGPoint(x: r.midX + tailW / 2, y: body.maxY - 0.5), control: CGPoint(x: r.midX + 2, y: body.maxY + 1))
        tail.closeSubpath()
        p.addPath(tail)
        return p
    }
}

// MARK: - Hit testing & panel state

/// Rects (in the scene's top-left coordinate space) that should receive mouse events.
struct HitRectsKey: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

struct BubbleSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Union of rects as a hit-testing shape; falls back to the full rect before layout reports any.
struct HitShape: Shape {
    var rects: [CGRect]
    func path(in r: CGRect) -> Path {
        guard !rects.isEmpty else { return Path(r) }
        var p = Path()
        for rect in rects { p.addRect(rect) }
        return p
    }
}

/// What the floating panel tells its content (defaults suit standalone use).
struct PanelState: Equatable, Sendable {
    var isActive = true
    var dragEpoch = 0
}

private struct PanelStateKey: EnvironmentKey { static let defaultValue = PanelState() }
extension EnvironmentValues {
    var mochiPanelState: PanelState {
        get { self[PanelStateKey.self] }
        set { self[PanelStateKey.self] = newValue }
    }
}

/// Small pill shown on hover (e.g. "12:34 left").
struct HoverPill: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.mochi(11))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Capsule().fill(Palette.bubbleBackground.opacity(0.92)))
            .overlay(Capsule().stroke(Palette.ink.opacity(0.1), lineWidth: 0.8))
            .shadow(color: Palette.ink.opacity(0.1), radius: 3, y: 1)
            .fixedSize()
    }
}

/// Static composition of bubble + ring + mascot at a given time. Used by `MascotView` and the preview tool.
public struct MascotScene: View {
    /// Base (medium) window size.
    public static let size = CGSize(width: 220, height: 230)

    /// Window size for a given mascot size (rounded to whole points).
    public static func size(for size: MascotSize) -> CGSize {
        // Width fits the widest bubble (216pt at bubble scale); height = figure block + headroom
        // for a 3-line bubble (~76pt at bubble scale).
        let w = max(Self.size.width * size.scale, 216 * size.bubbleScale + 4)
        let h = 152 * size.scale + 76 * size.bubbleScale + 2
        return CGSize(width: w.rounded(.up), height: h.rounded(.up))
    }

    let pose: MascotPose
    let progress: Double
    let bubbleText: String?
    let t: Double
    let blinkT: Double
    let hover: Bool
    let squish: Double
    let celebrate: Double
    let hoverText: String?
    let mascotSize: MascotSize
    @State private var bubbleSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public nonisolated init(pose: MascotPose, progress: Double, bubbleText: String?, t: Double,
                hover: Bool = false, squish: Double = 0, size: MascotSize = .medium,
                hoverText: String? = nil, celebrate: Double = 0) {
        self.init(pose: pose, progress: progress, bubbleText: bubbleText, t: t, blinkT: t,
                  hover: hover, squish: squish, size: size, hoverText: hoverText, celebrate: celebrate)
    }

    nonisolated init(pose: MascotPose, progress: Double, bubbleText: String?, t: Double, blinkT: Double,
         hover: Bool, squish: Double, size: MascotSize, hoverText: String?, celebrate: Double) {
        self.pose = pose; self.progress = progress; self.bubbleText = bubbleText
        self.t = t; self.blinkT = blinkT; self.hover = hover; self.squish = squish
        self.mascotSize = size; self.hoverText = hoverText; self.celebrate = celebrate
    }

    private var hasBubble: Bool { !(bubbleText ?? "").isEmpty }

    /// Rects that should catch the mouse: the figure block, plus the bubble when shown.
    private func hitRects(win: CGSize) -> [CGRect] {
        let s = mascotSize.scale, bs = mascotSize.bubbleScale
        let figW = 180 * s, figH = 142 * s
        var rects = [CGRect(x: (win.width - figW) / 2, y: win.height - figH, width: figW, height: figH)]
        if hasBubble, bubbleSize != .zero {
            let w = bubbleSize.width * bs, h = bubbleSize.height * bs
            let bottom = win.height - (164 - 12) * s
            rects.append(CGRect(x: (win.width - w) / 2, y: bottom - h, width: w, height: h))
        }
        return rects
    }

    public var body: some View {
        let s = mascotSize.scale
        let bs = mascotSize.bubbleScale
        let win = Self.size(for: mascotSize)
        let baseH = 164.0 // figure block height at medium
        ZStack(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                ProgressRing(progress: progress, tint: pose.ringTint)
                    .frame(width: 176, height: 40)
                    .offset(y: 10)
                MascotFigure(pose: pose, t: t, blinkT: blinkT, hover: hover, squish: squish, celebrate: celebrate)
            }
            .padding(.bottom, 14)
            .frame(width: Self.size.width, height: baseH)
            .scaleEffect(s, anchor: .bottom)
            .frame(width: win.width, height: baseH * s, alignment: .bottom)

            if let bubbleText, !bubbleText.isEmpty {
                SpeechBubble(text: bubbleText, maxWidth: min(216, (win.width - 4) / bs))
                    .background(GeometryReader { g in Color.clear.preference(key: BubbleSizeKey.self, value: g.size) })
                    .id(bubbleText)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                    .scaleEffect(bs, anchor: .bottom)
                    .padding(.bottom, (baseH - 12) * s)
            } else if let hoverText, hover {
                HoverPill(text: hoverText)
                    .transition(.opacity)
                    .padding(.bottom, (baseH - 6) * s)
            }
        }
        .frame(width: win.width, height: win.height, alignment: .bottom)
        .onPreferenceChange(BubbleSizeKey.self) { size in bubbleSize = size }
        .preference(key: HitRectsKey.self, value: hitRects(win: win))
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: bubbleText)
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

/// Live, animated Mochi: hover lean, click squish, Reduce Motion aware.
public struct MascotView: View {
    public var pose: MascotPose
    public var progress: Double
    public var bubbleText: String?
    public var size: MascotSize
    public var hoverText: String?
    public var onTap: (() -> Void)?

    @State private var hover = false
    @State private var tapCount = 0
    @State private var celebrateCount = 0
    @State private var start = Date()
    @State private var hitRects: [CGRect] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.mochiPanelState) private var panelState

    public init(pose: MascotPose, progress: Double, bubbleText: String?,
                size: MascotSize = .medium, hoverText: String? = nil, onTap: (() -> Void)? = nil) {
        self.size = size
        self.hoverText = hoverText
        self.pose = pose
        self.progress = progress
        self.bubbleText = bubbleText
        self.onTap = onTap
    }

    /// 30 fps for lively poses, 15 fps for calm ones.
    private var frameInterval: Double {
        switch pose {
        case .working, .almostDone, .breakDue: 1.0 / 30
        case .idle, .paused, .onBreak: 1.0 / 15
        }
    }

    public var body: some View {
        Group {
            if reduceMotion {
                // Static frame: no timeline, no blink.
                scene(t: 0, blinkT: 0)
            } else {
                TimelineView(.animation(minimumInterval: frameInterval, paused: !panelState.isActive)) { context in
                    let now = context.date.timeIntervalSince(start)
                    scene(t: now, blinkT: now)
                }
            }
        }
        .contentShape(HitShape(rects: hitRects))
        .onPreferenceChange(HitRectsKey.self) { rects in hitRects = rects }
        .onHover { hover = $0 }
        .onChange(of: panelState.dragEpoch) { hover = false }
        .onChange(of: pose) { old, new in
            if old == .onBreak, new == .working, !reduceMotion { celebrateCount += 1 }
        }
        .onTapGesture {
            tapCount += 1
            onTap?()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: String {
        if let bubbleText, !bubbleText.isEmpty { return "\(pose.accessibilityDescription). \(bubbleText)" }
        return pose.accessibilityDescription
    }

    @ViewBuilder
    private func scene(t: Double, blinkT: Double) -> some View {
        let hoverText = hover ? self.hoverText : nil
        if reduceMotion {
            MascotScene(pose: pose, progress: progress, bubbleText: bubbleText, t: t, blinkT: blinkT,
                        hover: hover, squish: 0, size: size, hoverText: hoverText, celebrate: 0)
        } else {
            // The placeholder content is ignored; the scene is rebuilt with the animated values.
            let (pose, progress, bubbleText, hover, size) = (self.pose, self.progress, self.bubbleText, self.hover, self.size)
            let tc = tapCount
            Color.clear
                .keyframeAnimator(initialValue: 0.0, trigger: celebrateCount) { _, c in
                    SquishLayer(trigger: tc, pose: pose, progress: progress, bubbleText: bubbleText, t: t,
                                blinkT: blinkT, hover: hover, size: size, hoverText: hoverText, celebrate: c)
                } keyframes: { _ in
                    LinearKeyframe(1.0, duration: 1.1)
                    LinearKeyframe(0.0, duration: 0.01)
                }
        }
    }
}

/// Inner layer applying the click-squish keyframes (nested so hop and squish animate independently).
private struct SquishLayer: View {
    var trigger: Int
    var pose: MascotPose
    var progress: Double
    var bubbleText: String?
    var t: Double
    var blinkT: Double
    var hover: Bool
    var size: MascotSize
    var hoverText: String?
    var celebrate: Double

    nonisolated init(trigger: Int, pose: MascotPose, progress: Double, bubbleText: String?, t: Double,
                     blinkT: Double, hover: Bool, size: MascotSize, hoverText: String?, celebrate: Double) {
        self.trigger = trigger; self.pose = pose; self.progress = progress; self.bubbleText = bubbleText
        self.t = t; self.blinkT = blinkT; self.hover = hover; self.size = size
        self.hoverText = hoverText; self.celebrate = celebrate
    }

    var body: some View {
        Color.clear
            .keyframeAnimator(initialValue: 0.0, trigger: trigger) { _, s in
                MascotScene(pose: pose, progress: progress, bubbleText: bubbleText, t: t, blinkT: blinkT,
                            hover: hover, squish: s, size: size, hoverText: hoverText, celebrate: celebrate)
            } keyframes: { _ in
                SpringKeyframe(1.0, duration: 0.12, spring: .init(duration: 0.12, bounce: 0.2))
                SpringKeyframe(0.0, duration: 0.5, spring: .init(duration: 0.5, bounce: 0.6))
            }
    }
}
