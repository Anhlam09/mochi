import Foundation
import Observation
import Darwin

/// Pure list logic shared by the store, the agent and the checks.
public enum TodoList {
    /// Items with day <= today that are not done (carried-over first, then timed by time, then the
    /// rest by creation), followed by the items finished today (by completion time).
    public static func today(_ items: [TodoItem], now: Date, calendar: Calendar = .autoupdatingCurrent) -> [TodoItem] {
        let start = calendar.startOfDay(for: now)
        let open = items.filter { !$0.done && $0.day <= start }
        let carried = open.filter { $0.day < start }
            .sorted { ($0.day, $0.createdAt) < ($1.day, $1.createdAt) }
        let timed = open.filter { $0.day >= start && $0.time != nil }
            .sorted { ($0.time!, $0.createdAt) < ($1.time!, $1.createdAt) }
        let rest = open.filter { $0.day >= start && $0.time == nil }
            .sorted { $0.createdAt < $1.createdAt }
        let done = items.filter { $0.done && calendar.isDate($0.doneAt ?? $0.day, inSameDayAs: now) }
            .sorted { ($0.doneAt ?? $0.day) < ($1.doneAt ?? $1.day) }
        return carried + timed + rest + done
    }

    /// Unfinished items for later days (day > today): by day, then timed items by time, then the rest.
    public static func later(_ items: [TodoItem], now: Date, calendar: Calendar = .autoupdatingCurrent) -> [TodoItem] {
        let start = calendar.startOfDay(for: now)
        return items.filter { !$0.done && $0.day > start }.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            switch ($0.time, $1.time) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.createdAt < $1.createdAt
            }
        }
    }

    /// "Fri" for a day within the next 6 days, otherwise "Oct 24".
    public static func dayLabel(_ day: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: day)).day ?? 0
        f.dateFormat = days <= 6 ? "EEE" : "MMM d"
        return f.string(from: day)
    }

    public static func counts(_ items: [TodoItem], now: Date, calendar: Calendar = .autoupdatingCurrent) -> (done: Int, left: Int) {
        let list = today(items, now: now, calendar: calendar)
        let done = list.filter(\.done).count
        return (done, list.count - done)
    }
}

/// The to-do list, kept only in one local file (default `~/Library/Application Support/Mochi/todos.json`,
/// folder 0700, file 0600). Nothing here touches the network, and titles are never logged.
@MainActor @Observable
public final class TodoStore {
    public private(set) var items: [TodoItem] = []
    /// True if the last write failed (the list stays in memory).
    public private(set) var saveFailed = false
    /// Set when an unreadable file was moved aside at launch.
    public private(set) var recoveredBackupURL: URL?

    @ObservationIgnored public let fileURL: URL
    @ObservationIgnored private let calendar: Calendar
    /// Newest file format this build understands; anything newer is backed up, never overwritten.
    public static let supportedVersion = 1
    /// When the existing file could neither be read nor moved aside, never overwrite it.
    @ObservationIgnored private var writeBlocked = false

