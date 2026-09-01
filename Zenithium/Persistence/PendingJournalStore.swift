//
//  PendingJournalStore.swift
//  Zenithium
//
//  The widget's outbox. Faz 22.
//
//  ## The problem this exists to avoid
//
//  A widget extension cannot open the SwiftData store. The app may already hold it, and two
//  processes writing one container is how a database gets corrupted — not usually, but
//  eventually, and unrecoverably.
//
//  So the widget never touches SwiftData. It appends to a small JSON file in the App Group,
//  and the app drains that file into the store on its next foreground. The widget is
//  append-only; the app is the single owner of the real data.
//
//  ## Why the file is written whole rather than appended to
//
//  Two taps in quick succession would interleave a true append. The file is tiny — at most
//  twelve booleans and a date — so it is read, modified and rewritten atomically each time.
//  Correctness at this size costs nothing.
//

import Foundation

/// One day's pending behaviours, as written by the widget.
struct PendingJournalDay: Codable, Sendable, Equatable {

    /// Local start of the day the entries belong to.
    let dayStart: Date

    /// `JournalBehavior.rawValue` for each logged behaviour.
    var behaviorRawValues: [String]

    var behaviors: Set<JournalBehavior> {
        Set(behaviorRawValues.compactMap(JournalBehavior.init(rawValue:)))
    }
}

enum PendingJournalStore {

    /// Where the outbox lives.
    static var url: URL? {
        AppGroup.containerURL?.appendingPathComponent("pending-journal.json")
    }

    /// Today's pending behaviours, or an empty set.
    static func loggedToday(now: Date = Date(), calendar: Calendar = .current) -> Set<JournalBehavior> {
        guard let day = read(), calendar.isDate(day.dayStart, inSameDayAs: now) else { return [] }
        return day.behaviors
    }

    /// Toggle one behaviour for today.
    ///
    /// A toggle rather than an add: the widget's chips show state, so tapping a lit one has
    /// to turn it off or the control is lying about what it does.
    static func toggle(_ behavior: JournalBehavior, now: Date = Date(), calendar: Calendar = .current) {
        let dayStart = calendar.startOfDay(for: now)
        var day = read().flatMap { calendar.isDate($0.dayStart, inSameDayAs: now) ? $0 : nil }
            ?? PendingJournalDay(dayStart: dayStart, behaviorRawValues: [])

        if let index = day.behaviorRawValues.firstIndex(of: behavior.rawValue) {
            day.behaviorRawValues.remove(at: index)
        } else {
            day.behaviorRawValues.append(behavior.rawValue)
        }
        write(day)
    }

    /// Take the pending day and clear the file.
    ///
    /// Called by the app on foreground. Clearing on read means a crash between draining and
    /// saving loses at most one day's taps — the alternative, clearing after the save,
    /// risks writing the same entries twice, and a duplicated behaviour would quietly skew
    /// a correlation.
    static func drain() -> PendingJournalDay? {
        defer { clear() }
        return read()
    }

    static func read() -> PendingJournalDay? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PendingJournalDay.self, from: data)
    }

    private static func write(_ day: PendingJournalDay) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(day) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private static func clear() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
