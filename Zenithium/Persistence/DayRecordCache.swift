//
//  DayRecordCache.swift
//  Zenithium
//
//  A caching front for the day-record store. Yol haritası v4, A4 and A5.
//
//  ## What it fixes
//
//  Nine view models read `dayRecords(from:through:)`, and they read it repeatedly. A single
//  Today refresh issued four of them — 120 days for the load ratio, seven for yesterday's
//  comparison, the cycle history window, and ninety for the correlations — over windows that
//  all sit inside the widest one. Separately, the strength screen read 120 days purely to
//  learn the load ratio the training-load screen had already read a moment earlier.
//
//  So this sits between the view models and the store, keeps the widest window it has been
//  asked for, and serves anything inside it by slicing. The store sees one read instead of
//  four, and moving between two screens does not re-read the same three months.
//
//  ## Why it cannot go stale
//
//  Day records change in exactly one place: the recalculation pipeline. `AppDependencies`
//  drains that pipeline's result stream and invalidates on every pass, and writes made
//  through this type invalidate it directly. There is no timeout involved, so there is no
//  window in which the app knowingly shows an old number — the cache is either current or
//  empty.
//
//  ## Why an actor
//
//  It holds mutable state read from many isolation domains, and §2.4 rules out a lock. The
//  reads it guards are already `async`, so the hop costs nothing that was not already paid.
//
//  ## Reentrancy
//
//  An actor releases its executor at every `await`, so "check the window, then read the
//  store" is not atomic here: a second caller arriving during the store read sees the same
//  empty window and issues its own. Sequentially the cache turned four reads into one;
//  concurrently — which is how a Today refresh actually loads, several view models starting
//  at once — it turned four into four, and the counter said one because each caller was
//  counted before the race.
//
//  So a miss publishes the read it starts. A caller whose window fits inside a read already
//  in flight joins that read instead of starting another. `Task` caches its value, so every
//  joiner gets the same array and the store still sees one query.
//
//  Invalidation carries a generation counter for the same reason: a read that began before a
//  write must not install its pre-write answer as the cache's view of the world afterwards.
//  It still returns what it read — a read racing a write is inherently one pass behind, and
//  that was true before this type existed — but it does not persist it.
//

import Foundation

