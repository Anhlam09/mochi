import Foundation
import MochiCore

@MainActor func runChatterChecks() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    check("day parts") {
        expect(DayPart(hour: 4) == .night && DayPart(hour: 5) == .morning)
        expect(DayPart(hour: 11) == .morning && DayPart(hour: 12) == .afternoon)
        expect(DayPart(hour: 17) == .evening && DayPart(hour: 22) == .night && DayPart(hour: 0) == .night)
    }
    check("name fills in, or vanishes cleanly") {
        expect(Chatter.fill("Good morning, {name}! ☀️", name: "Anh") == "Good morning, Anh! ☀️")
        expect(Chatter.fill("Good morning, {name}! ☀️", name: " ") == "Good morning! ☀️")
        expect(Chatter.fill("Hey {name}, you rock", name: "") == "Hey, you rock")
        expect(Chatter.fill("Hey {name}, you rock", name: "Anh") == "Hey Anh, you rock")
    }
    check("every line exists, uses only known placeholders and fits the bubble") {
        for moment in ChatMoment.allCases {
            for part in [DayPart.morning, .afternoon, .evening, .night] {
                for (weekday, month) in zip(1...7, [1, 4, 7, 10, 12, 2, 6]) {
                    let lines = Chatter.lines(for: moment, part: part, weekday: weekday, month: month)
                    expect(!lines.isEmpty, "\(moment) \(part) \(weekday)")
                    for t in lines {
                        let filled = Chatter.fill(t, name: "Sam")
                        expect(!filled.contains("{"), t)
                        expect(filled.count <= 64, "too long for the bubble: \(filled)")
                    }
                }
            }
        }
    }
    check("weekday greetings") {
        expect(Chatter.lines(for: .greeting, part: .morning, weekday: 2).contains { $0.contains("Monday") })
        expect(!Chatter.lines(for: .greeting, part: .afternoon, weekday: 2).contains { $0.contains("Monday") })
        expect(Chatter.lines(for: .greeting, part: .evening, weekday: 6).contains { $0.contains("Friday") })
    }
    check("weekend and seasonal check-ins") {
        expect(Chatter.lines(for: .checkIn, part: .afternoon, weekday: 7).contains { $0.contains("weekend") })
        expect(!Chatter.lines(for: .checkIn, part: .afternoon, weekday: 4).contains { $0.contains("weekend") })
        expect(Chatter.lines(for: .checkIn, part: .morning, weekday: 4, month: 10).contains { $0.contains("🍂") })
        expect(!Chatter.lines(for: .checkIn, part: .night, weekday: 4, month: 10).contains { $0.contains("🍂") })
    }
    check("chatter avoids recent repeats") {
        var c = Chatter(name: "Anh")
        let pool = Chatter.lines(for: .tapped, part: .morning, weekday: 3).count
        var seen: [String] = []
        for _ in 0..<pool { seen.append(c.line(for: .tapped, at: date(13, 9), calendar: cal, pick: { _ in 0 })) }
        expect(Set(seen).count == pool, "\(seen)")
        // Once everything is recent it still answers.
        expect(!c.line(for: .tapped, at: date(13, 9), calendar: cal, pick: { _ in 0 }).isEmpty)
        // A bad index from `pick` is clamped.
        expect(!c.line(for: .cheer, at: date(13, 9), calendar: cal, pick: { $0 + 5 }).isEmpty)
    }
    check("greeting fits the time of day") {
        var c = Chatter()
        let evening = Chatter.lines(for: .greeting, part: .evening, weekday: 3).map { Chatter.fill($0, name: "") }
        expect(evening.contains(c.line(for: .greeting, at: date(13, 19), calendar: cal)))
    }
    check("one greeting per day; the day starts at 5am") {
        expect(ChatSchedule.needsGreeting(lastGreeting: nil, now: date(13, 9), calendar: cal))
        expect(!ChatSchedule.needsGreeting(lastGreeting: date(13, 6), now: date(13, 21), calendar: cal))
        // Up past midnight: still the same Mochi day.
        expect(!ChatSchedule.needsGreeting(lastGreeting: date(13, 22), now: date(14, 1), calendar: cal))
        expect(ChatSchedule.needsGreeting(lastGreeting: date(13, 22), now: date(14, 5), calendar: cal))
        expect(ChatSchedule.needsGreeting(lastGreeting: date(13, 4), now: date(13, 6), calendar: cal))
    }
    check("check-in gaps stay within ±25%") {
        let t = date(13, 9)
        expect(ChatSchedule.next(after: t, interval: 600, jitter: 0) == t.addingTimeInterval(450))
        expect(ChatSchedule.next(after: t, interval: 600, jitter: 1) == t.addingTimeInterval(750))
        expect(ChatSchedule.next(after: t, interval: 600, jitter: 7) == t.addingTimeInterval(750))
        expect(ChatLevel.off.interval == nil && ChatLevel.often.interval! < ChatLevel.sometimes.interval!)
    }
    check("flavor announcements fit the bubble") {
        var c = Chatter()
        for i in 0..<4 {
            let line = c.flavorLine(name: "Strawberry", emoji: "🍓", pick: { _ in i })
            expect(line.contains("Strawberry") && line.count <= 64, line)
        }
    }
    check("flavor settings persist; rotation on by default") {
        let suite = "mochi.checks.flavor"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let s = MochiSettings(defaults: d)
        expect(s.flavor == "strawberry" && s.flavorRotation)
        s.flavor = "matcha"; s.flavorRotation = false
        let t = MochiSettings(defaults: d)
        expect(t.flavor == "matcha" && !t.flavorRotation)
        d.removePersistentDomain(forName: suite)
    }
    check("chat settings persist; bad values fall back") {
        let suite = "mochi.checks.chat"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let s = MochiSettings(defaults: d)
        expect(s.chat == .sometimes, "new users get the gentler default")
        s.chatLevel = ChatLevel.sometimes.rawValue; s.friendName = "Anh"
        let t = MochiSettings(defaults: d)
        expect(t.chat == .sometimes && t.friendName == "Anh")
        d.set("chatterbox", forKey: "chatLevel")
        expect(MochiSettings(defaults: d).chat == .sometimes)
        d.set(ChatLevel.often.rawValue, forKey: "chatLevel")
        expect(MochiSettings(defaults: d).chat == .often, "a stored choice is kept")
        d.removePersistentDomain(forName: suite)
    }
}
