import SwiftUI
import AppKit

/// Borderless, non-activating panel that floats above everything and never steals focus.
@MainActor
final class MochiPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that accepts the very first click (the panel is never key) and does NOT
/// turn mouse-downs into window drags itself: SwiftUI decides tap vs. drag (see `DragHandle`).
@MainActor
final class MochiHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Wraps the root view: a small drag on the content moves the window; a click without
/// movement still reaches the inner `onTapGesture` (the drag gesture is *simultaneous* and
/// has a minimum distance, so it never fires for taps).
private struct DragHandle<Content: View>: View {
    let content: Content
    let onDragStart: @MainActor () -> Void
    @State private var dragging = false

    var body: some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { _ in
                        guard !dragging else { return }
                        dragging = true
                        onDragStart() // runs the system window-drag loop until mouse-up
                        dragging = false
                    }
            )
    }
}

@MainActor
public final class FloatingPanelController {
    public static let panelSize = NSSize(width: 220, height: 230)
    private static let margin: CGFloat = 24

    private let panel: MochiPanel
    private var screenTask: Task<Void, Never>?

    public var isVisible: Bool { panel.isVisible }

    public init<V: View>(rootView: V) {
        let panel = MochiPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize))
        self.panel = panel

        let wrapped = DragHandle(content: rootView) { [weak panel] in
            guard let panel, let event = NSApp.currentEvent else { return }
            panel.performDrag(with: event)
        }
        let hosting = MochiHostingView(rootView: wrapped)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Restore the saved frame if there is one, otherwise default to bottom-right.
        let restored = panel.setFrameUsingName("MochiPanel")
        panel.setFrameAutosaveName("MochiPanel")
        if restored {
            panel.setContentSize(Self.panelSize)
        } else {
            placeDefault()
        }
        clampToScreen()

        screenTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification).map({ _ in () }) {
                self?.clampToScreen()
            }
        }
    }

    public func show() {
        clampToScreen()
        panel.orderFrontRegardless()
    }

    public func hide() {
        panel.orderOut(nil)
    }

    private func placeDefault() {
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: area.maxX - Self.panelSize.width - Self.margin,
            y: area.minY + Self.margin)
        panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: false)
    }

    /// Keeps the panel fully inside the visible area of the screen it overlaps most.
    private func clampToScreen() {
        let frame = panel.frame
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let best = screens.max { a, b in
            a.frame.intersection(frame).area < b.frame.intersection(frame).area
        } ?? screens[0]
        let target = best.frame.intersection(frame).area > 0 ? best : (NSScreen.main ?? screens[0])
        let area = target.visibleFrame
        var o = frame.origin
        o.x = min(max(o.x, area.minX), max(area.minX, area.maxX - frame.width))
        o.y = min(max(o.y, area.minY), max(area.minY, area.maxY - frame.height))
        if o != frame.origin { panel.setFrameOrigin(o) }
    }
}

private extension NSRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}
