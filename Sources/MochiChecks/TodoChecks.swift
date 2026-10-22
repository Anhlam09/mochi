import Foundation
import MochiCore

@MainActor func runTodoChecks() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
    let local = Calendar.current

    // MARK: Parser (the detector reads the system clock, so these use the real now)

    check("parser: time today") {
        let now = Date()
        let p = TodoParser.parse("call mom 3pm", now: now, calendar: local)
        expect(p?.title == "call mom", "\(String(describing: p))")
        expect(p?.day == local.startOfDay(for: now))
        let c = p?.time.map { local.dateComponents([.hour, .minute], from: $0) }
        expect(c?.hour == 15 && c?.minute == 0, "\(String(describing: c))")
        expect(p?.time.map { local.isDate($0, inSameDayAs: now) } == true)
    }
    check("parser: tomorrow without a time") {
        let now = Date()
        let p = TodoParser.parse("report tomorrow", now: now, calendar: local)
        expect(p?.title == "report", "\(String(describing: p))")
        expect(p?.day == local.date(byAdding: .day, value: 1, to: local.startOfDay(for: now)))
        expect(p?.time == nil)
    }
    check("parser: weekday and time") {
        let now = Date()
        let p = TodoParser.parse("dentist friday 10am", now: now, calendar: local)
        expect(p?.title == "dentist", "\(String(describing: p))")
        expect(p.map { local.component(.weekday, from: $0.day) } == 6)
        expect(p.map { $0.day >= local.startOfDay(for: now) } == true)
        let c = p?.time.map { local.dateComponents([.hour, .minute], from: $0) }
        expect(c?.hour == 10 && c?.minute == 0)
    }
    check("parser: plain text, filler words, empty, passed time, long text") {
        let now = Date()
        let milk = TodoParser.parse("buy milk", now: now, calendar: local)
        expect(milk?.title == "buy milk" && milk?.day == local.startOfDay(for: now) && milk?.time == nil)
        expect(TodoParser.parse("  \n ", now: now, calendar: local) == nil)
        expect(TodoParser.parse("", now: now, calendar: local) == nil)
        let at = TodoParser.parse("call mom at 3pm", now: now, calendar: local)
        expect(at?.title == "call mom", "\(String(describing: at))")
        let mid = TodoParser.parse("lunch at noon with Sam", now: now, calendar: local)
        expect(mid?.title == "lunch with Sam", "\(String(describing: mid))")
        // A time with no day stays on today even when it is already behind us.
        let early = TodoParser.parse("stretch 12:01am", now: now, calendar: local)
        expect(early?.day == local.startOfDay(for: now), "\(String(describing: early))")
        // Ambiguous words are not dates.
        expect(TodoParser.parse("buy sun cream", now: now, calendar: local)?.title == "buy sun cream")
        let long = TodoParser.parse(String(repeating: "x", count: 300), now: now, calendar: local)
        expect(long?.title.count == 120)
    }

    // MARK: Store

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mochi-check-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("todos.json")
    }
    func perms(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
    }
    let now = date(14, 10)

    check("store: persistence round-trip with private permissions") {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let s = TodoStore(fileURL: url, calendar: cal, now: now)
        expect(s.items.isEmpty)
        let a = s.add("buy milk", now: now)
        expect(a != nil && s.add("   ", now: now) == nil)
        s.toggle(id: a!.id, now: now)
        s.rename(id: a!.id, title: "  buy   oat milk ")
        let t = TodoStore(fileURL: url, calendar: cal, now: now)
        expect(t.items.count == 1 && t.items[0].title == "buy oat milk" && t.items[0].done && t.items[0].doneAt == now,
               "\(t.items)")
        expect(perms(url) == 0o600, "file mode \(String(describing: perms(url)))")
        expect(perms(url.deletingLastPathComponent()) == 0o700, "dir mode")
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        expect(leftovers == ["todos.json"], "\(leftovers)")
        t.delete(id: a!.id)
        expect(TodoStore(fileURL: url, calendar: cal, now: now).items.isEmpty)
    }
    check("store: corrupt file is moved aside, never lost") {
        let url = tempURL()
        let dir = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        let s = TodoStore(fileURL: url, calendar: cal, now: now)
        expect(s.items.isEmpty)
        let backup = s.recoveredBackupURL
        expect(backup?.lastPathComponent.hasPrefix("todos.corrupt-") == true && backup?.pathExtension == "json")
        expect(backup.flatMap { try? String(contentsOf: $0, encoding: .utf8) } == "{ not json")
        expect(!FileManager.default.fileExists(atPath: url.path))
        s.add("fresh start", now: now)
        expect(TodoStore(fileURL: url, calendar: cal, now: now).items.count == 1)
    }
    check("store: todayList ordering with carried-over items") {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let s = TodoStore(fileURL: url, calendar: cal, now: now)
        // Created on earlier days, so they are carried over (oldest day first).
        s.add("old12", now: date(12, 9))
        s.add("old13", now: date(13, 9))
        // Today: untimed in creation order (timed ordering is covered by the next check).
        s.add("rest1", now: now.addingTimeInterval(1))
        s.add("rest2", now: now.addingTimeInterval(4))
        let fin = s.add("finished", now: now.addingTimeInterval(5))!
        s.toggle(id: fin.id, now: date(14, 9, 30))
        let list0 = s.todayList(now: now).map(\.title)
        expect(list0 == ["old12", "old13", "rest1", "rest2", "finished"], "\(list0)")
        expect(s.counts(now: now) == (done: 1, left: 4), "\(s.counts(now: now))")
        expect(s.items.first { $0.title == "old12" }!.isCarriedOver(today: now, calendar: cal))
        // The next day: finished items drop off, everything else is carried over.
        let next = s.todayList(now: date(15, 9)).map(\.title)
        expect(next == ["old12", "old13", "rest1", "rest2"], "\(next)")
    }
    check("list: timed items sort by time between carried-over and untimed") {
        let day = cal.startOfDay(for: now)
        let base = date(14, 0)
        func mk(_ t: String, _ d: Date, _ time: Date?, _ c: Int) -> TodoItem {
            TodoItem(title: t, day: d, time: time, createdAt: base.addingTimeInterval(Double(c)))
        }
        let items = [
            mk("rest", day, nil, 1), mk("late", day, date(14, 15), 2), mk("early", day, date(14, 13), 3),
            mk("old", cal.date(byAdding: .day, value: -2, to: day)!, nil, 4),
            mk("oldTimed", cal.date(byAdding: .day, value: -1, to: day)!, date(13, 9), 5),
            mk("tomorrow", cal.date(byAdding: .day, value: 1, to: day)!, nil, 6),
        ]
        let titles = TodoList.today(items, now: now, calendar: cal).map(\.title)
        expect(titles == ["old", "oldTimed", "early", "late", "rest"], "\(titles)")
    }
    check("store: moveUnfinishedToTomorrow") {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let s = TodoStore(fileURL: url, calendar: cal, now: now)
        let a = s.add("a", now: now)!, b = s.add("b", now: now)!
        s.toggle(id: b.id, now: now)
        let c = s.add("c", now: now)!
        expect(s.moveUnfinishedToTomorrow(now: now) == 2)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
        let all = s.items
        func item(_ id: UUID) -> TodoItem { all.first { $0.id == id }! }
        expect(item(a.id).day == tomorrow && item(c.id).day == tomorrow)
        expect(item(b.id).day == cal.startOfDay(for: now), "done items stay")
        expect(s.counts(now: now) == (done: 1, left: 0))
        expect(s.counts(now: date(15, 9)) == (done: 0, left: 2))
        // Persisted.
        expect(TodoStore(fileURL: url, calendar: cal, now: now).items.filter { $0.day == tomorrow }.count == 2)
    }
    check("week: 7 days from today, items placed by day, today matches the today list") {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let s = TodoStore(fileURL: url, calendar: cal, now: now)
        s.add("old", now: date(12, 9))
        s.add("plain one", now: now)
        let fin = s.add("finished one", now: now)!
        s.toggle(id: fin.id, now: date(14, 9))
        @MainActor func on(_ title: String, _ day: Int, done: Bool = false) {
            let item = s.add(title, now: now, defaultDay: date(day, 0))!
            if done { s.toggle(id: item.id, now: date(14, 9)) }
        }
        on("fri b", 16); on("fri done", 16, done: true); on("fri a", 16); on("sun", 18); on("day7", 20); on("beyond", 21)
        let week = s.week(now: now)
        expect(week.count == 7 && week[0].isToday && !week[1].isToday)
        expect(week.map(\.date) == (0..<7).map { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now))! }, "consecutive days")
        expect(week[0].items == s.todayList(now: now), "today is the today list")
        expect(week[0].openCount == 2 && week[0].items.map(\.title) == ["old", "plain one", "finished one", "fri done"], "carried-over first, items ticked today last: \(week[0].items.map(\.title))")
        expect(week[2].items.map(\.title) == ["fri b", "fri a", "fri done"], "\(week[2].items.map(\.title)): open by creation, done last")
        expect(week[2].openCount == 2 && week[4].items.map(\.title) == ["sun"] && week[6].items.map(\.title) == ["day7"])
        expect(week[1].items.isEmpty && week[1].openCount == 0)
        expect(s.laterList(now: now).map(\.title) == ["beyond"], "later: \(s.laterList(now: now).map(\.title))")
        expect(!week.flatMap(\.items).contains { $0.title == "beyond" })
        // Timed items sort first on a future day.
        let t = TodoStore(fileURL: tempURL(), calendar: cal, now: now)
        defer { try? FileManager.default.removeItem(at: t.fileURL.deletingLastPathComponent()) }
        t.add("untimed", now: now, defaultDay: date(15, 0))
        t.add("late 5pm", now: now, defaultDay: date(15, 0)); t.add("early 9am", now: now, defaultDay: date(15, 0))
        expect(t.week(now: now)[1].items.map(\.title) == ["early", "late", "untimed"], "\(t.week(now: now)[1].items.map(\.title))")
    }
    check("week: daylight-saving changes still give seven distinct days") {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        for start in [DateComponents(year: 2026, month: 10, day: 30, hour: 23), DateComponents(year: 2026, month: 3, day: 5, hour: 1)] {
            let d = ny.date(from: start)!
            let week = TodoList.week([], now: d, calendar: ny)
            let days = week.map { ny.dateComponents([.year, .month, .day, .hour], from: $0.date) }
            expect(week.count == 7 && days.allSatisfy { $0.hour == 0 }, "\(days)")
            expect(Set(week.map(\.date)).count == 7)
            expect(zip(week, week.dropFirst()).allSatisfy { ny.isDate($1.date, inSameDayAs: ny.date(byAdding: .day, value: 1, to: $0.date)!) })
        }
    }
    check("store: a default day applies only when the text names no day") {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let s = TodoStore(fileURL: url, calendar: cal, now: now)
        let thu = cal.startOfDay(for: date(16, 0))
        let plain = s.add("buy milk", now: now, defaultDay: date(16, 12))!
        expect(plain.day == thu && plain.time == nil, "\(plain)")
        let timed = s.add("gym 6pm", now: now, defaultDay: date(16, 12))!
        expect(timed.day == thu && timed.time.map { cal.dateComponents([.hour, .minute, .day], from: $0) } == DateComponents(day: 16, hour: 18, minute: 0), "\(timed)")
        let today = s.add("buy milk", now: now)!
        expect(today.day == cal.startOfDay(for: now), "no default: today as before")
        // A day written in the text wins over the default (the detector reads the real clock, so only
        // check that it did not simply take the default).
        let real = Date()
        let tmp = TodoStore(fileURL: tempURL(), calendar: .autoupdatingCurrent, now: real)
        defer { try? FileManager.default.removeItem(at: tmp.fileURL.deletingLastPathComponent()) }
        let def = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 4, to: real)!
        let tomorrow = tmp.add("report tomorrow", now: real, defaultDay: def)!
        expect(tomorrow.day == Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Calendar.autoupdatingCurrent.startOfDay(for: real)), "explicit day wins")
        expect(tomorrow.title == "report")
    }
    check("store: prunes done items older than 30 days on load") {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let s = TodoStore(fileURL: url, calendar: cal, now: now)
        let old = s.add("old done", now: now.addingTimeInterval(-40 * 86400))!
        let recent = s.add("recent done", now: now.addingTimeInterval(-10 * 86400))!
        let open = s.add("old but open", now: now.addingTimeInterval(-40 * 86400))!
        s.toggle(id: old.id, now: now.addingTimeInterval(-39 * 86400))
        s.toggle(id: recent.id, now: now.addingTimeInterval(-9 * 86400))
        let t = TodoStore(fileURL: url, calendar: cal, now: now)
        expect(Set(t.items.map(\.id)) == [recent.id, open.id], "\(t.items.map(\.title))")
        expect(TodoStore(fileURL: url, calendar: cal, now: now).items.count == 2, "prune is saved")
    }

    // MARK: Agent

    func item(_ title: String, day: Int = 14, time: Date? = nil, done: Bool = false, doneAt: Date? = nil) -> TodoItem {
        TodoItem(title: title, day: cal.startOfDay(for: date(day, 0)), time: time, done: done, doneAt: doneAt,
                 createdAt: date(14, 7))
    }
    let on = TodoAgentSettings()
    func agent(_ r: Double = 0.1) -> TodoAgent { TodoAgent(calendar: cal, random: { r }) }

    check("agent: morning list once a day, only with items, only after 6") {
        var a = agent()
        let items = [item("a"), item("b")]
        expect(a.decide(now: date(14, 5, 30), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        let n = a.decide(now: date(14, 8), items: items, phase: .idle, event: nil, userActive: true, settings: on)
        expect(n?.kind == .morning && n?.text == "Good morning! 2 things today 🌱 Tap me to see!" && n?.openCard == false, "\(String(describing: n))")
        expect(a.decide(now: date(14, 8, 1), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        expect(a.decide(now: date(15, 8), items: items, phase: .idle, event: nil, userActive: true, settings: on)?.kind == .morning)
        var b = agent()
        expect(b.decide(now: date(14, 8), items: [], phase: .idle, event: nil, userActive: true, settings: on) == nil)
        expect(b.decide(now: date(14, 9), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil, "empty morning counts as said")
        var c = agent()
        expect(c.decide(now: date(14, 8), items: items, phase: .idle, event: nil, userActive: false, settings: on) == nil)
        expect(c.decide(now: date(14, 8, 5), items: items, phase: .idle, event: nil, userActive: true, settings: on)?.kind == .morning, "waits for the user")
    }
    check("agent: timed reminders fire once each, with a notification, even when away") {
        var a = agent()
        let call = item("Call mom", time: date(14, 15))
        var items = [call]
        expect(a.decide(now: date(14, 14, 40), items: items, phase: .idle, event: nil, userActive: false, settings: on) == nil)
        let soon = a.decide(now: date(14, 14, 50), items: items, phase: .idle, event: nil, userActive: false, settings: on)
        expect(soon?.kind == .reminderSoon && soon?.text == "⏰ In 10 min: Call mom", "\(String(describing: soon))")
        expect(soon?.showBubble == false && soon?.notificationBody == "Call mom", "away: notification only")
        expect(a.decide(now: date(14, 14, 51), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        let now = a.decide(now: date(14, 15, 0), items: items, phase: .focusing(end: date(14, 16)), event: nil, userActive: true, settings: on)
        expect(now?.kind == .reminderNow && now?.text == "⏰ Now: Call mom" && now?.showBubble == true)
        expect(a.decide(now: date(14, 15, 1), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        // Done items are not reminded; stale ones (an hour late) are skipped.
        var b = agent()
        items[0].done = true
        expect(b.decide(now: date(14, 15), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        var c = agent()
        expect(c.decide(now: date(14, 17), items: [call], phase: .idle, event: nil, userActive: true, settings: on)?.kind != .reminderNow)
        // Reminders stay on when gentle nudges are off, and never bubble during breakDue.
        var d = agent()
        var off = on; off.nudges = false
        let due = d.decide(now: date(14, 15), items: [call], phase: .breakDue(since: date(14, 15), snoozes: 0), event: nil, userActive: true, settings: off)
        expect(due?.kind == .reminderNow && due?.showBubble == false && due?.notificationTitle != nil)
        // Late start: "now" replaces the 10 min heads-up.
        var e = agent()
        expect(e.decide(now: date(14, 15, 2), items: [call], phase: .idle, event: nil, userActive: true, settings: on)?.kind == .reminderNow)
        expect(e.decide(now: date(14, 15, 3), items: [call], phase: .idle, event: nil, userActive: true, settings: on) == nil)
    }
    check("agent: break suggestion needs a 5 min break, an untimed item, and luck; once per break") {
        let onBreak = Phase.onBreak(end: date(14, 11, 5))
        let items = [item("Timed", time: date(14, 18)), item("Water plants")]
        let day = cal.startOfDay(for: date(14, 0))
        let lastCI = date(14, 10, 30)
        func primed(_ r: Double) -> TodoAgent { var x = TodoAgent(calendar: cal, random: { r }); x.memory.morningDay = day; x.memory.lastCheckIn = lastCI; return x }
        var a = primed(0.1)
        let n = a.decide(now: date(14, 11), items: items, phase: onBreak, event: .breakStarted, userActive: true, settings: on)
        expect(n?.kind == .breakSuggestion && n?.text == "Quick win while you rest? ✨ Water plants", "\(String(describing: n))")
        expect(a.decide(now: date(14, 11, 1), items: items, phase: onBreak, event: nil, userActive: true, settings: on) == nil)
        var unlucky = primed(0.9)
        expect(unlucky.decide(now: date(14, 11), items: items, phase: onBreak, event: .breakStarted, userActive: true, settings: on) == nil)
        var short = primed(0.1)
        expect(short.decide(now: date(14, 11), items: items, phase: .onBreak(end: date(14, 11, 0).addingTimeInterval(20)), event: .breakStarted, userActive: true, settings: on) == nil)
        var onlyTimed = primed(0.1)
        expect(onlyTimed.decide(now: date(14, 11), items: [items[0]], phase: onBreak, event: .breakStarted, userActive: true, settings: on) == nil)
        var quiet = primed(0.1)
        var off = on; off.nudges = false
        expect(quiet.decide(now: date(14, 11), items: items, phase: onBreak, event: .breakStarted, userActive: true, settings: off) == nil)
    }
    check("agent: check-in after focus, once per item per day and once an hour") {
        var a = TodoAgent(calendar: cal, random: { 0.9 }); a.memory.morningDay = cal.startOfDay(for: date(14, 0))
        let items = [item("Write report"), item("Email Sam")]
        let brk = Phase.onBreak(end: date(14, 11, 5))
        let due = Phase.breakDue(since: date(14, 10), snoozes: 0)
        // The check-in rides on the break starting, and wins over the break suggestion (one per break).
        expect(a.decide(now: date(14, 10), items: items, phase: due, event: .breakDue, userActive: true, settings: on) == nil, "no bubble during breakDue")
        let n = a.decide(now: date(14, 10), items: items, phase: brk, event: .breakStarted, userActive: true, settings: on)
        expect(n?.kind == .checkIn && n?.openCard == true && n?.text == "Did you get to 'Write report'? Tap me to tick it off ✅", "\(String(describing: n))")
        expect(a.decide(now: date(14, 10, 1), items: items, phase: due, event: nil, userActive: true, settings: on) == nil)
        expect(a.decide(now: date(14, 10, 30), items: items, phase: brk, event: .breakStarted, userActive: true, settings: on) == nil, "once an hour")
        let second = a.decide(now: date(14, 11, 30), items: items, phase: brk, event: .breakStarted, userActive: true, settings: on)
        expect(second?.text.contains("Email Sam") == true, "next item, not the same one")
        expect(a.decide(now: date(14, 13), items: items, phase: brk, event: .breakStarted, userActive: true, settings: on) == nil, "all asked today")
        expect(a.decide(now: date(15, 13), items: items, phase: brk, event: .breakStarted, userActive: true, settings: on)?.kind == .checkIn, "new day")
        var off = on; off.nudges = false
        var b = agent(); b.memory.morningDay = cal.startOfDay(for: date(14, 0))
        expect(b.decide(now: date(14, 10), items: items, phase: brk, event: .breakStarted, userActive: true, settings: off) == nil)
        var c = agent()
        expect(c.decide(now: date(14, 10), items: items, phase: brk, event: .breakStarted, userActive: false, settings: on) == nil)
    }
    check("agent: end-of-day wrap-up once, at the set time or the first active moment after") {
        var a = agent()
        let items = [item("a"), item("b"), item("c", done: true, doneAt: date(14, 12))]
        expect(a.decide(now: date(14, 17, 29), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil, "morning is dropped after noon")
        let n = a.decide(now: date(14, 17, 31), items: items, phase: .idle, event: nil, userActive: true, settings: on)
        expect(n?.kind == .wrapUp && n?.openCard == true && n?.text == "Finished 1 today 🎉 2 left: move to tomorrow? Tap me 🌙", "\(String(describing: n))")
        expect(a.decide(now: date(14, 17, 40), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        var b = agent()
        let allDone = [item("a", done: true, doneAt: date(14, 9)), item("b", done: true, doneAt: date(14, 10))]
        let w = b.decide(now: date(14, 18), items: allDone, phase: .idle, event: nil, userActive: true, settings: on)
        expect(w?.kind == .wrapUp && w?.text == "You finished 2 things today 🎉", "\(String(describing: w))")
        var c = agent()
        let leftOnly = c.decide(now: date(14, 20), items: [item("x")], phase: .idle, event: nil, userActive: true, settings: on)
        expect(leftOnly?.text == "1 left, move them to tomorrow? Tap me 🌙", "\(String(describing: leftOnly))")
        var d = agent()
        var custom = on; custom.wrapUpHour = 21; custom.wrapUpMinute = 0
        expect(d.decide(now: date(14, 18), items: [item("x")], phase: .idle, event: nil, userActive: true, settings: custom)?.kind != .wrapUp)
        var e = agent()
        var off = on; off.nudges = false
        expect(e.decide(now: date(14, 18), items: [item("x")], phase: .idle, event: nil, userActive: true, settings: off) == nil)
        var f = agent()
        expect(f.decide(now: date(14, 18), items: [], phase: .idle, event: nil, userActive: true, settings: on) == nil)
    }
    check("agent: celebrates when the last item gets ticked, once a day") {
        var a = agent()
        var items = [item("a"), item("b")]
        // Quiet start: the morning list has been said.
        _ = a.decide(now: date(14, 14), items: items, phase: .idle, event: nil, userActive: true, settings: on)
        items[0].done = true; items[0].doneAt = date(14, 14, 5)
        expect(a.decide(now: date(14, 14, 5), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        items[1].done = true; items[1].doneAt = date(14, 14, 10)
        let n = a.decide(now: date(14, 14, 10), items: items, phase: .idle, event: nil, userActive: true, settings: on)
        expect(n?.kind == .celebrate && n?.text == "All done for today! 🎉 You're amazing ✨", "\(String(describing: n))")
        expect(a.decide(now: date(14, 14, 11), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        // Un-tick and tick again the same day: no second party.
        items[1].done = false
        _ = a.decide(now: date(14, 14, 20), items: items, phase: .idle, event: nil, userActive: true, settings: on)
        items[1].done = true; items[1].doneAt = date(14, 14, 21)
        expect(a.decide(now: date(14, 14, 21), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        // A fresh launch with everything already done does not celebrate.
        var b = agent()
        expect(b.decide(now: date(14, 14), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
    }
    check("agent: priority order and quiet rules") {
        // Reminder beats check-in beats wrap-up beats morning.
        var a = agent()
        let items = [item("Call", time: date(14, 17, 40)), item("b")]
        let due = Phase.breakDue(since: date(14, 17, 35), snoozes: 0)
        expect(a.decide(now: date(14, 17, 35), items: items, phase: due, event: .breakDue, userActive: true, settings: on)?.kind == .reminderSoon)
        let brk = Phase.onBreak(end: date(14, 17, 45))
        var lucky = agent(0.1)
        _ = lucky.decide(now: date(14, 17, 35), items: items, phase: due, event: nil, userActive: true, settings: on)
        expect(lucky.decide(now: date(14, 17, 36), items: items, phase: brk, event: .breakStarted, userActive: true, settings: on)?.kind == .checkIn, "check-in beats the break suggestion")
        expect(a.decide(now: date(14, 17, 37), items: items, phase: due, event: .breakDue, userActive: true, settings: on) == nil, "no bubble at all during breakDue")
        expect(a.decide(now: date(14, 17, 38), items: items, phase: .idle, event: nil, userActive: true, settings: on)?.kind == .wrapUp)
        // Wrap-up (which was ready) did not use up the morning list before noon, but after noon morning is dropped.
        expect(a.decide(now: date(14, 17, 39), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil)
        var b = agent()
        expect(b.decide(now: date(14, 8), items: items, phase: .idle, event: nil, userActive: true, settings: on)?.kind == .morning)
        // Away: no bubbles at all.
        var c = agent()
        expect(c.decide(now: date(14, 18), items: [item("b")], phase: .idle, event: .breakDue, userActive: false, settings: on) == nil)
        // Switched off.
        var d = agent()
        var off = on; off.todosEnabled = false
        expect(d.decide(now: date(14, 17, 35), items: items, phase: .idle, event: nil, userActive: true, settings: off) == nil)
        // Titles cannot smuggle placeholders or run past the bubble.
        var e = agent()
        let nasty = [item("{name} " + String(repeating: "x", count: 80), time: date(14, 15))]
        let n = e.decide(now: date(14, 15), items: nasty, phase: .idle, event: nil, userActive: true, settings: on)
        expect(n.map { !$0.text.contains("{") && $0.text.count <= 40 } == true, "\(String(describing: n?.text))")
    }
    check("agent: memory round-trips as JSON and holds no titles") {
        var a = agent()
        let call = item("Secret dentist visit", time: date(14, 15))
        _ = a.decide(now: date(14, 14, 55), items: [call], phase: .idle, event: .breakDue, userActive: true, settings: on)
        let data = try JSONEncoder().encode(a.memory)
        expect(!String(decoding: data, as: UTF8.self).contains("dentist"))
        let back = try JSONDecoder().decode(TodoAgentMemory.self, from: data)
        expect(back == a.memory)
        var b = TodoAgent(memory: back, calendar: cal, random: { 0 })
        expect(b.decide(now: date(14, 14, 56), items: [call], phase: .idle, event: nil, userActive: true, settings: on) == nil, "remembers it already said so")
    }
    check("parser: merges day and time from separate phrases, strips connectors") {
        let now = Date()
        let tomorrow = local.date(byAdding: .day, value: 1, to: local.startOfDay(for: now))
        let a = TodoParser.parse("tomorrow call dentist at noon", now: now, calendar: local)
        expect(a?.title == "call dentist" && a?.day == tomorrow, "\(String(describing: a))")
        let ac = a?.time.map { local.dateComponents([.hour, .minute], from: $0) }
        expect(ac?.hour == 12 && ac?.minute == 0 && a?.time.map { local.isDate($0, inSameDayAs: tomorrow!) } == true)
        let b = TodoParser.parse("take pills at 8 am and 8 pm", now: now, calendar: local)
        expect(b?.title == "take pills", "\(String(describing: b))")
        expect(b?.time.map { local.component(.hour, from: $0) } == 8, "first time wins")
        let c = TodoParser.parse("call mom on friday at 3pm about the party", now: now, calendar: local)
        expect(c?.title == "call mom about the party" && c?.day != nil && c.map { local.component(.weekday, from: $0.day) } == 6, "\(String(describing: c))")
    }
    check("parser: bare times follow the daytime heuristic and never depend on the clock") {
        let now = Date()
        func hm(_ text: String) -> (String, Int, Int)? {
            guard let p = TodoParser.parse(text, now: now, calendar: local), let t = p.time else { return nil }
            if p.day != local.startOfDay(for: now) { return nil }   // a time with no day belongs to today
            let c = local.dateComponents([.hour, .minute], from: t)
            return (p.title, c.hour ?? -1, c.minute ?? -1)
        }
        let meeting = hm("meeting at 10")
        expect(meeting?.0 == "meeting" && meeting?.1 == 10 && meeting?.2 == 0, "\(String(describing: meeting))")
        let gym = hm("gym at 6")
        expect(gym?.0 == "gym" && gym?.1 == 18, "\(String(describing: gym))")
        let kids = hm("pick up kids 3:15")
        expect(kids?.0 == "pick up kids" && kids?.1 == 15 && kids?.2 == 15, "\(String(describing: kids))")
        let by = hm("send invoice by 5")
        expect(by?.0 == "send invoice" && by?.1 == 17, "\(String(describing: by))")
        let h24 = hm("train 15:30")
        expect(h24?.0 == "train" && h24?.1 == 15 && h24?.2 == 30, "\(String(describing: h24))")
        let am = hm("run 7am")
        expect(am?.1 == 7, "explicit am stays am: \(String(describing: am))")
        expect(hm("buy 3 apples")?.1 == nil, "a bare number is not a time")
        expect(TodoParser.parse("finish by 2 weeks", now: now, calendar: local)?.time == nil)
    }
    check("parser: input is capped at 500 characters") {
        let p = TodoParser.parse(String(repeating: "a ", count: 600) + "3pm", now: Date(), calendar: local)
        expect(p?.time == nil, "the time past the cap is never seen")
    }

    check("store: laterList, day labels, and a newer file version is backed up") {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let s = TodoStore(fileURL: url, calendar: cal, now: now)
        s.add("today", now: now)
        s.add("future b", now: date(14, 9), defaultDay: date(22, 0)); s.add("future a", now: date(14, 9), defaultDay: date(21, 0))
        s.add("inside the week", now: date(14, 9), defaultDay: date(20, 0))
        let later = s.laterList(now: now).map(\.title)
        expect(later == ["future a", "future b"], "\(later), the week itself is not 'later'")
        let day = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
        var us = cal; us.locale = Locale(identifier: "en_US_POSIX")
        expect(TodoList.dayLabel(day, now: now, calendar: cal) == "Fri", TodoList.dayLabel(day, now: now, calendar: cal))
        expect(TodoList.dayLabel(cal.date(byAdding: .day, value: 10, to: cal.startOfDay(for: now))!, now: now, calendar: cal) == "Oct 24")
        // A file written by a newer Mochi must be kept untouched.
        let newer = tempURL()
        defer { try? FileManager.default.removeItem(at: newer.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: newer.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = #"{"version": 99, "items": []}"#
        try Data(body.utf8).write(to: newer)
        let n = TodoStore(fileURL: newer, calendar: cal, now: now)
        expect(n.recoveredBackupURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } == body)
    }
    check("store: blocked writes never prune, and a failed save is retried") {
        let url = tempURL()
        let dir = url.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = TodoStore(fileURL: url, calendar: cal, now: now)
        s.add("keep", now: now)
        // A directory squatting on the file's path: the next mutation cannot be written.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        s.add("unsaved", now: now)
        expect(s.saveFailed && s.items.count == 2)
        try FileManager.default.removeItem(at: url)
        s.retrySaveIfNeeded()
        expect(!s.saveFailed && TodoStore(fileURL: url, calendar: cal, now: now).items.count == 2)
        // Daily pruning.
        let o = s.add("old", now: now.addingTimeInterval(-50 * 86400))!
        s.toggle(id: o.id, now: now.addingTimeInterval(-45 * 86400))
        s.pruneOldDone(now: now)
        expect(s.items.count == 2)
    }
    check("agent: a to-do moved to another day reminds again") {
        var a = agent()
        let day14 = cal.startOfDay(for: date(14, 0))
        var call = item("Call", time: date(14, 15))
        expect(a.decide(now: date(14, 14, 55), items: [call], phase: .idle, event: nil, userActive: true, settings: on)?.kind == .reminderSoon)
        expect(a.decide(now: date(14, 15), items: [call], phase: .idle, event: nil, userActive: true, settings: on)?.kind == .reminderNow)
        _ = day14
        call.day = cal.startOfDay(for: date(15, 0)); call.time = date(15, 15)
        expect(a.decide(now: date(15, 14, 55), items: [call], phase: .idle, event: nil, userActive: true, settings: on)?.kind == .reminderSoon, "new day, new reminder")
    }
    check("agent: only ticking the last open item celebrates, not delete, add or move") {
        let day = cal.startOfDay(for: date(14, 0))
        func primed() -> TodoAgent { var x = TodoAgent(calendar: cal, random: { 0.1 }); x.memory.morningDay = day; return x }
        // Deleting the last open item.
        var a = primed()
        var items = [item("a", done: true, doneAt: date(14, 9)), item("b")]
        _ = a.decide(now: date(14, 14), items: items, phase: .idle, event: nil, userActive: true, settings: on)
        items.removeLast()
        expect(a.decide(now: date(14, 14, 1), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil, "delete")
        // Moving it to tomorrow.
        var b = primed()
        items = [item("a", done: true, doneAt: date(14, 9)), item("b")]
        _ = b.decide(now: date(14, 14), items: items, phase: .idle, event: nil, userActive: true, settings: on)
        items[1].day = cal.startOfDay(for: date(15, 0))
        expect(b.decide(now: date(14, 14, 1), items: items, phase: .idle, event: nil, userActive: true, settings: on) == nil, "move")
        // Adding while empty, then ticking, does celebrate.
        var c = primed()
        items = [item("a", done: true, doneAt: date(14, 9)), item("b")]
        _ = c.decide(now: date(14, 14), items: items, phase: .idle, event: nil, userActive: true, settings: on)
        items[1].done = true; items[1].doneAt = date(14, 14, 2)
        expect(c.decide(now: date(14, 14, 2), items: items, phase: .idle, event: nil, userActive: true, settings: on)?.kind == .celebrate, "tick")
    }
    check("settings: to-do defaults") {
        let defaults = UserDefaults(suiteName: "mochi-check-\(UUID().uuidString)")!
        let s = MochiSettings(defaults: defaults)
        expect(s.todoNotificationText && s.todosEnabled && s.todoNudges && s.todoWrapUpHour == 17 && s.todoWrapUpMinute == 30)
        s.todoWrapUpHour = 19
        expect(MochiSettings(defaults: defaults).todoAgent == TodoAgentSettings(todosEnabled: true, wrapUpHour: 19, wrapUpMinute: 30, nudges: true))
    }
}
