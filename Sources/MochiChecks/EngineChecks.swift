import Foundation
import MochiCore

final class TestClock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ s: TimeInterval) { date = date.addingTimeInterval(s) }
}

@MainActor private func makeEngine(_ preset: Preset = .gentle) -> (TimerEngine, TestClock, EventLog) {
    let c = TestClock()
    let e = TimerEngine(preset: preset, clock: { c.date })
    let log = EventLog()
    e.onEvent = { log.events.append($0) }
    return (e, c, log)
}

@MainActor final class EventLog { var events: [EngineEvent] = [] }

@MainActor func runEngineChecks() {
    check("presets") {
        expect(Preset.gentle.spec(forCycle: 0) == BreakSpec(focus: 1200, rest: 20, kind: .eyes))
        expect(Preset.gentle.spec(forCycle: 2) == BreakSpec(focus: 1200, rest: 300, kind: .stretch))
        expect(Preset.gentle.spec(forCycle: 3).kind == .eyes)
        expect(Preset.pomodoro.spec(forCycle: 3) == BreakSpec(focus: 1500, rest: 900, kind: .long))
        expect(Preset.pomodoro.spec(forCycle: 2).rest == 300)
        expect(Preset.deepFocus.spec(forCycle: 5) == BreakSpec(focus: 3120, rest: 1020, kind: .short))
        expect(Preset.custom(focusMinutes: 30, breakMinutes: 5).id == "custom")
        expect(Preset.preset(id: "pomodoro") == .pomodoro)
        expect(!Tips.random(for: .eyes).isEmpty && !Tips.random(for: .long).isEmpty)
    }
    check("start → focusing, tick past end → breakDue once") {
        let (e, c, log) = makeEngine()
        expect(e.phase == .idle)
        e.start()
        guard case .focusing = e.phase else { expect(false, "not focusing"); return }
        c.advance(1201); e.tick(); e.tick()
        guard case .breakDue(_, 0) = e.phase else { expect(false, "not breakDue \(e.phase)"); return }
        expect(log.events.filter { $0 == .breakDue }.count == 1)
    }
    check("almostDone fires once") {
        let (e, c, log) = makeEngine()
        e.start()
        c.advance(1000); e.tick()
        expect(log.events.isEmpty)
        c.advance(100); e.tick(); e.tick()
        c.advance(10); e.tick()
        expect(log.events == [.almostDone], "\(log.events)")
    }
    check("snooze twice then refused; count retained") {
        let (e, c, log) = makeEngine()
        e.start(); c.advance(1201); e.tick()
        expect(e.snooze(minutes: 5))
        c.advance(301); e.tick()
        guard case .breakDue(_, 1) = e.phase else { expect(false, "\(e.phase)"); return }
        expect(e.snooze(minutes: 5))
        c.advance(301); e.tick()
        guard case .breakDue(_, 2) = e.phase else { expect(false, "\(e.phase)"); return }
        expect(!e.snooze(minutes: 5))
        expect(log.events.filter { $0 == .breakDue }.count == 3)
    }
    check("startBreak → onBreak → end → focusing") {
        let (e, c, log) = makeEngine()
        e.start(); c.advance(1201); e.tick()
        e.startBreak()
        guard case .onBreak = e.phase else { expect(false, "\(e.phase)"); return }
        expect(e.remaining == 20)
        c.advance(21); e.tick()
        guard case .focusing = e.phase else { expect(false, "\(e.phase)"); return }
        expect(e.completedBreaks == 1)
        expect(log.events.contains(.breakStarted) && log.events.suffix(2) == [.breakEnded, .breakCompleted])
    }
    check("break-now while focusing") {
        let (e, _, _) = makeEngine()
        e.start(); e.startBreak()
        guard case .onBreak = e.phase else { expect(false, "\(e.phase)"); return }
    }
    check("skipBreak") {
        let (e, c, _) = makeEngine()
        e.start(); c.advance(1201); e.tick()
        e.skipBreak()
        guard case .focusing = e.phase else { expect(false, "\(e.phase)"); return }
        expect(e.completedBreaks == 1)
    }
    check("pause/resume preserves remaining") {
        let (e, c, _) = makeEngine()
        e.start(); c.advance(100)
        e.pause()
        let r = e.remaining
        expect(r == 1100, "\(r)")
        c.advance(5000); e.tick()
        expect(e.remaining == r)
        expect(!e.isRunning)
        e.resume()
        expect(e.remaining == r)
        c.advance(50); e.tick()
        expect(e.remaining == r - 50)
    }
    check("clock jump far past focus end") {
        let (e, c, log) = makeEngine()
        e.start(); c.advance(100_000); e.tick()
        guard case .breakDue = e.phase else { expect(false, "\(e.phase)"); return }
        expect(log.events == [.breakDue])
    }
    check("clock jump far past break end") {
        let (e, c, _) = makeEngine()
        e.start(); e.startBreak(); c.advance(100_000); e.tick()
        guard case .focusing = e.phase else { expect(false, "\(e.phase)"); return }
    }
    check("gentle stretch rotation & pomodoro long") {
        let (e, _, _) = makeEngine()
        e.start()
        e.startBreak(); e.skipBreak(); e.startBreak(); e.skipBreak()
        expect(e.completedBreaks == 2)
        expect(e.currentSpec == BreakSpec(focus: 1200, rest: 300, kind: .stretch))
        let (p, _, _) = makeEngine(.pomodoro)
        p.start(); for _ in 0..<3 { p.startBreak(); p.skipBreak() }
        expect(p.currentSpec.kind == .long && p.currentSpec.rest == 900)
    }
    check("naturalBreak") {
        let (e, _, _) = makeEngine()
        e.start(); e.naturalBreak()
        expect(e.completedBreaks == 1)
        guard case .focusing = e.phase else { expect(false, "\(e.phase)"); return }
    }
    check("reset keeps completedBreaks; preset change restarts focus") {
        let (e, c, _) = makeEngine()
        e.start(); e.startBreak(); e.skipBreak(); c.advance(500); e.reset()
        expect(e.completedBreaks == 1 && e.remaining == 1200)
        c.advance(500); e.tick(); e.preset = .pomodoro
        expect(e.remaining == 1500)
    }
    check("overrides & progress bounds") {
        let c = TestClock()
        let e = TimerEngine(clock: { c.date }, focusOverride: 10, breakOverride: 4)
        expect(e.progress == 0)
        e.start()
        expect(e.progress == 0)
        c.advance(5); e.tick()
        expect(abs(e.progress - 0.5) < 0.001)
        c.advance(100); e.tick()
        expect(e.progress == 1)
        e.startBreak()
        c.advance(1); e.tick()
        expect(abs(e.progress - 0.25) < 0.001)
        expect(e.progress >= 0 && e.progress <= 1)
    }
    check("settings persist round-trip") {
        let suite = "mochi.checks"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let s = MochiSettings(defaults: d)
        expect(s.presetID == "gentle" && s.customFocusMinutes == 30 && s.customBreakMinutes == 5)
        expect(!s.soundEnabled && s.showMascot && !s.launchAtLogin)
        s.presetID = "custom"; s.customFocusMinutes = 45; s.customBreakMinutes = 10
        s.soundEnabled = true; s.showMascot = false; s.launchAtLogin = true
        let t = MochiSettings(defaults: d)
        expect(t.presetID == "custom" && t.customFocusMinutes == 45 && t.customBreakMinutes == 10)
        expect(t.soundEnabled && !t.showMascot && t.launchAtLogin)
        expect(t.preset.spec(forCycle: 0).focus == 2700)
        d.removePersistentDomain(forName: suite)
    }
    runReviewChecks()
    runAdjustChecks()
    runStopChecks()
    runM4ReviewChecks()
    runAwayChecks()
}

