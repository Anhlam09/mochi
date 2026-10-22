import Foundation
import MochiCore

@MainActor func runExtrasChecks() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let us = Locale(identifier: "en_US")
    @MainActor func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    let idle = Phase.idle

    check("wake greeting: day parts, name, localized date, 10 minute rule") {
        @MainActor func g(_ h: Int, _ m: Int = 0, name: String = "") -> String { WakeGreeting.line(now: at(22, h, m), name: name, calendar: cal, locale: us) }
        expect(g(8) == "Good morning! ☀️ It's Thursday, October 22.", g(8))
        expect(g(13, name: "Anh") == "Good afternoon, Anh! 🌤️ It's Thursday, October 22.", g(13, name: "Anh"))
        expect(g(19) == "Good evening! 🌙 It's Thursday, October 22.", g(19))
        expect(g(5) == "Good morning! ☀️ It's Thursday, October 22." && g(11, 59).hasPrefix("Good morning"))
        expect(g(12).hasPrefix("Good afternoon") && g(16, 59).hasPrefix("Good afternoon"))
        expect(g(17).hasPrefix("Good evening") && g(21, 59).hasPrefix("Good evening"))
        expect(g(22) == "Hi again 🌙 It's late, be gentle with yourself", g(22))
        expect(g(3, name: "Anh") == "Hi again, Anh 🌙 It's late, be gentle with yourself")
        expect(!g(23).contains("October") && !g(4, 59).contains("Thursday"), "no date at night")
        expect(!WakeGreeting.shouldGreet(awayFor: 599) && WakeGreeting.shouldGreet(awayFor: 600))
        let fr = WakeGreeting.line(now: at(22, 9), name: "", calendar: cal, locale: Locale(identifier: "fr_FR"))
        expect(fr.contains("jeudi") && fr.contains("octobre"), "localized: \(fr)")
    }

    check("good night: window, once per night, not after 2:00, quiet when away") {
        @MainActor func due(_ day: Int, _ h: Int, _ m: Int = 0, hour: Int = 20, last: Date? = nil, active: Bool = true, phase: Phase = .idle) -> Bool {
            GoodNight.isDue(now: at(day, h, m), hour: hour, lastNight: last, userActive: active, phase: phase, calendar: cal)
        }
        expect(!due(22, 19, 59) && due(22, 20) && due(22, 23, 40), "from the set hour on")
        expect(due(22, 21, hour: 21) && !due(22, 20, 59, hour: 21))
        expect(due(22, 19, hour: 19) && !due(22, 22, hour: 99) && due(22, 23, hour: 99), "hour clamps to 19...23")
        expect(!due(22, 22, active: false), "only when active")
        expect(!due(22, 22, phase: .breakDue(since: at(22, 22), snoozes: 0)))
        let key = GoodNight.key(at(22, 20), calendar: cal)
        expect(!due(22, 21, last: key), "once per evening")
        expect(due(23, 0, 30), "after midnight is still that evening")
        expect(!due(23, 0, 30, last: key), "but not twice")
        expect(due(23, 1, 59) && !due(23, 2, 0) && !due(23, 5), "never after 2:00")
        expect(due(23, 20, last: key), "the next evening is a new night")
        expect(GoodNight.lines.count >= 8 && GoodNight.lines.contains("Have an amazing night! 🌙")
               && GoodNight.lines.contains("You did enough today. Have a cozy night ✨") && GoodNight.lines.contains("Rest well tonight, see you tomorrow 💤"))
    }

    check("meal ideas: curated lists, vegetarian filter, windows, once a day, waits for focus") {
        expect(MealIdeas.lunch.count >= 40 && MealIdeas.dinner.count >= 40)
        expect(Set(MealIdeas.lunch.map(\.id)).count == MealIdeas.lunch.count && Set(MealIdeas.dinner.map(\.id)).count == MealIdeas.dinner.count)
        expect(MealIdeas.lunch.contains { $0.vegetarian } && MealIdeas.lunch.contains { !$0.vegetarian })
        expect(MealIdeas.pool(.lunch, mode: .vegetarian).allSatisfy(\.vegetarian) && MealIdeas.pool(.dinner, mode: .vegetarian).count >= 20)
        expect(MealIdeas.pool(.dinner, mode: .any).count == MealIdeas.dinner.count)
        for i in MealIdeas.lunch + MealIdeas.dinner { expect(!i.text.isEmpty && LineSanitizer.containsEmoji(i.line) && i.line.count <= 70, i.line) }
        expect(MealIdeas.lunch[0].line.hasPrefix("Lunch idea: ") && MealIdeas.dinner[0].line == "Dinner idea: tacos with lots of lime 🌮", MealIdeas.dinner[0].line)
        // Windows: lunch 11:30-13:30 (aim ~12:00), dinner 17:30-19:30 (aim ~18:00).
        @MainActor func due(_ day: Int, _ h: Int, _ m: Int = 0, mode: MealMode = .any, mem: MealMemory = .init(), active: Bool = true, phase: Phase = .idle) -> Meal? {
            MealPolicy.due(now: at(day, h, m), mode: mode, memory: mem, userActive: active, phase: phase, calendar: cal)
        }
        expect(due(22, 11, 29) == nil && due(22, 13, 31) == nil && due(22, 15) == nil && due(22, 20) == nil)
        expect(due(22, 13, 30) == .lunch && due(22, 12, 31) == .lunch, "everything in the back half of the window is due")
        var offsets: [Double] = []
        for d in 1...28 {
            let first = (0..<121).map { at(d, 11, 30).addingTimeInterval(Double($0) * 60) }.first { MealPolicy.due(now: $0, mode: .any, memory: .init(), userActive: true, phase: idle, calendar: cal) == .lunch }!
            offsets.append(first.timeIntervalSince(at(d, 11, 30)) / 60)
        }
        expect(offsets.min()! >= 0 && offsets.max()! <= 60 && Set(offsets).count > 5, "aim time spreads over 11:30-12:30, about 12:00 on average")
        expect(due(22, 19, 0) == .dinner && due(22, 19, 31) == nil && due(22, 17, 29) == nil)
        expect(due(22, 12, 45, mode: .off) == nil && due(22, 12, 45, active: false) == nil)
        expect(due(22, 12, 45, phase: .focusing(end: at(22, 13))) == nil, "waits during focus")
        expect(due(22, 12, 45, phase: .breakDue(since: at(22, 12), snoozes: 0)) == nil && due(22, 12, 45, phase: .snoozed(end: at(22, 13), snoozes: 1)) == nil)
        expect(due(22, 12, 45, phase: .onBreak(end: at(22, 13))) == .lunch && due(22, 12, 45, phase: .paused(remaining: 60, resume: .focusing)) == .lunch, "a break or an idle timer is fine")
        // Once per meal per day.
        var mem = MealMemory()
        let idea = MealPolicy.pick(.lunch, mode: .any, memory: mem, now: at(22, 12, 45), random: { _ in 0 })!
        MealPolicy.commit(idea, to: &mem, now: at(22, 12, 45), calendar: cal)
        expect(due(22, 13, 0, mem: mem) == nil && due(22, 19, 0, mem: mem) == .dinner && due(23, 13, 0, mem: mem) == .lunch)
    }
    check("meal ideas: never repeat within 7 days, vegetarian only when asked") {
        var mem = MealMemory()
        var seen: [String] = []
        for day in 0..<7 {
            let now = at(10 + day, 12)
            let idea = MealPolicy.pick(.lunch, mode: .any, memory: mem, now: now, random: { _ in 0 })!
            expect(!seen.contains(idea.id), "repeat within a week: \(idea.id)")
            seen.append(idea.id)
            MealPolicy.commit(idea, to: &mem, now: now, calendar: cal)
        }
        let after7 = MealPolicy.pick(.lunch, mode: .any, memory: mem, now: at(16, 13), random: { _ in 0 })!
        expect(after7.id == "l08", "seven ideas are resting: \(after7.id)")
        let wk = MealPolicy.pick(.lunch, mode: .any, memory: mem, now: at(17, 12), random: { _ in 0 })!
        expect(wk.id == "l01", "after 7 days an idea can return: \(wk.id)")
        for _ in 0..<60 {
            let v = MealPolicy.pick(.dinner, mode: .vegetarian, memory: .init(), now: at(10, 18))!
            expect(v.vegetarian, v.line)
        }
        // Exhausted pool falls back to the longest-ago idea.
        var all = MealMemory()
        for (i, m) in MealIdeas.lunch.enumerated() { all.recent[m.id] = at(10, 8).addingTimeInterval(Double(i)) }
        expect(MealPolicy.pick(.lunch, mode: .any, memory: all, now: at(11, 8), random: { _ in 0 })?.id == "l01")
        let json = String(decoding: try JSONEncoder().encode(mem), as: UTF8.self)
        expect(!json.isEmpty && !json.contains("ramen"), "memory holds ids only")
    }

    check("self-care: interval, timer states, quiet hours, other lines, rotation") {
        @MainActor func due(_ h: Int, _ m: Int = 0, minutes: Int = 60, last: Date, other: Date? = nil, active: Bool = true, phase: Phase = .idle) -> Bool {
            SelfCare.isDue(now: at(22, h, m), minutes: minutes, lastNudge: last, lastOtherLine: other, userActive: active, phase: phase, calendar: cal)
        }
        expect(!due(10, 59, last: at(22, 10)) && due(11, last: at(22, 10)), "hourly")
        expect(due(10, 30, minutes: 30, last: at(22, 10)) && !due(10, 29, minutes: 30, last: at(22, 10)), "every 30 minutes")
        expect(!due(12, minutes: 0, last: at(22, 8)), "off")
        expect(!due(12, last: at(22, 8), active: false))
        for phase in [Phase.focusing(end: at(22, 13)), .breakDue(since: at(22, 12), snoozes: 0), .snoozed(end: at(22, 13), snoozes: 1), .onBreak(end: at(22, 13))] {
            expect(!due(12, last: at(22, 8), phase: phase), "\(phase)")
        }
        expect(due(12, last: at(22, 8), phase: .idle) && due(12, last: at(22, 8), phase: .paused(remaining: 60, resume: .focusing)), "idle or paused")
        expect(!due(22, 0, last: at(22, 12)) && !due(3, last: at(22, 1)) && !due(6, 59, last: at(22, 1)))
        expect(due(7, 0, last: at(22, 5)) && due(21, 59, last: at(22, 20)), "quiet only from 22:00 to 7:00")
        expect(!due(12, last: at(22, 8), other: at(22, 11, 55)) && due(12, last: at(22, 8), other: at(22, 11, 49)), "10 minutes after any other line")
        expect(SelfCare.lines.count >= 15 && Set(SelfCare.lines).count == SelfCare.lines.count)
        expect(SelfCare.lines.allSatisfy { LineSanitizer.containsEmoji($0) })
        var r = LineRotor(memory: 3)
        var picks: [Int] = []
        for _ in 0..<200 { picks.append(r.next(count: SelfCare.lines.count)) }
        for i in 3..<picks.count { expect(!picks[(i - 3)..<i].contains(picks[i]), "repeated within 3 at \(i)") }
        var one = LineRotor(memory: 3)
        expect(one.next(count: 1) == 0 && one.next(count: 1) == 0, "tiny pools still answer")
    }
    check("ask: meal requests are detected, to-dos are not") {
        for t in ["Lunch idea 🥪", "Dinner idea 🍝", "lunch idea", "give me a meal idea", "what should I eat?", "What's for dinner?",
                  "whats for lunch", "what’s for dinner tonight", "any food ideas? food idea please", "snack idea", "I need ideas for dinner"] {
            expect(MealRequest.isRequest(t), t)
        }
        for t in ["dinner with Sam at 7", "remind me to cook dinner", "call mom at lunch", "plan my day", "buy lunch supplies tomorrow",
                  "move the dinner reservation to friday", "what's left today?", ""] {
            expect(!MealRequest.isRequest(t), t)
        }
        @MainActor func meal(_ t: String, _ h: Int) -> Meal { MealRequest.meal(for: t, now: at(22, h), calendar: cal) }
        expect(meal("Lunch idea 🥪", 18) == .lunch && meal("Dinner idea 🍝", 9) == .dinner, "the word wins")
        expect(meal("what should I eat", 14) == .lunch && meal("what should I eat", 15) == .dinner && meal("snack idea", 8) == .lunch, "else by time")
        expect(meal("lunch or dinner idea", 20) == .lunch)
        expect(MealRequest.mode(from: .off) == .any && MealRequest.mode(from: .vegetarian) == .vegetarian && MealRequest.mode(from: .any) == .any)
        let ramen = MealIdeas.lunch[0]
        expect(MealRequest.reply(for: ramen) == "How about a warm bowl of ramen? 🍜 Easy and tasty.", MealRequest.reply(for: ramen))
        for i in MealIdeas.lunch + MealIdeas.dinner { expect(MealRequest.reply(for: i).count <= 90 && LineSanitizer.containsEmoji(MealRequest.reply(for: i)), i.id) }
    }
    check("ask: on-demand ideas keep the vegetarian filter, rest for 7 days, and don't use up the scheduled one") {
        var mem = MealMemory()
        var seen: Set<String> = []
        for i in 0..<12 {
            let now = at(22, 9, i)
            let idea = MealPolicy.pick(.dinner, mode: MealRequest.mode(from: .vegetarian), memory: mem, now: now, random: { _ in 0 })!
            expect(idea.vegetarian && !seen.contains(idea.id), "\(idea.id) repeated or not vegetarian")
            seen.insert(idea.id)
            MealPolicy.commit(idea, to: &mem, now: now, calendar: cal, markDay: false)
        }
        expect(mem.lunchDay == nil && mem.dinnerDay == nil, "asked-for ideas don't mark the day")
        expect(MealPolicy.due(now: at(22, 19), mode: .any, memory: mem, userActive: true, phase: .idle, calendar: cal) == .dinner)
        let off = MealPolicy.pick(.lunch, mode: MealRequest.mode(from: .off), memory: .init(), now: at(22, 12), random: { _ in 0 })
        expect(off != nil, "Off still answers when asked")
    }
    check("meal links: clean Google URLs from the dish name only") {
        for i in MealIdeas.lunch + MealIdeas.dinner {
            expect(!i.searchTerm.isEmpty && i.searchTerm.count <= 40 && i.searchTerm == i.searchTerm.lowercased(), i.id)
            let l = i.links
            expect(l.map(\.title) == ["🍳 Recipes", "📍 Nearby"], i.id)
            expect(l[0].url.host == "www.google.com" && l[0].url.path == "/search" && l[0].url.scheme == "https", l[0].url.absoluteString)
            expect(l[1].url.host == "www.google.com" && l[1].url.path.hasPrefix("/maps/search/"), l[1].url.absoluteString)
            expect(!l[0].url.absoluteString.contains(" ") && !l[1].url.absoluteString.contains(" "))
        }
        let ramen = MealIdeas.lunch[0].links
        expect(ramen[0].url.absoluteString == "https://www.google.com/search?q=ramen+recipe", ramen[0].url.absoluteString)
        expect(ramen[1].url.absoluteString == "https://www.google.com/maps/search/ramen+near+me", ramen[1].url.absoluteString)
        let tacos = MealIdeas.dinner[0].links
        expect(tacos[0].url.absoluteString == "https://www.google.com/search?q=tacos+recipe")
        let odd = MealIdea(id: "x1", text: "t", emoji: "🍜", vegetarian: true, meal: .lunch, searchTerm: "mac & cheese ü")
        expect(odd.links[0].url.absoluteString == "https://www.google.com/search?q=mac+%26+cheese+%C3%BC+recipe", odd.links[0].url.absoluteString)
        let bad = MealIdea(id: "x2", text: "t", emoji: "🍜", vegetarian: true, meal: .lunch, searchTerm: "a#b?c=d/e")
        expect(bad.links[0].url.query == "q=a%23b%3Fc%3Dd%2Fe+recipe", bad.links[0].url.query ?? "nil")
        // No user data: the links depend on the idea alone (no name, to-dos, times, ids).
        let all = (MealIdeas.lunch + MealIdeas.dinner).flatMap(\.links).map(\.url.absoluteString).joined()
        expect(!all.lowercased().contains("uuid") && !all.contains("@"), "nothing but the dish name goes into a link")
    }
    check("ask state: meal replies carry links, the next reply or a reset clears them") {
        let idea = MealIdeas.lunch[0]
        let meal = MealRequest.state(for: idea)
        expect(meal.reply == MealRequest.reply(for: idea) && meal.links.count == 2 && meal.actionsTaken.isEmpty && !meal.isThinking)
        let thinking = AskMochiState(reply: nil, isThinking: true, actionsTaken: [], unavailableReason: nil)
        expect(thinking.links.isEmpty, "a new question clears the links")
        let plan = AskMochiState(reply: "Start with the report.", isThinking: false, actionsTaken: [])
        expect(plan.links.isEmpty, "a normal reply has none")
        expect(AskMochiState() == AskMochiState(reply: nil, isThinking: false, actionsTaken: [], unavailableReason: nil, links: []), "reset state is empty")
        expect(AskMochiState().links.isEmpty && AskMochiState().reply == nil)
    }
    check("settings: extras defaults and persistence") {
        let name = "mochi.checks.extras.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        let s = MochiSettings(defaults: d)
        expect(s.wakeGreeting && s.goodNight && s.goodNightHour == 20 && s.mealMode == .any && s.selfCareMinutes == 60)
        s.wakeGreeting = false; s.goodNightHour = 22; s.mealIdeas = MealMode.vegetarian.rawValue; s.selfCareMinutes = 30
        let t = MochiSettings(defaults: d)
        expect(!t.wakeGreeting && t.goodNightHour == 22 && t.mealMode == .vegetarian && t.selfCareMinutes == 30)
        d.set(3, forKey: "goodNightHour"); d.set("junk", forKey: "mealIdeas"); d.set(45, forKey: "selfCareMinutes")
        let u = MochiSettings(defaults: d)
        expect(u.goodNightHour == 19 && u.mealMode == .any && u.selfCareMinutes == 60, "bad values fall back or clamp")
        d.removePersistentDomain(forName: name)
    }
}
