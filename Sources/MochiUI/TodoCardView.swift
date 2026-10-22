import SwiftUI
import MochiCore

/// What the to-do card can ask the app to do. All closures run on the main actor.
public struct TodoCardActions {
    public var add: @MainActor (String) -> Void
    public var toggle: @MainActor (UUID) -> Void
    public var delete: @MainActor (UUID) -> Void
    public var moveUnfinishedToTomorrow: @MainActor () -> Void
    public var close: @MainActor () -> Void
    /// Sends a question to Mochi's on-device brain (the "Ask Mochi" tab).
    public var ask: (@MainActor (String) -> Void)?

    public init(add: @escaping @MainActor (String) -> Void,
                toggle: @escaping @MainActor (UUID) -> Void,
                delete: @escaping @MainActor (UUID) -> Void,
                moveUnfinishedToTomorrow: @escaping @MainActor () -> Void,
                close: @escaping @MainActor () -> Void,
                ask: (@MainActor (String) -> Void)? = nil) {
        self.ask = ask
        self.add = add
        self.toggle = toggle
        self.delete = delete
        self.moveUnfinishedToTomorrow = moveUnfinishedToTomorrow
        self.close = close
    }
}

/// Mochi's to-do card: header, quick-add field, rows and an optional "move to tomorrow" pill.
public struct TodoCardView: View {
    public static let width: CGFloat = 332
    /// The list scrolls once it grows past this height (card max is about 430pt).
    static let maxListHeight: CGFloat = 224

    public var items: [TodoItem]
    /// To-dos for later days (shown in a collapsed "Later" section).
    public var later: [TodoItem]
    /// A warm warning strip at the top when non-nil.
    public var notice: String?
    /// Non-nil adds the "Ask Mochi" tab.
    public var ask: AskMochiState?
    public var now: Date
    public var actions: TodoCardActions
    public var showMoveToTomorrow: Bool
    @State private var text = ""
    @State private var listHeight: CGFloat = 0
    @FocusState private var fieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var laterOpen = false
    @State private var tab: TodoCardTab = .todos
    @State private var askText = ""
    @FocusState private var askFocused: Bool
    private let hasInitialTab: Bool

    public init(items: [TodoItem], later: [TodoItem] = [], now: Date, actions: TodoCardActions,
                showMoveToTomorrow: Bool, notice: String? = nil, ask: AskMochiState? = nil, laterExpanded: Bool = false,
                initialTab: TodoCardTab? = nil) {
        self.ask = ask
        self._tab = State(initialValue: initialTab ?? .todos)
        self.hasInitialTab = initialTab != nil
        self._laterOpen = State(initialValue: laterExpanded)
        self.items = items
        self.later = later
        self.now = now
        self.actions = actions
        self.showMoveToTomorrow = showMoveToTomorrow
        self.notice = notice
    }

    private var doneCount: Int { items.filter(\.done).count }
    private var hasUnfinished: Bool { items.contains { !$0.done } }