@MainActor private func runReviewChecks() {
    check("breakEnded fires once on skip/reset during break") {
        for action in [{ (e: TimerEngine) in e.skipBreak() }, { (e: TimerEngine) in e.reset() }] {
            let (e, _, log) = makeEngine()
            e.start(); e.startBreak(); action(e)
            expect(log.events.filter { $0 == .breakEnded }.count == 1, "\(log.events)")
            guard case .focusing = e.phase else { expect(false, "\(e.phase)"); return }
        }
    }
    check("naturalBreak is no-op on break/paused/idle") {
        let (e, _, log) = makeEngine()
        e.naturalBreak(); expect(e.completedBreaks == 0 && e.phase == .idle)
        e.start(); e.startBreak(); e.naturalBreak()
        guard case .onBreak = e.phase else { expect(false, "\(e.phase)"); return }
        expect(e.completedBreaks == 0 && !log.events.contains(.breakEnded))
        e.pause(); e.naturalBreak(); expect(e.completedBreaks == 0)
    }
    check("beginFocus uses fresh clock") {
        let (e, c, _) = makeEngine()
        let t0 = c.date
        c.advance(777); e.start()
        expect(e.phase == .focusing(end: t0.addingTimeInterval(777 + 1200)), "\(e.phase)")
        c.advance(50); e.preset = .pomodoro
        expect(e.phase == .focusing(end: t0.addingTimeInterval(827 + 1500)), "\(e.phase)")
    }
    check("preset change semantics per phase") {
        // focusing
        var (e, c, _) = makeEngine()
        e.start(); e.startBreak(); e.skipBreak(); c.advance(100)
        e.preset = .pomodoro
        expect(e.completedBreaks == 0 && e.remaining == 1500)
        // paused(focusing)
        (e, c, _) = makeEngine()
        e.start(); c.advance(100); e.pause(); e.preset = .deepFocus
        expect(e.phase == .paused(remaining: 3120, resume: .focusing), "\(e.phase)")
        // breakDue
        (e, c, _) = makeEngine()
        e.start(); c.advance(1201); e.tick(); e.preset = .pomodoro
        guard case .breakDue = e.phase else { expect(false, "\(e.phase)"); return }
        // snoozed
        (e, c, _) = makeEngine()
        e.start(); c.advance(1201); e.tick(); e.snooze(minutes: 5); e.preset = .pomodoro
        guard case .snoozed = e.phase else { expect(false, "\(e.phase)"); return }
        // onBreak keeps end
        (e, c, _) = makeEngine()
        e.start(); e.startBreak(); let before = e.phase; e.preset = .pomodoro
        expect(e.phase == before && e.completedBreaks == 0)
        c.advance(21); e.tick()
        expect(e.remaining == 1500)
    }
    check("settings normalise unknown id; custom edit changes preset") {
        let suite = "mochi.checks2"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set("bogus", forKey: "presetID")
        let s = MochiSettings(defaults: d)
        expect(s.presetID == "gentle")
        s.presetID = "custom"
        let old = s.preset
        s.customFocusMinutes += 5
        expect(s.preset != old)
        d.removePersistentDomain(forName: suite)
    }
    check("pause after clock passed end → breakDue; pause from breakDue no-op") {
        let (e, c, _) = makeEngine()
        e.start(); c.advance(1300); e.pause()
        guard case .breakDue = e.phase else { expect(false, "\(e.phase)"); return }
        e.pause()
        guard case .breakDue = e.phase else { expect(false, "\(e.phase)"); return }
    }
    check("snooze clamps to 1 minute") {
        let (e, c, _) = makeEngine()
        e.start(); c.advance(1201); e.tick()
        expect(e.snooze(minutes: 0))
        expect(e.remaining == 60, "\(e.remaining)")
    }
    check("currentTip stable during break, nil while focusing") {
        let (e, c, _) = makeEngine()
        e.start(); expect(e.currentTip == nil)
        c.advance(1201); e.tick()
        let tip = e.currentTip
        expect(tip != nil)
        e.snooze(minutes: 5); expect(e.currentTip == tip)
        c.advance(301); e.tick(); e.startBreak()
        for _ in 0..<10 { c.advance(1); e.tick(); expect(e.currentTip == tip) }
        c.advance(100); e.tick()
        expect(e.currentTip == nil)
    }
}

