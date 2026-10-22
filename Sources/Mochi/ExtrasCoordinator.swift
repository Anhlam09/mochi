import CoreGraphics
import Foundation
import MochiCore

/// Mochi's little extras: a good-night line, lunch and dinner ideas, and gentle self-care nudges.
/// `MochiCore` decides WHEN (pure, checked); this only shows the lines, one per tick, and only when
/// Mochi is visible, the user is here and nothing else is being said. Only ids and dates are saved.
@MainActor
final class ExtrasCoordinator {
    private let engine: TimerEngine
    private let settings: MochiSettings
    private let companion: Companion
    private let defaults: UserDefaults
    private var loopTask: Task<Void, Never>?
    private var mealMemory: MealMemory
    private var nightRotor = LineRotor(memory: 3)
    private var careRotor = LineRotor(memory: 3)
    private var lastCare = Date()   // the first nudge comes one interval after launch

    private static let nightKey = "goodNightLastNight"
    private static let mealKey = "mealMemory"

    init(engine: TimerEngine, settings: MochiSettings, companion: Companion, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.settings = settings
        self.companion = companion
        self.defaults = defaults
        mealMemory = defaults.data(forKey: Self.mealKey).flatMap { try? JSONDecoder().decode(MealMemory.self, from: $0) } ?? MealMemory()
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            while !Task.isCancelled {
                self?.tick(Date())
                try? await Task.sleep(for: .seconds(45), tolerance: .seconds(15))
            }
        }
    }

    private func tick(_ now: Date) {
        guard settings.showMascot, settings.chat != .off, companion.isQuiet else { return }
        let away = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            >= Companion.awayAfter
        let active = !away
        let phase = engine.phase

        // 1. Good night, 2. a meal idea, 3. self-care.
        if settings.goodNight,
           GoodNight.isDue(now: now, hour: settings.goodNightHour, lastNight: defaults.object(forKey: Self.nightKey) as? Date,
                           userActive: active, phase: phase) {
            let line = GoodNight.lines[nightRotor.next(count: GoodNight.lines.count)]
            if companion.sayExtra(line) { defaults.set(GoodNight.key(now), forKey: Self.nightKey) }
            return
        }
        if let meal = MealPolicy.due(now: now, mode: settings.mealMode, memory: mealMemory, userActive: active, phase: phase),
           let idea = MealPolicy.pick(meal, mode: settings.mealMode, memory: mealMemory, now: now) {
            if companion.sayExtra(idea.line) {
                MealPolicy.commit(idea, to: &mealMemory, now: now)
                if let data = try? JSONEncoder().encode(mealMemory) { defaults.set(data, forKey: Self.mealKey) }
            }
            return
        }
        if SelfCare.isDue(now: now, minutes: settings.selfCareMinutes, lastNudge: lastCare, lastOtherLine: companion.lastLineAt,
                          userActive: active, phase: phase) {
            let line = SelfCare.lines[careRotor.next(count: SelfCare.lines.count)]
            if companion.sayExtra(line) { lastCare = now }
        }
    }
}
