import SwiftUI
import AppKit
import MochiCore
import MochiUI

/// Renders the to-do card and the mascot badge through a real (offscreen) window so AppKit-backed
/// controls such as the text field draw correctly. Run: `swift run MochiPreview <dir> --todo`.
@MainActor
func renderTodoPreviews(into dir: URL) {
    if ProcessInfo.processInfo.environment["MOCHI_LOOPTEST"] == "1" { runResizeLoopTest(); return }
    let cal = Calendar.current
    let now = Date()
    let today = cal.startOfDay(for: now)
    let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
    let at3pm = cal.date(bySettingHour: 15, minute: 0, second: 0, of: today)

    let items = [
        TodoItem(title: "Reply to Mina's email", day: yesterday),
        TodoItem(title: "Go for a walkie", day: today, time: at3pm),
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
            ("links", AskMochiState(
                reply: "How about a cosy pasta night? Garlic, cherry tomatoes and basil take about 20 minutes 🍝",
                links: [AskLink(title: "🍳 Recipes", url: URL(string: "https://www.google.com/search?q=pasta+recipes")!),
                        AskLink(title: "📍 Nearby", url: URL(string: "https://www.google.com/maps/search/pasta")!)])),
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

        let weekDays: [TodoWeekDay] = (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: today)!
            let its: [TodoItem] = i == 0 ? [items[1], items[3]]
                : i == 3 ? [TodoItem(title: "Dentist appointment", day: d, time: at3pm),
                            TodoItem(title: "Pick up the parcel", day: d)]
                : []
            return TodoWeekDay(date: d, items: its, openCount: its.filter { !$0.done }.count, isToday: i == 0)
        }
        let actionsDay = TodoCardActions(add: { _ in }, toggle: { _ in }, delete: { _ in },
                                         moveUnfinishedToTomorrow: {}, close: {}, addOnDay: { _, _ in })
        snapshot(TodoCardView(items: items, now: now, actions: actionsDay, showMoveToTomorrow: true,
                              week: [TodoWeekDay(date: weekDays[0].date, items: items, openCount: 3, isToday: true)] + weekDays.dropFirst()),
                 name: "todo_week_today_items_\(mode)", dark: dark, dir: dir)
        snapshot(TodoCardView(items: weekDays[0].items, now: now, actions: actionsDay, showMoveToTomorrow: true,
                              week: weekDays),
                 name: "todo_week_list_\(mode)", dark: dark, dir: dir)
        snapshot(TodoCardView(items: weekDays[0].items, now: now, actions: actionsDay, showMoveToTomorrow: true,
                              week: weekDays, initialTarget: weekDays[3].date),
                 name: "todo_week_pill_\(mode)", dark: dark, dir: dir)
        let emptyToday = weekDays.enumerated().map { i, d in
            i == 0 ? TodoWeekDay(date: d.date, items: [], openCount: 0, isToday: true) : d
        }
        snapshot(TodoCardView(items: [], now: now, actions: actionsDay, showMoveToTomorrow: false, week: emptyToday),
                 name: "todo_week_today_empty_\(mode)", dark: dark, dir: dir)

        let voice = HStack(alignment: .bottom, spacing: 0) {
            MascotView(pose: .idle, progress: 0.3, bubbleText: nil, size: .tiny, listening: true, onHoldStart: {})
            MascotView(pose: .idle, progress: 0.3, bubbleText: nil, size: .tiny, listening: true,
                       liveText: "remind me to call mom at three and also buy milk", onHoldStart: {})
            MascotView(pose: .thinking, progress: 0.3, bubbleText: nil, size: .tiny)
            MascotView(pose: .chatting, progress: 0.3, bubbleText: "Sure! I added 'call mom' for 3:00 PM and put milk on your list 🥛", size: .tiny)
            MascotView(pose: .idle, progress: 0.3, bubbleText: nil, size: .medium, listening: true, onHoldStart: {})
            MascotView(pose: .idle, progress: 0.3, bubbleText: nil, size: .medium, listening: true,
                       liveText: "remind me to call mom at three", onHoldStart: {})
            MascotView(pose: .thinking, progress: 0.3, bubbleText: nil, size: .medium)
            MascotView(pose: .chatting, progress: 0.3, bubbleText: "Sure! I added 'call mom' for 3:00 PM and put milk on your list 🥛", size: .medium)
        }
        snapshot(voice, name: "mascot_voice_\(mode)", dark: dark, dir: dir, pad: 8)
        snapshot(HStack(spacing: 0) {
            MascotView(pose: .idle, progress: 0.3, bubbleText: nil, size: .tiny, calm: true, listening: true)
            MascotView(pose: .thinking, progress: 0.3, bubbleText: nil, size: .tiny, calm: true)
        }, name: "mascot_voice_calm_\(mode)", dark: dark, dir: dir, pad: 8)

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

// MARK: - Resize-loop harness (`MOCHI_LOOPTEST=1 swift run MochiPreview <dir> --todo`)

private final class ResizeCounter: @unchecked Sendable { var count = 0 }

@MainActor @Observable
private final class LoopModel {
    var tick = 0
    var week: [TodoWeekDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: today)!
            let n = i % 2 == 0 ? 3 + (tick % 3) : 0
            let its = (0..<n).map { TodoItem(title: "Task \(i)-\($0) with a fairly long title that wraps to two lines", day: d) }
            return TodoWeekDay(date: d, items: its, openCount: n, isToday: i == 0)
        }
    }
}

@MainActor
func runResizeLoopTest() {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let model = LoopModel()
    let anchor = FloatingPanelController(rootView: Color.clear, size: .tiny)
    anchor.show()
    // Put Mochi mid-screen (like the user's report) so the card is placed away from the screen edges.
    if let a = NSApp.windows.first(where: { $0.frame == anchor.frame }), let scr = NSScreen.main {
        a.setFrameOrigin(NSPoint(x: scr.visibleFrame.maxX - a.frame.width - 24, y: scr.visibleFrame.midY - 40))
    }
    let controller = TodoCardController(anchor: anchor)
    let counter = ResizeCounter()
    let tok = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: nil, queue: .main) { n in
        if let w = n.object, String(describing: type(of: w)).contains("TodoCardPanel") { counter.count += 1 }
    }
    let actions = TodoCardActions(add: { _ in }, toggle: { _ in }, delete: { _ in },
                                  moveUnfinishedToTomorrow: {}, close: {}, addOnDay: { _, _ in })
    controller.show(items: { model.week[0].items }, now: { Date() }, showMoveToTomorrow: { true },
                    week: { model.week }, actions: actions)
    let start = Date()
    var ticks = 0
    while Date().timeIntervalSince(start) < 2.5 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        if Date().timeIntervalSince(start) > 0.5 + Double(ticks) * 0.12, ticks < 8 { model.tick += 1; ticks += 1 }
        if ticks == 2 { NSApp.windows.first { $0.frame == anchor.frame }?.setFrameOrigin(NSPoint(x: 400, y: 120)) }
    }
    NotificationCenter.default.removeObserver(tok)
    print("card panel resizes in 2.5s: \(counter.count)")
    controller.hide()
}
