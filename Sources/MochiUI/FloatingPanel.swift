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

/// Shared state between the controller, the hosting view and the SwiftUI wrapper.
@MainActor
final class PanelMetrics: ObservableObject {
    /// Fixed drag threshold (points) at every size.
    static let dragThreshold: CGFloat = 6
    /// Visible and not occluded: drives whether the mascot animates.
    @Published var isActive = true
    /// Incremented whenever a window drag ends (the mascot resets its hover state).
    @Published var dragEpoch = 0
    /// Regions (top-left coords in window space) that accept clicks; empty = everything.
    @Published var hitRects: [CGRect] = []
    /// The most recent left mouse-down delivered to the hosting view.
    var lastMouseDown: NSEvent?

    func accepts(windowPointTopLeft p: CGPoint) -> Bool {
        hitRects.isEmpty || hitRects.contains { $0.insetBy(dx: -2, dy: -2).contains(p) }
    }
}

/// Hosting view that accepts the very first click (the panel is never key) and does NOT turn
/// mouse-downs into window drags itself; it records the mouse-down so the drag can start from it.
@MainActor
final class MochiHostingView<Content: View>: NSHostingView<Content> {
    var metrics: PanelMetrics?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        metrics?.lastMouseDown = event
        super.mouseDown(with: event) // SwiftUI still sees the press (tap / drag gestures)
    }
}

/// Wraps the root view. A click without movement reaches the inner `onTapGesture`; once the
/// pointer moves more than 6pt, the simultaneous DragGesture starts the system window drag from the
/// recorded mouse-down. Hit-testing is limited to the figure (and bubble) rects.
private struct DragHandle<Content: View>: View {
    let content: Content
    @ObservedObject var metrics: PanelMetrics
    let onDragStart: @MainActor () -> Void
    @State private var dragging = false

    var body: some View {
        content
            .contentShape(HitShape(rects: metrics.hitRects))
            .onPreferenceChange(HitRectsKey.self) { rects in
                Task { @MainActor in metrics.hitRects = rects }
            }
            .environment(\.mochiPanelState, PanelState(isActive: metrics.isActive, dragEpoch: metrics.dragEpoch))
            .simultaneousGesture(
                DragGesture(minimumDistance: PanelMetrics.dragThreshold, coordinateSpace: .global)
                    .onChanged { _ in
                        guard !dragging else { return }
                        dragging = true
                        onDragStart() // runs the system window-drag loop until mouse-up
                        dragging = false
                        metrics.dragEpoch += 1
                    }
            )
    }
}

@MainActor
public final class FloatingPanelController {
    public static let panelSize = NSSize(width: 220, height: 230)

    /// Panel size for a mascot size (medium size scaled and rounded).
    public static func panelSize(for size: MascotSize) -> NSSize {
        let s = MascotScene.size(for: size)
        return NSSize(width: s.width, height: s.height)
    }
    private static let margin: CGFloat = 24

    private let panel: MochiPanel
    private let metrics = PanelMetrics()
    private var size: MascotSize
    private var monitors: [Any] = []
    private var screenTask: Task<Void, Never>?

    public var isVisible: Bool { panel.isVisible }

    public init<V: View>(rootView: V, size: MascotSize = .medium) {
        let panel = MochiPanel(contentRect: NSRect(origin: .zero, size: Self.panelSize(for: size)))
        self.panel = panel
        self.size = size

        let metrics = self.metrics
        let wrapped = DragHandle(content: rootView, metrics: metrics) { [weak panel] in
            // Start from the recorded mouse-down; fall back to the current event.
            guard let panel, let event = metrics.lastMouseDown ?? NSApp.currentEvent else { return }
            panel.performDrag(with: event)
        }
        let hosting = MochiHostingView(rootView: wrapped)
        hosting.metrics = metrics
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(origin: .zero, size: Self.panelSize(for: size))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        // Restore the saved frame if there is one, otherwise default to bottom-right.
        let restored = panel.setFrameUsingName("MochiPanel")
        panel.setFrameAutosaveName("MochiPanel")
        if restored {
            resize(to: Self.panelSize(for: size))
        } else {
            placeDefault()
        }
        clampToScreen()

        panel.acceptsMouseMovedEvents = true
        observeActivity()
        installMouseMonitors()

        screenTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification).map({ _ in () }) {
                self?.clampToScreen()
            }
        }
    }

    /// Resizes the panel, keeping its bottom-right corner anchored, and clamps it on screen.
    public func setSize(_ newSize: MascotSize) {
        size = newSize
        resize(to: Self.panelSize(for: newSize))
        clampToScreen()
    }

    private func resize(to target: NSSize) {
        let f = panel.frame
        guard f.size != target else { return }
        let origin = NSPoint(x: f.maxX - target.width, y: f.minY)
        panel.setFrame(NSRect(origin: origin, size: target), display: true)
    }

    public func show() {
        clampToScreen()
        panel.orderFrontRegardless()
        updateActivity()
    }

    public func hide() {
        panel.orderOut(nil)
        updateActivity()
    }

    // MARK: activity (stop animating when nobody can see Mochi)

    private func updateActivity() {
        let active = panel.isVisible && panel.occlusionState.contains(.visible)
        if metrics.isActive != active { metrics.isActive = active }
    }

    private func observeActivity() {
        let nc = NotificationCenter.default
        let panel = self.panel
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didChangeScreenNotification] {
            let token = nc.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateActivity() }
            }
            monitors.append(token)
        }
    }

    // MARK: click-through for transparent areas

    /// The panel ignores the mouse while the pointer is over blank (non-figure) areas of
    /// its frame, so clicks fall through to the windows below.
    private func installMouseMonitors() {
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouseTransparency() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.updateMouseTransparency() }
            return event
        }
        monitors.append(contentsOf: [global, local].compactMap { $0 })
    }

    private func updateMouseTransparency() {
        guard panel.isVisible, NSEvent.pressedMouseButtons == 0 else { return }
        let loc = NSEvent.mouseLocation
        let f = panel.frame
        var ignore = false
        if f.contains(loc) {
            let p = CGPoint(x: loc.x - f.minX, y: f.maxY - loc.y)
            ignore = !metrics.accepts(windowPointTopLeft: p)
        }
        if panel.ignoresMouseEvents != ignore {
            panel.ignoresMouseEvents = ignore
            // No exit event arrives once the window ignores the mouse: reset hover explicitly.
            if ignore { metrics.dragEpoch += 1 }
        }
    }

    private func placeDefault() {
        let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: area.maxX - Self.panelSize(for: size).width - Self.margin,
            y: area.minY + Self.margin)
        panel.setFrame(NSRect(origin: origin, size: Self.panelSize(for: size)), display: false)
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