@MainActor private func runAdjustChecks() {
    check("adjust in focusing/onBreak/snoozed/paused") {
        let (e, c, _) = makeEngine()
        e.start()
        expect(e.adjust(by: 300) && e.remaining == 1500)
        e.pause(); expect(e.adjust(by: -60) && e.remaining == 1440)
        c.advance(30); e.resume(); expect(e.remaining == 1440)
        c.advance(1500); e.tick()
        e.snooze(minutes: 5)
        expect(e.adjust(by: 60) && e.remaining == 360)
        c.advance(361); e.tick(); e.startBreak()
        expect(e.adjust(by: 60) && e.remaining == 80, "\(e.remaining)")
    }
    check("adjust clamps to 10s…3h") {
        let (e, _, _) = makeEngine()
        e.start()
        e.adjust(by: -100_000); expect(e.remaining == 10, "\(e.remaining)")
        e.adjust(by: 1_000_000); expect(e.remaining == 10_800, "\(e.remaining)")
    }
    check("adjust no-op in idle/breakDue") {
        let (e, c, log) = makeEngine()
        expect(!e.adjust(by: 60))
        e.start(); c.advance(1201); e.tick()
        expect(!e.adjust(by: 60))
        guard case .breakDue = e.phase else { expect(false); return }
        expect(log.events == [.breakDue])
    }
    check("adjust keeps progress continuous & in range") {
        let (e, c, _) = makeEngine()
        e.start(); c.advance(600); e.tick()
        let before = e.progress
        e.adjust(by: 300)
        expect(abs(before * 1200 - e.progress * e.periodDuration) < 0.001, "elapsed preserved")
        expect(e.periodDuration == 1500)
        e.adjust(by: -100_000)
        expect(e.progress >= 0 && e.progress <= 1)
        e.adjust(by: 100_000)
        expect(e.progress >= 0 && e.progress <= 1)
    }
    check("adjust re-arms almostDone") {
        let (e, c, log) = makeEngine()
        e.start(); c.advance(1100); e.tick()
        expect(log.events == [.almostDone])
        e.adjust(by: 300)
        c.advance(300); e.tick()
        expect(log.events == [.almostDone, .almostDone], "\(log.events)")
        expect(!log.events.contains(.breakDue))
    }
    check("phaseStartedAt set on phase change only") {
        let (e, c, _) = makeEngine()
        e.start(); c.advance(10); e.tick(); e.adjust(by: 60)
        let t0 = e.phaseStartedAt
        c.advance(5); e.tick(); e.adjust(by: 60)
        expect(e.phaseStartedAt == t0)
        e.startBreak()
        expect(e.phaseStartedAt == c.date)
    }
}

