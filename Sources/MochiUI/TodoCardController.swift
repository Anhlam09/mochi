import SwiftUI
import AppKit
import MochiCore

/// Borderless, non-activating panel for the to-do card. Unlike the mascot panel it CAN become key,
/// so the text field gets keystrokes.
@MainActor
final class TodoCardPanel: NSPanel {
    var onCancel: (() -> Void)?
    private(set) var allowsKey = false

    init(contentRect: NSRect) {
        // `.nonactivatingPanel` must be in the style mask at init time (changing it later is unreliable).
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // the card draws its own soft shadow
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
    }

    func setAllowsKey(_ v: Bool) { allowsKey = v }
    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() } // Esc
}

@MainActor
private final class CardHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The SwiftUI root hosted in the card panel. It calls the caller's closures inside `body`, so any
/// `@Observable` state they read (the TodoStore) is tracked by SwiftUI and the card re-renders on change.
private struct TodoCardRoot: View {
    let items: () -> [TodoItem]
    let later: () -> [TodoItem]
    let notice: () -> String?
    let ask: () -> AskMochiState?
    let now: () -> Date
    let showMoveToTomorrow: () -> Bool
    let actions: TodoCardActions
    let popAnchor: UnitPoint
    let onSize: (CGSize) -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TodoCardView(items: items(), later: later(), now: now(), actions: actions,
                     showMoveToTomorrow: showMoveToTomorrow(), notice: notice(), ask: ask())
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { onSize($0) }
            .scaleEffect(shown || reduceMotion ? 1 : 0.86, anchor: popAnchor)
            .opacity(shown ? 1 : 0)
            .padding(TodoCardController.shadowPad)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.62)) {
                    shown = true
                }
            }
    }
}

/// Shows the to-do card in its own panel next to the mascot.
@MainActor
public final class TodoCardController {
    /// Transparent margin around the card so its shadow isn't clipped.
    static let shadowPad: CGFloat = 22
    private static let gap: CGFloat = 4
    private static let edge: CGFloat = 6

    private let anchor: FloatingPanelController
    private var panel: TodoCardPanel?
    private var cardSize = CGSize(width: TodoCardView.width, height: 160)
    private var frameToken: NSObjectProtocol?
    private var mouseMonitors: [Any] = []
    private var closeAction: (@MainActor () -> Void)?
    private var generation = 0

    public var isVisible: Bool { panel?.isVisible ?? false }

    public init(anchor: FloatingPanelController) {
        self.anchor = anchor
    }

    /// Shows (or refreshes) the card. The closures are re-read by SwiftUI on every render, so reading
    /// `@Observable` state in them keeps the card live.
    public func show(items: @escaping () -> [TodoItem],
                     later: @escaping () -> [TodoItem] = { [] },
                     now: @escaping () -> Date,
                     showMoveToTomorrow: @escaping () -> Bool,
                     notice: @escaping () -> String? = { nil },
                     ask: @escaping () -> AskMochiState? = { nil },
                     actions: TodoCardActions) {
        if isVisible { return }
        generation += 1
        let userClose = actions.close
        closeAction = userClose
        var wrapped = actions
        wrapped.close = { [weak self] in self?.dismiss() }

        let side = placement(for: cardSize)
        let panel = TodoCardPanel(contentRect: .zero)
        let root = TodoCardRoot(items: items, later: later, notice: notice, ask: ask, now: now, showMoveToTomorrow: showMoveToTomorrow,
                                actions: wrapped, popAnchor: side.popAnchor) { [weak self] size in
            MainActor.assumeIsolated { self?.cardSizeChanged(size) }
        }
        let hosting = CardHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        panel.contentView = hosting
        panel.onCancel = { [weak self] in self?.dismiss() }
        panel.setAllowsKey(true)
        self.panel = panel
        apply(side.rect, to: panel)
        panel.alphaValue = 1

        // Key without activating the app: see the note on `focus(_:)`.
        panel.makeKeyAndOrderFront(nil)
        focus(panel)

        frameToken = anchor.observeFrameChanges { [weak self] in self?.reposition() }
        installMouseMonitors()
    }