    public var body: some View {
        VStack(spacing: 12) {
            if let notice, !notice.isEmpty { NoticeStrip(text: notice) }
            header
            if ask != nil { TabSwitch(tab: $tab) }
            if tab == .ask, let ask {
                AskTab(state: ask, text: $askText, focused: $askFocused, send: sendAsk)
            } else {
                field
                if items.isEmpty { EmptyTodoState() }
                if !items.isEmpty || (!later.isEmpty && laterOpen) { list }
                if !later.isEmpty && !laterOpen { laterSection }
                if showMoveToTomorrow && hasUnfinished {
                    moveButton
                }
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .background(CardBackground())
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: items)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: later)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: laterOpen)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: showMoveToTomorrow)
        .onKeyPress(.escape) {
            actions.close()
            return .handled
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: ask)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: tab)
        .onAppear { if ask != nil, !hasInitialTab { tab = TabMemory.last } }
        .onChange(of: tab) { _, new in
            TabMemory.last = new
            focusCurrentField()
        }
        .task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            focusCurrentField()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Today's to-do list")
    }

    private func focusCurrentField() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            if tab == .ask && ask?.unavailableReason == nil { askFocused = true } else { fieldFocused = true }
        }
    }

    private func sendAsk(_ question: String) {
        let t = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { actions.ask?(t); askText = "" }
        askFocused = true
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Today 🌱")
                .font(.mochi(20, .bold))
                .foregroundStyle(Palette.text)
            Spacer(minLength: 4)
            if !items.isEmpty && tab == .todos { progress }
            Button { actions.close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.text.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Palette.softFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close to-do list")
            .help("Close")
        }
    }

    private var progress: some View {
        let total = items.count
        let frac = total == 0 ? 0 : Double(doneCount) / Double(total)
        return HStack(spacing: 6) {
            Capsule().fill(Palette.softFill)
                .frame(width: 34, height: 5)
                .overlay(alignment: .leading) {
                    Capsule().fill(Palette.sprout)
                        .frame(width: max(5, 34 * frac), height: 5)
                        .opacity(doneCount == 0 ? 0 : 1)
                }
            Text(doneCount == total ? "all done 🎉" : "\(doneCount) of \(total) done")
                .font(.mochi(13, .medium))
                .foregroundStyle(Palette.text.opacity(0.6))
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(doneCount) of \(total) done")
    }

    // MARK: field

    private var field: some View {
        HStack(spacing: 7) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.blush)
            TextField("", text: $text,
                      prompt: Text("Add a to-do… try 'go for a walkie 3pm'")
                        .foregroundStyle(Palette.text.opacity(0.4)))
                .textFieldStyle(.plain)
                .font(.mochi(15, .medium))
                .foregroundStyle(Palette.text)
                .focused($fieldFocused)
                .onSubmit(submit)
                .accessibilityLabel("New to-do")
                .accessibilityHint("Type a to-do, optionally with a time, then press Return")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 17, style: .circular).fill(Palette.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .circular).strokeBorder(fieldFocused ? Palette.blush.opacity(0.9) : Palette.ink.opacity(0.1),
                                   lineWidth: fieldFocused ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: fieldFocused)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            actions.add(trimmed)
            text = ""
        }
        fieldFocused = true // keep focus for fast entry
    }

    // MARK: list

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                ForEach(items) { item in
                    TodoRow(item: item, now: now, actions: actions)
                        .transition(reduceMotion ? .opacity
                                    : .asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity),
                                                  removal: .opacity))
                }
                if !later.isEmpty && laterOpen { laterSection }
            }
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { listHeight = $0 }
        }
        .frame(height: min(max(listHeight, 1), laterOpen ? Self.maxListHeight + 67 : Self.maxListHeight))
        .scrollBounceBehavior(.basedOnSize)
    }

    private var laterSection: some View {
        VStack(spacing: 2) {
            Button { laterOpen.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(laterOpen ? 90 : 0))
                    Text("Later (\(later.count))").font(.mochi(14))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.text.opacity(0.6))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Later, \(later.count) to-dos")
            .accessibilityValue(laterOpen ? "expanded" : "collapsed")
            if laterOpen {
                ForEach(later) { item in
                    TodoRow(item: item, now: now, actions: actions, showDay: true)
                        .transition(.opacity)
                }
            }
        }
        .padding(.top, items.isEmpty ? 0 : 4)
    }

    private var moveButton: some View {
        Button { actions.moveUnfinishedToTomorrow() } label: {
            Text("Move unfinished to tomorrow 🌙")
                .font(.mochi(14))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 15, style: .circular).fill(Palette.focusRing.opacity(0.22)))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .circular).strokeBorder(Palette.focusRing.opacity(0.45), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Move unfinished to-dos to tomorrow")
        .transition(.opacity)
    }
}

// MARK: - Card chrome

private struct CardBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape.fill(Palette.cardFill)
            .overlay(
                shape.fill(LinearGradient(colors: [Palette.blush.opacity(0.16), .clear],
                                          startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
            )
            .overlay(shape.stroke(Palette.ink.opacity(0.1), lineWidth: 1))
            .shadow(color: Palette.ink.opacity(0.18), radius: 14, y: 5)
    }
}

extension Palette {
    static let cardFill = dynamic(light: 0xFFFDFD, dark: 0x332D3D)
    static let softFill = dynamic(light: 0x4A3F55, dark: 0xFFFFFF, alpha: 0.10)
    static let fieldFill = dynamic(light: 0xFFF3F5, dark: 0x403949)
}

// MARK: - Row

private struct TodoRow: View {
    let item: TodoItem
    let now: Date
    let actions: TodoCardActions
    var showDay = false
    @State private var hover = false
    @State private var dragX: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var carried: Bool { item.isCarriedOver(today: now) }
    private static let swipeToDelete: CGFloat = -64