@MainActor private func runStopChecks() {
    check("stop → idle, clears tip, fires breakEnded if on break") {
        let (e, c, log) = makeEngine()
        e.start(); e.stop()
        expect(e.phase == .idle && e.currentTip == nil && log.events.isEmpty)
        e.start(); c.advance(1201); e.tick(); e.startBreak(); e.stop()
        expect(e.phase == .idle && e.currentTip == nil)
        expect(log.events.filter { $0 == .breakEnded }.count == 1)
        expect(e.completedBreaks == 0 && e.progress == 0)
        c.advance(5000); e.tick()
        expect(e.phase == .idle)
    }
    check("autoStart persists, default false") {
        let suite = "mochi.checks3"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let s = MochiSettings(defaults: d)
        expect(!s.autoStart)
        s.autoStart = true
        expect(MochiSettings(defaults: d).autoStart)
        d.removePersistentDomain(forName: suite)
    }
}

@MainActor private func runM4ReviewChecks() {
    check("breakCompleted only on natural end") {
        let (e, c, log) = makeEngine()
        e.start(); e.startBreak(); e.skipBreak()
        e.startBreak(); e.reset()
        e.startBreak(); e.stop()
        expect(!log.events.contains(.breakCompleted), "\(log.events)")
        e.start(); e.startBreak(); c.advance(21); e.tick()
        expect(log.events.filter { $0 == .breakCompleted }.count == 1)
        expect(log.events.filter { $0 == .breakEnded }.count == 4)
    }
    check("adjust returns false if tick changed phase") {
        let (e, c, _) = makeEngine()
        e.start(); e.startBreak()
        c.advance(20.1)
        expect(!e.adjust(by: 300))
        guard case .focusing = e.phase else { expect(false, "\(e.phase)"); return }
        expect(e.remaining == 1200, "\(e.remaining)")
    }
    check("lower clamp never lengthens") {
        let (e, c, _) = makeEngine()
        e.start(); e.startBreak(); c.advance(15)
        e.adjust(by: -60)
        expect(abs(e.remaining - 5) < 0.001, "\(e.remaining)")
    }
    check("pause/resume keep phaseStartedAt") {
        let (e, c, _) = makeEngine()
        e.start(); let t0 = e.phaseStartedAt
        c.advance(10); e.pause(); c.advance(10); e.resume()
        expect(e.phaseStartedAt == t0)
        e.startBreak(); let t1 = e.phaseStartedAt
        c.advance(3); e.pause(); c.advance(3); e.resume()
        expect(e.phaseStartedAt == t1 && t1 != t0)
    }
}