/// Serves day-record reads from the widest window it has already fetched.
actor DayRecordCache: BiometricDayRepository {

    private let upstream: any BiometricDayRepository

    /// The widest window read since the last invalidation, and what was in it.
    private var window: (start: Date, end: Date, days: [BiometricDaySnapshot])?

    /// How many reads have reached the store. Counted so the regression suite can assert
    /// that one refresh pass issues one read, rather than timing the pass. Yol haritası v4, A9.
    private(set) var upstreamReadCount = 0

    /// How many reads have been asked for, whether or not they reached the store.
    private(set) var requestCount = 0

    /// How many reads joined a store read that was already running, rather than starting one.
    ///
    /// Counted separately from `upstreamReadCount` so the regression suite can tell the two
    /// ways of not reading the store apart: a window hit, and a join. Yol haritası v4, A9.
    private(set) var coalescedReadCount = 0

    /// The store read currently running, and the window it was asked for.
    private var inFlight: (start: Date, end: Date, task: Task<[BiometricDaySnapshot], any Error>)?

    /// Bumped by every invalidation. A read that started under an older generation may not
    /// install its result.
    private var generation = 0

    /// How far back a miss reads, however little was asked for.
    ///
    /// Every caller's window is a suffix of the same history: seven days for yesterday's
    /// comparison, ninety for the correlations, a hundred and twenty for the load ratio. Read
    /// exactly what was asked and a refresh pays for three reads, because each request is
    /// wider than the one cached before it. Read a set floor instead and the first request
    /// covers the rest.
    ///
    /// Set just above the widest of the everyday windows rather than above the widest window
    /// in the app: the longevity composite wants a year and the cycle history four hundred
    /// days, and pre-reading that much for a screen that asked for a week would trade one
    /// problem for another. Those two widen the cache when they run, and everything narrower
    /// then rides along.
    private static let minimumHistoryDays: Double = 150

    /// How far past the requested end a miss reads.
    ///
    /// Callers pass their own `Date()` as the end, so two requests moments apart do not have
    /// the same end and an exact window would miss on the second one every time. A day of
    /// slack absorbs that. Over-reading forward is safe because a slice is always bounded by
    /// what the caller asked for, and because no record exists for a day that has not
    /// started yet.
    private static let forwardSlackDays: Double = 1

    init(upstream: any BiometricDayRepository) {
        self.upstream = upstream
    }

    /// Drop everything cached. Called whenever a recalculation pass rewrites a day.
    ///
    /// A read already in flight is disowned rather than cancelled: its caller is still
    /// waiting for an answer and cancelling would fail that caller for a reason that has
    /// nothing to do with it. The generation bump is what stops the answer being installed.
    func invalidate() {
        window = nil
        inFlight = nil
        generation &+= 1
    }

    // MARK: - BiometricDayRepository

    func dayRecords(from start: Date, through end: Date) async throws -> [BiometricDaySnapshot] {
        requestCount += 1

        if let window, window.start <= start, window.end >= end {
            return slice(window.days, from: start, through: end)
        }

        // A read already running that covers this request answers it. Reached before the
        // widening below because joining is unconditionally better than starting a second
        // query for a window somebody is already fetching.
        if let inFlight, inFlight.start <= start, inFlight.end >= end {
            coalescedReadCount += 1
            let days = try await inFlight.task.value
            return slice(days, from: start, through: end)
        }

        // Widen rather than replace. A narrow request arriving after a wide one would
        // otherwise shrink the cache and make the *next* wide request miss — which is the
        // exact sequence a Today refresh performs.
        let widenedEnd = max(end, window?.end ?? end, inFlight?.end ?? end)
            .addingTimeInterval(Self.forwardSlackDays * 86_400)
        let floor = widenedEnd.addingTimeInterval(-Self.minimumHistoryDays * 86_400)
        let widenedStart = min(start, window?.start ?? start, inFlight?.start ?? start, floor)

        let readGeneration = generation
        let upstream = self.upstream
        let task = Task<[BiometricDaySnapshot], any Error> {
            try await upstream.dayRecords(from: widenedStart, through: widenedEnd)
        }
        inFlight = (widenedStart, widenedEnd, task)

        let days: [BiometricDaySnapshot]
        do {
            days = try await task.value
        } catch {
            if inFlight?.task == task { inFlight = nil }
            throw error
        }

        upstreamReadCount += 1
        if inFlight?.task == task { inFlight = nil }

        // Installing a pre-write answer after a write is how a cache goes stale without a
        // timeout to blame. The caller still gets what the store said.
        if readGeneration == generation {
            adopt(days, start: widenedStart, end: widenedEnd)
        }
        return slice(days, from: start, through: end)
    }

    /// Stores a completed read, unless what is already stored covers strictly more.
    ///
    /// Two reads can be in flight when the second one's window did not fit inside the
    /// first's. Whichever lands second must not narrow the cache.
    private func adopt(_ days: [BiometricDaySnapshot], start: Date, end: Date) {
        if let window, window.start <= start, window.end >= end { return }
        window = (start, end, days)
    }

    func dayRecord(for dayStart: Date) async throws -> BiometricDaySnapshot? {
        if let window, window.start <= dayStart, window.end >= dayStart {
            return window.days.first { $0.dayStart == dayStart }
        }
        return try await upstream.dayRecord(for: dayStart)
    }

    func recentDayRecords(limit: Int) async throws -> [BiometricDaySnapshot] {
        // Deliberately not served from the window: "the most recent n" is unanswerable from
        // a date range without knowing whether the range reaches the newest record.
        try await upstream.recentDayRecords(limit: limit)
    }

    func strainAnchor(for dayStart: Date) async throws -> StrainAnchor? {
        try await upstream.strainAnchor(for: dayStart)
    }

    @discardableResult
    func upsertDayRecord(_ write: DayRecordWrite) async throws -> BiometricDaySnapshot {
        defer { invalidate() }
        return try await upstream.upsertDayRecord(write)
    }

    func dayRecordsNeedingBackfill(currentEngineVersion: Int) async throws -> [Date] {
        try await upstream.dayRecordsNeedingBackfill(currentEngineVersion: currentEngineVersion)
    }

    // MARK: - Slicing

    /// The same bounds the store applies: inclusive at both ends, ascending by day.
    private func slice(
        _ days: [BiometricDaySnapshot],
        from start: Date,
        through end: Date
    ) -> [BiometricDaySnapshot] {
        days.filter { $0.dayStart >= start && $0.dayStart <= end }
    }
}