    public func toggle(items: @escaping () -> [TodoItem],
                       later: @escaping () -> [TodoItem] = { [] },
                       now: @escaping () -> Date,
                       showMoveToTomorrow: @escaping () -> Bool,
                       notice: @escaping () -> String? = { nil },
                       ask: @escaping () -> AskMochiState? = { nil },
                       actions: TodoCardActions) {
        if isVisible {
            hide()
        } else {
            show(items: items, later: later, now: now, showMoveToTomorrow: showMoveToTomorrow,
                 notice: notice, ask: ask, actions: actions)
        }
    }

    /// Hides the card (does not call the caller's `close` action).
    public func hide() {
        guard let panel else { return }
        generation += 1
        removeMonitors()
        if let frameToken { anchor.removeFrameObserver(frameToken); self.frameToken = nil }
        panel.setAllowsKey(false)
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                panel.contentView = nil
            }
        })
    }

    /// Esc, the X button or a click outside: hide, then tell the caller.
    private func dismiss() {
        let close = closeAction
        hide()
        close?()
    }

    // MARK: key focus

    /// Typing approach: the panel is `.nonactivatingPanel` and overrides `canBecomeKey`, so
    /// `makeKeyAndOrderFront` makes it the key window WITHOUT activating Mochi or pulling the user's
    /// frontmost app out of focus; key events are routed to the key window, so the text field receives
    /// them. SwiftUI's `@FocusState` then puts the caret in the field. If AppKit still reports the panel as
    /// not key on the next runloop turn (rare), we retry `makeKey()` once. The app is never activated.
    private func focus(_ panel: TodoCardPanel) {
        DispatchQueue.main.async { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self, let panel, self.panel === panel, panel.isVisible else { return }
                if !panel.isKeyWindow { panel.makeKey() }
            }
        }
    }

    // MARK: outside clicks

    private func installMouseMonitors() {
        removeMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps.
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) { mouseMonitors.append(g) }
        // Clicks in our own windows other than the card and the mascot (the mascot's to-do badge toggles
        // the card itself, so it must not be closed-then-reopened here).
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            nonisolated(unsafe) let ev = event
            MainActor.assumeIsolated {
                guard let self, let panel = self.panel else { return }
                if ev.window !== panel && ev.window?.frame != self.anchor.frame { self.dismiss() }
            }
            return event
        }) { mouseMonitors.append(l) }
    }

    private func removeMonitors() {
        mouseMonitors.forEach { NSEvent.removeMonitor($0) }
        mouseMonitors = []
    }

    // MARK: positioning

    private struct Placement {
        var rect: NSRect // the visible card (without shadow margin)
        var popAnchor: UnitPoint
    }

    private func cardSizeChanged(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != cardSize else { return }
        cardSize = size
        reposition()
    }

    private func reposition() {
        guard let panel else { return }
        apply(placement(for: cardSize).rect, to: panel)
    }

    private func apply(_ card: NSRect, to panel: NSPanel) {
        let outer = card.insetBy(dx: -Self.shadowPad, dy: -Self.shadowPad)
        if panel.frame != outer { panel.setFrame(outer, display: true) }
    }

    /// Right of the mascot if there's room (top-aligned with the figure), else left, else above
    /// and clamped to the visible area of its screen.
    private func placement(for size: CGSize) -> Placement {
        let fig = anchor.figureFrame
        let screens = NSScreen.screens
        let screen = screens.max { a, b in
            a.frame.intersection(anchor.frame).width * a.frame.intersection(anchor.frame).height <
            b.frame.intersection(anchor.frame).width * b.frame.intersection(anchor.frame).height
        } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let e = Self.edge

        var x: CGFloat, y: CGFloat
        var pop: UnitPoint
        let leftX = fig.minX - Self.gap - size.width
        let rightX = fig.maxX + Self.gap
        // Preferred: right of Mochi, top edge level with the top of the figure.
        if rightX + size.width <= vis.maxX - e {
            x = rightX; y = fig.maxY - size.height; pop = .topLeading
        } else if leftX >= vis.minX + e {
            x = leftX; y = fig.maxY - size.height; pop = .topTrailing
        } else {
            x = fig.midX - size.width / 2; y = fig.maxY + Self.gap; pop = .bottom
        }
        x = min(max(x, vis.minX + e), max(vis.minX + e, vis.maxX - size.width - e))
        y = min(max(y, vis.minY + e), max(vis.minY + e, vis.maxY - size.height - e))
        return Placement(rect: NSRect(x: x, y: y, width: size.width, height: size.height), popAnchor: pop)
    }
}
