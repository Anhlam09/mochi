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
    let mascotSize: MascotSize

    public nonisolated init(pose: MascotPose, progress: Double, bubbleText: String?, t: Double,
                hover: Bool = false, squish: Double = 0, size: MascotSize = .medium) {
        self.init(pose: pose, progress: progress, bubbleText: bubbleText, t: t, blinkT: t,
                  hover: hover, squish: squish, size: size)
    }

    nonisolated init(pose: MascotPose, progress: Double, bubbleText: String?, t: Double, blinkT: Double,
         hover: Bool, squish: Double, size: MascotSize) {
        self.pose = pose; self.progress = progress; self.bubbleText = bubbleText
        self.t = t; self.blinkT = blinkT; self.hover = hover; self.squish = squish
        self.mascotSize = size
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
                MascotFigure(pose: pose, t: t, blinkT: blinkT, hover: hover, squish: squish)
            }
            .padding(.bottom, 14)
            .frame(width: Self.size.width, height: baseH)
            .scaleEffect(s, anchor: .bottom)
            .frame(width: win.width, height: baseH * s, alignment: .bottom)

            if let bubbleText, !bubbleText.isEmpty {
                SpeechBubble(text: bubbleText, maxWidth: min(216, (win.width - 4) / bs))
                    .id(bubbleText)
                    .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                    .scaleEffect(bs, anchor: .bottom)
                    .padding(.bottom, (baseH - 12) * s)
            }
        }
        .frame(width: win.width, height: win.height, alignment: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: bubbleText)
    }
}

/// Live, animated Mochi: hover lean, click squish, Reduce Motion aware.
public struct MascotView: View {
    public var pose: MascotPose
    public var progress: Double
    public var bubbleText: String?
    public var size: MascotSize
    public var onTap: (() -> Void)?

    @State private var hover = false
    @State private var tapCount = 0
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(pose: MascotPose, progress: Double, bubbleText: String?,
                size: MascotSize = .medium, onTap: (() -> Void)? = nil) {
        self.size = size
        self.pose = pose
        self.progress = progress
        self.bubbleText = bubbleText
        self.onTap = onTap
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 10 : 1.0 / 30)) { context in
            let now = context.date.timeIntervalSince(start)
            // Reduce Motion: motion time is frozen, only the slow blink keeps running.
            scene(t: reduceMotion ? 0 : now, blinkT: now)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            tapCount += 1
            onTap?()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pose.accessibilityDescription)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func scene(t: Double, blinkT: Double) -> some View {
        if reduceMotion {
            MascotScene(pose: pose, progress: progress, bubbleText: bubbleText, t: t, blinkT: blinkT, hover: hover, squish: 0, size: size)
        } else {
            // The placeholder content is ignored; the scene is rebuilt with the animated squish value.
            let (pose, progress, bubbleText, hover, size) = (self.pose, self.progress, self.bubbleText, self.hover, self.size)
            Color.clear
                .keyframeAnimator(initialValue: 0.0, trigger: tapCount) { _, s in
                    MascotScene(pose: pose, progress: progress, bubbleText: bubbleText, t: t, blinkT: blinkT, hover: hover, squish: s, size: size)
                } keyframes: { _ in
                    SpringKeyframe(1.0, duration: 0.12, spring: .init(duration: 0.12, bounce: 0.2))
                    SpringKeyframe(0.0, duration: 0.5, spring: .init(duration: 0.5, bounce: 0.6))
                }
        }
    }
}