    var body: some View {
        ZStack(alignment: .trailing) {
            // Revealed while swiping left.
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.blush)
                .padding(.trailing, 12)
                .opacity(min(1, Double(-dragX) / 40))

            content
                .offset(x: dragX)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            dragX = min(0, v.translation.width)
                        }
                        .onEnded { v in
                            if v.translation.width < Self.swipeToDelete {
                                actions.delete(item.id)
                            } else {
                                withAnimation(.snappy(duration: 0.2)) { dragX = 0 }
                            }
                        }
                )
        }
        .onHover { hover = $0 }
        .contextMenu {
            Button(item.done ? "Mark as not done" : "Mark as done") { actions.toggle(item.id) }
            Button("Delete", role: .destructive) { actions.delete(item.id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: item.done ? "Mark as not done" : "Mark as done") { actions.toggle(item.id) }
        .accessibilityAction(named: "Delete") { actions.delete(item.id) }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 9) {
            TickBox(done: item.done) { actions.toggle(item.id) }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.mochi(15, .medium))
                    .foregroundStyle(Palette.text)
                    .strikethrough(item.done, color: Palette.text.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if item.time != nil || carried || showDay {
                    HStack(spacing: 5) {
                        if showDay {
                            Chip(text: dayText, tint: Palette.sprout, symbol: nil)
                        }
                        if let time = item.time {
                            Chip(text: time.formatted(date: .omitted, time: .shortened),
                                 tint: Palette.peach, symbol: "clock")
                        }
                        if carried {
                            Chip(text: "from yesterday", tint: Palette.focusRing, symbol: nil)
                        }
                    }
                }
            }
            .opacity(item.done ? 0.45 : 1)
            Spacer(minLength: 0)
            if hover {
                Button { actions.delete(item.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.text.opacity(0.5))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Palette.softFill))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityHidden(true)
                .help("Delete")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7.5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hover ? Palette.blush.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    private var dayText: String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: item.day)).day ?? 0
        return days <= 6
            ? item.day.formatted(.dateTime.weekday(.abbreviated))
            : item.day.formatted(.dateTime.month(.abbreviated).day())
    }

    private var accessibilityText: String {
        var parts = [item.title]
        if showDay { parts.append("on " + item.day.formatted(.dateTime.weekday(.wide).month().day())) }
        if let time = item.time { parts.append("at " + time.formatted(date: .omitted, time: .shortened)) }
        if carried { parts.append("from yesterday") }
        parts.append(item.done ? "done" : "not done")
        return parts.joined(separator: ", ")
    }
}

private struct Chip: View {
    let text: String
    let tint: Color
    let symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            }
            Text(text).font(.mochi(12, .semibold))
        }
        .foregroundStyle(Palette.text.opacity(0.75))
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.32)))
        .fixedSize()
    }
}

/// Round checkbox: a springy tick with a tiny sparkle burst (plain fade under Reduce Motion).
private struct TickBox: View {
    let done: Bool
    let action: () -> Void
    @State private var burst: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(done ? Color.clear : Palette.blush, lineWidth: 1.8)
                Circle()
                    .fill(Palette.blush)
                    .scaleEffect(done ? 1 : 0.2)
                    .opacity(done ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .scaleEffect(done ? 1 : 0.3)
                    .opacity(done ? 1 : 0)
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) * .pi / 2 + .pi / 4
                    SparkleShape()
                        .fill(i.isMultiple(of: 2) ? Palette.peach : Palette.sprout)
                        .frame(width: 6, height: 6)
                        .offset(x: cos(angle) * (7 + 8 * burst), y: sin(angle) * (7 + 8 * burst))
                        .scaleEffect(1 - 0.4 * burst)
                        .opacity(burst > 0 ? Double(1 - burst) : 0)
                }
            }
            .frame(width: 24, height: 24)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.5), value: done)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
        .onChange(of: done) { _, nowDone in
            guard nowDone, !reduceMotion else { return }
            burst = 0.001
            withAnimation(.easeOut(duration: 0.5)) { burst = 1 }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 550_000_000)
                burst = 0
            }
        }
    }
}