@MainActor private func runAwayChecks() {
    check("AwayPolicy decisions") {
        let t: TimeInterval = 300
        let f = Phase.focusing(end: Date()), d = Phase.breakDue(since: Date(), snoozes: 0)
        expect(AwayPolicy.action(awayFor: 299, phase: f, threshold: t) == .none)
        expect(AwayPolicy.action(awayFor: 300, phase: f, threshold: t) == .naturalBreak)
        expect(AwayPolicy.action(awayFor: 900, phase: d, threshold: t) == .naturalBreak)
        expect(AwayPolicy.action(awayFor: 900, phase: .snoozed(end: Date(), snoozes: 1), threshold: t) == .naturalBreak)
        expect(AwayPolicy.action(awayFor: 900, phase: .onBreak(end: Date()), threshold: t) == .none)
        expect(AwayPolicy.action(awayFor: 900, phase: .idle, threshold: t) == .none)
        expect(AwayPolicy.action(awayFor: 900, phase: .paused(remaining: 5, resume: .focusing), threshold: t) == .none)
    }
    check("IdleTracker fires once per stretch, re-arms on activity") {
        var tr = IdleTracker()
        let f = Phase.focusing(end: Date())
        expect(tr.update(idleFor: 100, phase: f, threshold: 300) == .none)
        expect(tr.update(idleFor: 310, phase: f, threshold: 300) == .naturalBreak)
        expect(tr.update(idleFor: 330, phase: f, threshold: 300) == .none)
        expect(tr.update(idleFor: 2, phase: f, threshold: 300) == .none)
        expect(tr.update(idleFor: 305, phase: f, threshold: 300) == .naturalBreak)
        // resting: consumed, no action
        expect(tr.update(idleFor: 1, phase: f, threshold: 300) == .none)
        expect(tr.update(idleFor: 400, phase: .onBreak(end: Date()), threshold: 300) == .none)
        expect(tr.update(idleFor: 420, phase: f, threshold: 300) == .none)
    }
    check("AwayTracker lock/sleep/wake") {
        var tr = AwayTracker()
        let t0 = Date(timeIntervalSince1970: 0)
        tr.lock(at: t0)
        tr.sleep(at: t0.addingTimeInterval(10))
        expect(tr.wake(at: t0.addingTimeInterval(500)) == nil, "wake while locked ignored")
        expect(tr.unlock(at: t0.addingTimeInterval(600)) == 600)
        expect(tr.unlock(at: t0.addingTimeInterval(700)) == nil)
        tr.sleep(at: t0.addingTimeInterval(1000))
        expect(tr.wake(at: t0.addingTimeInterval(1100)) == 100)
    }
}