    public static let pruneAfterDays = 30

    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mochi/todos.json")
    }

    public init(fileURL: URL = TodoStore.defaultFileURL, calendar: Calendar = .autoupdatingCurrent, now: Date = Date()) {
        self.fileURL = fileURL
        self.calendar = calendar
        load(now: now)
    }

    // MARK: Queries

    public func todayList(now: Date) -> [TodoItem] { TodoList.today(items, now: now, calendar: calendar) }
    public func counts(now: Date) -> (done: Int, left: Int) { TodoList.counts(items, now: now, calendar: calendar) }
    /// Unfinished items for days after today.
    public func laterList(now: Date) -> [TodoItem] { TodoList.later(items, now: now, calendar: calendar) }

    // MARK: Mutations

    @discardableResult
    public func add(_ text: String, now: Date) -> TodoItem? {
        guard let p = TodoParser.parse(text, now: now, calendar: calendar) else { return nil }
        let item = TodoItem(title: p.title, day: p.day, time: p.time, createdAt: now)
        items.append(item)
        save()
        return item
    }

    public func toggle(id: UUID, now: Date) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].done.toggle()
        items[i].doneAt = items[i].done ? now : nil
        save()
    }

    public func delete(id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    public func rename(id: UUID, title: String) {
        let t = TodoParser.cap(title.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        guard !t.isEmpty, let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].title = t
        save()
    }

    /// Moves unfinished items to tomorrow; a time of day is kept (on tomorrow's date).
    public func moveToTomorrow(ids: Set<UUID>, now: Date) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        var changed = false
        for i in items.indices where ids.contains(items[i].id) && !items[i].done {
            items[i].day = tomorrow
            if let t = items[i].time {
                let c = calendar.dateComponents([.hour, .minute], from: t)
                items[i].time = calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: tomorrow)
            }
            changed = true
        }
        if changed { save() }
    }

    /// Everything unfinished that is due today or earlier goes to tomorrow. Returns how many moved.
    @discardableResult
    public func moveUnfinishedToTomorrow(now: Date) -> Int {
        let ids = Set(todayList(now: now).filter { !$0.done }.map(\.id))
        moveToTomorrow(ids: ids, now: now)
        return ids.count
    }

    // MARK: Persistence

    private struct Envelope: Codable { var version = 1; var items: [TodoItem] }

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func load(now: Date) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        let data: Data
        do { data = try Data(contentsOf: fileURL) } catch { writeBlocked = true; saveFailed = true; return }
        do {
            let env = try Self.makeDecoder().decode(Envelope.self, from: data)
            guard env.version <= Self.supportedVersion else { throw CocoaError(.fileReadCorruptFile) }
            items = env.items
        } catch {
            quarantineFile(now: now)
            return
        }
        pruneOldDone(now: now)
    }

    /// Drops done items older than 30 days. Does nothing while writes are blocked (it could not be saved).
    public func pruneOldDone(now: Date) {
        guard !writeBlocked else { return }
        let cutoff = calendar.date(byAdding: .day, value: -Self.pruneAfterDays, to: calendar.startOfDay(for: now))!
        let kept = items.filter { !($0.done && ($0.doneAt ?? $0.day) < cutoff) }
        if kept.count != items.count { items = kept; save() }
    }

    /// Tries again after a failed write (the coordinator calls this now and then).
    public func retrySaveIfNeeded() {
        if saveFailed, !writeBlocked { save() }
    }

    /// Moves an unreadable file to `todos.corrupt-<timestamp>.json` so nothing is silently lost.
    private func quarantineFile(now: Date) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let dir = fileURL.deletingLastPathComponent()
        var target = dir.appendingPathComponent("todos.corrupt-\(f.string(from: now)).json")
        var n = 1
        while FileManager.default.fileExists(atPath: target.path) {
            n += 1
            target = dir.appendingPathComponent("todos.corrupt-\(f.string(from: now))-\(n).json")
        }
        do {
            try FileManager.default.moveItem(at: fileURL, to: target)
            recoveredBackupURL = target
        } catch {
            writeBlocked = true
            saveFailed = true
        }
    }

    private func save() {
        guard !writeBlocked else { saveFailed = true; return }
        do {
            let data = try Self.makeEncoder().encode(Envelope(items: items))
            let fm = FileManager.default
            let dir = fileURL.deletingLastPathComponent()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            // Write a private temp file, then rename over the real one (atomic).
            let tmp = dir.appendingPathComponent(".todos.json.tmp")
            try? fm.removeItem(at: tmp)
            guard fm.createFile(atPath: tmp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: tmp)
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()   // on disk before it replaces the old file
                try handle.close()
            } catch {
                try? handle.close()
                try? fm.removeItem(at: tmp)
                throw error
            }
            guard Darwin.rename(tmp.path, fileURL.path) == 0 else {
                try? fm.removeItem(at: tmp)
                throw CocoaError(.fileWriteUnknown)
            }
            saveFailed = false
        } catch {
            saveFailed = true
        }
    }
}