private struct NoticeStrip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.mochi(13, .medium))
            .foregroundStyle(Palette.text)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.peach.opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.peach.opacity(0.7), lineWidth: 1))
            .accessibilityLabel("Warning: \(text)")
    }
}

// MARK: - Ask Mochi

public enum TodoCardTab: Sendable { case todos, ask }

/// Remembers the last tab while the app runs.
@MainActor
private enum TabMemory { static var last: TodoCardTab = .todos }

private struct TabSwitch: View {
    @Binding var tab: TodoCardTab
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            seg("📝 To-dos", .todos)
            seg("✨ Ask Mochi", .ask)
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 16, style: .circular).fill(Palette.softFill))
        .accessibilityElement(children: .contain)
    }

    private func seg(_ title: String, _ value: TodoCardTab) -> some View {
        let on = tab == value
        return Button { tab = value } label: {
            Text(title)
                .font(.mochi(13, on ? .bold : .medium))
                .foregroundStyle(Palette.text.opacity(on ? 1 : 0.6))
                .frame(maxWidth: .infinity).frame(height: 26)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: 13, style: .circular).fill(Palette.blush.opacity(0.35))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .circular).strokeBorder(Palette.blush.opacity(0.5), lineWidth: 1))
                            .matchedGeometryEffect(id: "sel", in: ns)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 13, style: .circular))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == .todos ? "To-dos" : "Ask Mochi")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

private struct AskTab: View {
    let state: AskMochiState
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let send: (String) -> Void
    @State private var replyHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let suggestions = ["Plan my afternoon 🌤️", "What's left today?", "Cheer me up 💕", "Start a focus 🌱"]
    private var fresh: Bool { state.reply == nil && !state.isThinking && state.actionsTaken.isEmpty }

    var body: some View {
        VStack(spacing: 10) {
            if let reason = state.unavailableReason {
                EmptyTodoState(text: reason)
            } else {
                field
                if fresh { chips }
                if state.isThinking { thinking }
                if let reply = state.reply, !reply.isEmpty { replyBubble(reply) }
                if !state.actionsTaken.isEmpty { pills }
            }
            Text("🔒 Runs on your Mac, never sent anywhere")
                .font(.mochi(12, .medium))
                .foregroundStyle(Palette.text.opacity(0.55))
                .accessibilityLabel("Runs on your Mac, never sent anywhere")
        }
    }

