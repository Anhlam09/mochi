import SwiftUI
import AppKit
import MochiCore
import MochiUI

/// Renders the to-do card and the mascot badge through a real (offscreen) window so AppKit-backed
/// controls such as the text field draw correctly. Run: `swift run MochiPreview <dir> --todo`.
@MainActor
func renderTodoPreviews(into dir: URL) {
    let cal = Calendar.current
    let now = Date()
    let today = cal.startOfDay(for: now)
    let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
    let at3pm = cal.date(bySettingHour: 15, minute: 0, second: 0, of: today)

    let items = [
        TodoItem(title: "Reply to Mina's email", day: yesterday),
        TodoItem(title: "Call mom", day: today, time: at3pm),
        TodoItem(title: "Buy oat milk and strawberries", day: today),
        TodoItem(title: "Water the plants", day: today, done: true, doneAt: now),
    ]
    let actions = TodoCardActions(add: { _ in }, toggle: { _ in }, delete: { _ in },
                                  moveUnfinishedToTomorrow: {}, close: {})

    for dark in [false, true] {
        let mode = dark ? "dark" : "light"
        let full = TodoCardView(items: items, now: now, actions: actions, showMoveToTomorrow: true)
        snapshot(full, name: "todo_card_\(mode)", dark: dark, dir: dir)
        let empty = TodoCardView(items: [], now: now, actions: actions, showMoveToTomorrow: false)
        snapshot(empty, name: "todo_card_empty_\(mode)", dark: dark, dir: dir)
        let many = (1...9).map { TodoItem(title: "Little task number \($0)", day: today) }
        snapshot(TodoCardView(items: many, now: now, actions: actions, showMoveToTomorrow: true),
                 name: "todo_card_long_\(mode)", dark: dark, dir: dir)

        let later = [
            TodoItem(title: "Dentist appointment", day: cal.date(byAdding: .day, value: 3, to: today)!, time: at3pm),
            TodoItem(title: "Plan the birthday picnic", day: cal.date(byAdding: .day, value: 10, to: today)!),
        ]
        snapshot(TodoCardView(items: items, later: later, now: now, actions: actions, showMoveToTomorrow: true,
                              notice: "Couldn't save your list. Changes may not stick ⚠️", laterExpanded: true),
                 name: "todo_card_later_notice_\(mode)", dark: dark, dir: dir)
        snapshot(TodoCardView(items: items, later: later, now: now, actions: actions, showMoveToTomorrow: false),
                 name: "todo_card_later_collapsed_\(mode)", dark: dark, dir: dir)

        let asks: [(String, AskMochiState)] = [
            ("empty", AskMochiState()),
            ("thinking", AskMochiState(isThinking: true)),
            ("reply", AskMochiState(
                reply: "Here's a gentle plan: call mom at 3, then tackle the email while your energy is high. I'd save the groceries for a short walk after 5 🌤️",
                actionsTaken: ["Added 'call mom' for 3:00 PM ✓", "Moved 'Reply to Mina' to tomorrow ✓"])),
            ("unavailable", AskMochiState(unavailableReason: "Turn on Apple Intelligence to chat with Mochi ✨")),
        ]
        for (n, st) in asks {
            snapshot(TodoCardView(items: items, now: now, actions: actions, showMoveToTomorrow: true,
                                  ask: st, initialTab: .ask),
                     name: "todo_ask_\(n)_\(mode)", dark: dark, dir: dir)
        }

        let sizesSheet = HStack(alignment: .bottom, spacing: 0) {
            MascotView(pose: .breakDue, progress: 0.7, bubbleText: "Time to stretch! 🌱", size: .tiny, todoBadge: 3, onTodoTap: {})
            MascotView(pose: .idle, progress: 0.3, bubbleText: nil, size: .tiny, todoBadge: 12, onTodoTap: {})
            MascotView(pose: .breakDue, progress: 0.7, bubbleText: nil, size: .small, todoBadge: 3, onTodoTap: {})
            MascotView(pose: .breakDue, progress: 0.7, bubbleText: "Time to stretch! 🌱", size: .medium, todoBadge: 3, onTodoTap: {})
            MascotView(pose: .idle, progress: 0.3, bubbleText: nil, size: .large, todoBadge: 5, onTodoTap: {})
        }
        snapshot(sizesSheet, name: "mascot_badge_sizes_\(mode)", dark: dark, dir: dir, pad: 8)

        let badges = HStack(spacing: 0) {
            ForEach([3, 12, 0], id: \.self) { n in
                MascotView(pose: .idle, progress: 0.3, bubbleText: n == 12 ? "You have 12 to-dos 🌱" : nil,
                           todoBadge: n, onTodoTap: {})
            }
            MascotView(pose: .working, progress: 0.3, bubbleText: nil, size: .tiny, todoBadge: 2, onTodoTap: {})
            MascotView(pose: .working, progress: 0.3, bubbleText: nil, size: .large, todoBadge: 5, onTodoTap: {})
        }
        snapshot(badges, name: "mascot_badge_\(mode)", dark: dark, dir: dir, pad: 8)
    }
    print("Wrote to-do PNGs to \(dir.path)")
}

@MainActor
private func snapshot<V: View>(_ view: V, name: String, dark: Bool, dir: URL, pad: CGFloat = 26) {
    let bg = dark ? Color(red: 0x1E / 255, green: 0x1A / 255, blue: 0x24 / 255)
                  : Color(red: 0xF7 / 255, green: 0xF3 / 255, blue: 0xEE / 255)
    let hosting = NSHostingView(rootView: view.padding(pad).background(bg))
    let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = hosting
    hosting.layoutSubtreeIfNeeded()
    // Let onGeometryChange-driven state settle, then size to fit.
    for _ in 0..<3 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        hosting.layoutSubtreeIfNeeded()
    }
    let size = hosting.fittingSize
    hosting.frame = NSRect(origin: .zero, size: size)
    window.setContentSize(size)
    hosting.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { print("FAILED \(name)"); return }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    guard let png = rep.representation(using: .png, properties: [:]) else { print("FAILED \(name)"); return }
    try? png.write(to: dir.appendingPathComponent(name + ".png"))
}