    private var field: some View {
        HStack(spacing: 7) {
            Text("✨").font(.system(size: 11))
            TextField("", text: $text,
                      prompt: Text("Ask me anything… try 'what's next?'")
                        .foregroundStyle(Palette.text.opacity(0.4)))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.text)
                .focused(focused)
                .onSubmit { send(text) }
                .accessibilityLabel("Ask Mochi")
                .accessibilityHint("Type a question, then press Return")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 17, style: .circular).fill(Palette.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .circular)
                .strokeBorder(focused.wrappedValue ? Palette.blush.opacity(0.9) : Palette.ink.opacity(0.1),
                              lineWidth: focused.wrappedValue ? 1.5 : 1)
        )
    }

    private var chips: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(Self.suggestions, id: \.self) { s in
                Button { send(s) } label: {
                    Text(s)
                        .font(.mochi(13))
                        .foregroundStyle(Palette.text)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity).frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 13, style: .circular).fill(Palette.focusRing.opacity(0.2)))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .circular).strokeBorder(Palette.focusRing.opacity(0.4), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 13, style: .circular))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s)
            }
        }
    }

    private var thinking: some View {
        HStack(spacing: 8) {
            MiniFace()
            if reduceMotion {
                Text("thinking…").font(.mochi(13, .medium)).foregroundStyle(Palette.text.opacity(0.65))
            } else {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().fill(Palette.blush).frame(width: 7, height: 7)
                                .offset(y: -3.5 * max(0, sin(t * 6 - Double(i) * 0.9)))
                        }
                    }
                }
                .frame(height: 16)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.fieldFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mochi is thinking")
    }

    private func replyBubble(_ reply: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(reply)
                .font(.mochi(15, .medium))
                .foregroundStyle(Palette.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { replyHeight = $0 }
        }
        .frame(height: min(max(replyHeight, 1), 134))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.fieldFill)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.blush.opacity(0.35), lineWidth: 1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mochi says: \(reply)")
    }

    private var pills: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(state.actionsTaken.enumerated()), id: \.offset) { _, a in
                Text(a)
                    .font(.mochi(13, .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 13, style: .circular).fill(Palette.sprout.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .circular).strokeBorder(Palette.sprout.opacity(0.7), lineWidth: 1))
                    .accessibilityLabel("Done: \(a)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tiny awake Mochi face for the "thinking" row.
private struct MiniFace: View {
    var body: some View {
        ZStack {
            LeafShape().fill(Palette.sprout).frame(width: 8, height: 9).offset(y: -13)
            MochiBodyShape().fill(Palette.body).frame(width: 30, height: 24)
                .overlay(MochiBodyShape().stroke(Palette.blush.opacity(0.4), lineWidth: 1).frame(width: 30, height: 24))
            HStack(spacing: 9) {
                Ellipse().fill(Palette.ink).frame(width: 3.4, height: 4.6)
                Ellipse().fill(Palette.ink).frame(width: 3.4, height: 4.6)
            }.offset(y: -2)
            HStack(spacing: 14) {
                Ellipse().fill(Palette.blush.opacity(0.65)).frame(width: 5, height: 3.4)
                Ellipse().fill(Palette.blush.opacity(0.65)).frame(width: 5, height: 3.4)
            }.offset(y: 3)
        }
        .frame(width: 32, height: 34)
        .accessibilityHidden(true)
    }
}

// MARK: - Empty state

private struct EmptyTodoState: View {
    var text = "Nothing yet, add something sweet ✨"
    @State private var float = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                LeafShape().fill(Palette.sprout).frame(width: 12, height: 14)
                    .rotationEffect(.degrees(-18)).offset(x: -3, y: -22)
                LeafShape().fill(Palette.sprout.opacity(0.85)).frame(width: 10, height: 12)
                    .rotationEffect(.degrees(22)).offset(x: 5, y: -21)
                MochiBodyShape().fill(Palette.body).frame(width: 46, height: 36)
                    .overlay(MochiBodyShape().stroke(Palette.blush.opacity(0.35), lineWidth: 1).frame(width: 46, height: 36))
                HStack(spacing: 14) {
                    ArcLine(up: false).stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .frame(width: 8, height: 3)
                    ArcLine(up: false).stroke(Palette.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                        .frame(width: 8, height: 3)
                }.offset(y: -1)
                HStack(spacing: 22) {
                    Ellipse().fill(Palette.blush.opacity(0.6)).frame(width: 7, height: 4.5)
                    Ellipse().fill(Palette.blush.opacity(0.6)).frame(width: 7, height: 4.5)
                }.offset(y: 4)
                Text("z")
                    .font(.mochi(13, .bold)).foregroundStyle(Palette.focusRing)
                    .offset(x: 30, y: float ? -20 : -14)
                Text("z")
                    .font(.mochi(10, .bold)).foregroundStyle(Palette.focusRing.opacity(0.7))
                    .offset(x: 38, y: float ? -28 : -23)
            }
            .frame(height: 56)
            .padding(.top, 8)
            Text(text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .font(.mochi(14, .medium))
                .foregroundStyle(Palette.text.opacity(0.6))
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { float = true }
        }
    }
}

// MARK: - Mascot badge

/// The little 📝 bubble on Mochi's upper-left. With open to-dos it carries a blush-pink count dot.
struct TodoBadgeView: View {
    static let diameter: CGFloat = 26
    let count: Int
    let scale: Double
    let visible: Bool
    let tap: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle().fill(Palette.bubbleBackground)
                    .overlay(Circle().stroke(Palette.ink.opacity(0.12), lineWidth: 1))
                    .shadow(color: Palette.ink.opacity(0.16), radius: 3, y: 1.5)
                Text("📝").font(.system(size: 13))
            }
            .frame(width: Self.diameter, height: Self.diameter)
            if count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.mochi(9, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3.5)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Capsule().fill(Palette.blush))
                    .overlay(Capsule().stroke(.white.opacity(0.85), lineWidth: 1))
                    .offset(x: 5, y: -4)
                    .fixedSize()
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .scaleEffect(scale)
        .scaleEffect(visible ? 1 : 0.3)
        .opacity(visible ? 1 : 0)
        .contentShape(Circle())
        .onTapGesture { if visible { tap() } }
        .allowsHitTesting(visible)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count > 0 ? "To-do list, \(count) to do" : "To-do list")
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(!visible)
    }
}
