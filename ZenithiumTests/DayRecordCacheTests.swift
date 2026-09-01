//
//  DayRecordCacheTests.swift
//  ZenithiumTests
//
//  Yol haritası v4, A4 and A5 — one read per refresh, and no stale numbers to pay for it.
//
//  The interesting assertions here are counts, not timings: how many reads reached the store
//  for a sequence of windows a real refresh issues. A count is deterministic, and it moves in
//  an obvious direction if someone reintroduces a per-window read.
//

import Testing
import Foundation
@testable import Zenithium

/// A store that answers day-record reads and remembers how many it was asked for.
private actor CountingDayRepository: BiometricDayRepository {

    private let days: [BiometricDaySnapshot]
    private(set) var readCount = 0

    init(days: [BiometricDaySnapshot]) {
        self.days = days
    }

    func dayRecords(from start: Date, through end: Date) async throws -> [BiometricDaySnapshot] {
        readCount += 1
        return days
            .filter { $0.dayStart >= start && $0.dayStart <= end }
            .sorted { $0.dayStart < $1.dayStart }
    }

    func dayRecord(for dayStart: Date) async throws -> BiometricDaySnapshot? {
        readCount += 1
        return days.first { $0.dayStart == dayStart }
    }

    func recentDayRecords(limit: Int) async throws -> [BiometricDaySnapshot] {
        readCount += 1
        return Array(days.sorted { $0.dayStart > $1.dayStart }.prefix(limit))
    }

    func strainAnchor(for dayStart: Date) async throws -> StrainAnchor? { nil }

    @discardableResult
    func upsertDayRecord(_ write: DayRecordWrite) async throws -> BiometricDaySnapshot {
        guard let first = days.first else {
            throw ZenithiumError.persistenceWriteFailed(detail: "boş sahte depo")
        }
        return first
    }

    func dayRecordsNeedingBackfill(currentEngineVersion: Int) async throws -> [Date] { [] }
}

/// A gate a test can hold shut, so a store read can be observed while it is still running.
///
/// Reentrancy only shows up while an `await` is outstanding. Without something holding the
/// read open, the race the cache now closes cannot be staged at all — the read finishes
/// before a second caller ever arrives, and the test passes whether or not the fix is there.
private actor ReadGate {

    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

/// A counting store whose reads block on a gate until the test lets them finish.
private actor GatedDayRepository: BiometricDayRepository {

    private let days: [BiometricDaySnapshot]
    private let gate: ReadGate
    private(set) var readCount = 0

    init(days: [BiometricDaySnapshot], gate: ReadGate) {
        self.days = days
        self.gate = gate
    }

    func dayRecords(from start: Date, through end: Date) async throws -> [BiometricDaySnapshot] {
        readCount += 1
        await gate.wait()
        return days
            .filter { $0.dayStart >= start && $0.dayStart <= end }
            .sorted { $0.dayStart < $1.dayStart }
    }

    func dayRecord(for dayStart: Date) async throws -> BiometricDaySnapshot? {
        days.first { $0.dayStart == dayStart }
    }

    func recentDayRecords(limit: Int) async throws -> [BiometricDaySnapshot] {
        Array(days.sorted { $0.dayStart > $1.dayStart }.prefix(limit))
    }

    func strainAnchor(for dayStart: Date) async throws -> StrainAnchor? { nil }

    @discardableResult
    func upsertDayRecord(_ write: DayRecordWrite) async throws -> BiometricDaySnapshot {
        guard let first = days.first else {
            throw ZenithiumError.persistenceWriteFailed(detail: "boş sahte depo")
        }
        return first
    }

    func dayRecordsNeedingBackfill(currentEngineVersion: Int) async throws -> [Date] { [] }
}

@Suite("Day record cache")
struct DayRecordCacheTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func history(days count: Int) -> [BiometricDaySnapshot] {
        (0..<count).map { offset in
            snapshot(dayStart: calendar.startOfDay(for: now.addingTimeInterval(-Double(offset) * 86_400)))
        }
    }

    /// The windows one Today refresh asks for, in the order it asks for them: yesterday's
    /// comparison, then the correlations, then the load ratio.
    @Test("Bir yenileme geçişi depoya tek okuma gönderiyor")
    func oneRefreshIssuesOneRead() async throws {
        let upstream = CountingDayRepository(days: history(days: 200))
        let cache = DayRecordCache(upstream: upstream)

        for windowDays in [7.0, 90.0, 120.0] {
            _ = try await cache.dayRecords(
                from: now.addingTimeInterval(-windowDays * 86_400),
                through: now
            )
        }

        #expect(await upstream.readCount == 1)
        #expect(await cache.requestCount == 3)
        #expect(await cache.upstreamReadCount == 1)
    }

    /// The same three windows, started at once instead of one after another.
    ///
    /// This is how a Today refresh actually loads — several view models begin together — and
    /// it is the case an actor gets wrong for free: the window check and the store read are
    /// separated by an `await`, so without coalescing all three miss and all three read.
    @Test("Eşzamanlı üç istek depoya yine tek okuma gönderiyor")
    func concurrentRequestsJoinOneRead() async throws {
        let gate = ReadGate()
        let upstream = GatedDayRepository(days: history(days: 200), gate: gate)
        let cache = DayRecordCache(upstream: upstream)

        async let week = cache.dayRecords(from: now.addingTimeInterval(-7 * 86_400), through: now)
        async let quarter = cache.dayRecords(from: now.addingTimeInterval(-90 * 86_400), through: now)
        async let ratio = cache.dayRecords(from: now.addingTimeInterval(-120 * 86_400), through: now)

        // Wait for the two joiners to reach the join rather than sleeping for a guess. The
        // spin is bounded so a regression fails the test instead of hanging the suite.
        var spins = 0
        while await cache.coalescedReadCount < 2, spins < 100_000 {
            await Task.yield()
            spins += 1
        }
        #expect(await cache.coalescedReadCount == 2, "iki çağıran devam eden okumaya katılmadı")

        await gate.open()
        let results = try await [week, quarter, ratio]

        #expect(await upstream.readCount == 1)
        #expect(await cache.upstreamReadCount == 1)

        // Each caller still gets its own window, not the widened one the read used. Counts
        // are compared rather than pinned, because the day boundary the fixture builds from
        // depends on the running time zone.
        let windows = [7.0, 90.0, 120.0]
        for (result, windowDays) in zip(results, windows) {
            let earliest = now.addingTimeInterval(-windowDays * 86_400)
            #expect(result.count <= Int(windowDays) + 1)
            for day in result {
                #expect(day.dayStart >= earliest)
                #expect(day.dayStart <= now)
            }
        }
        #expect(results[0].count < results[1].count)
        #expect(results[1].count < results[2].count)
    }

    /// A write landing while a read is outstanding must not leave the pre-write answer
    /// installed as the cache's view afterwards.
    @Test("Okuma sürerken gelen geçersiz kılma, eski cevabı önbelleğe yerleştirmiyor")
    func invalidationDuringAReadIsNotOverwritten() async throws {
        let gate = ReadGate()
        let upstream = GatedDayRepository(days: history(days: 200), gate: gate)
        let cache = DayRecordCache(upstream: upstream)

        async let first = cache.dayRecords(from: now.addingTimeInterval(-7 * 86_400), through: now)

        var spins = 0
        while await upstream.readCount < 1, spins < 100_000 {
            await Task.yield()
            spins += 1
        }
        #expect(await upstream.readCount == 1, "okuma hiç başlamadı")

        // The recalculation pipeline rewrites a day while the read is still out.
        await cache.invalidate()
        await gate.open()
        _ = try await first

        // The next request must reach the store, because the window it would have hit was
        // read before the write.
        _ = try await cache.dayRecords(from: now.addingTimeInterval(-7 * 86_400), through: now)
        #expect(await upstream.readCount == 2, "geçersiz kılınan pencere yine de önbelleğe yazılmış")
    }

    @Test("İkinci ekran aynı pencereyi yeniden okumuyor")
    func asecondScreenReusesTheWindow() async throws {
        let upstream = CountingDayRepository(days: history(days: 200))
        let cache = DayRecordCache(upstream: upstream)

        // The training-load screen, then the strength screen a moment later. Their `now`
        // values differ by a few seconds, which is exactly the case an exact-window cache
        // would miss on.
        _ = try await cache.dayRecords(from: now.addingTimeInterval(-120 * 86_400), through: now)
        _ = try await cache.dayRecords(
            from: now.addingTimeInterval(3).addingTimeInterval(-120 * 86_400),
            through: now.addingTimeInterval(3)
        )

        #expect(await upstream.readCount == 1)
    }

    @Test("Dilim, çağıranın istediği pencereyle sınırlı")
    func sliceRespectsTheRequestedWindow() async throws {
        let upstream = CountingDayRepository(days: history(days: 200))
        let cache = DayRecordCache(upstream: upstream)

        _ = try await cache.dayRecords(from: now.addingTimeInterval(-120 * 86_400), through: now)
        let week = try await cache.dayRecords(from: now.addingTimeInterval(-7 * 86_400), through: now)

        #expect(week.count <= 8)
        for day in week {
            #expect(day.dayStart >= now.addingTimeInterval(-7 * 86_400))
            #expect(day.dayStart <= now)
        }
    }

    @Test("Önbellek, depoyla aynı sonucu döndürüyor")
    func matchesTheStoreExactly() async throws {
        let days = history(days: 200)
        let upstream = CountingDayRepository(days: days)
        let cache = DayRecordCache(upstream: upstream)

        for windowDays in [3.0, 30.0, 90.0, 150.0] {
            let start = now.addingTimeInterval(-windowDays * 86_400)
            let cached = try await cache.dayRecords(from: start, through: now)
            let direct = days
                .filter { $0.dayStart >= start && $0.dayStart <= now }
                .sorted { $0.dayStart < $1.dayStart }
            #expect(cached.map(\.dayStart) == direct.map(\.dayStart), "\(windowDays) günlük pencere")
        }
    }

    @Test("Geçersizleştirme sonrası depo yeniden okunuyor")
    func invalidationForcesAReread() async throws {
        let upstream = CountingDayRepository(days: history(days: 200))
        let cache = DayRecordCache(upstream: upstream)

        _ = try await cache.dayRecords(from: now.addingTimeInterval(-30 * 86_400), through: now)
        await cache.invalidate()
        _ = try await cache.dayRecords(from: now.addingTimeInterval(-30 * 86_400), through: now)

        #expect(await upstream.readCount == 2)
    }

    @Test("Daha eski bir pencere isteyen çağrı yeniden okuyor")
    func awiderWindowStillReaches() async throws {
        let upstream = CountingDayRepository(days: history(days: 400))
        let cache = DayRecordCache(upstream: upstream)

        _ = try await cache.dayRecords(from: now.addingTimeInterval(-30 * 86_400), through: now)
        let deep = try await cache.dayRecords(from: now.addingTimeInterval(-365 * 86_400), through: now)

        #expect(await upstream.readCount == 2)
        #expect(deep.count > 200)
    }

    private func snapshot(dayStart: Date) -> BiometricDaySnapshot {
        BiometricDaySnapshot(
            dayStart: dayStart,
            timeZoneIdentifier: "Europe/Istanbul",
            heartRateVariability: 60,
            restingHeartRate: 50,
            wristTemperatureDelta: nil,
            respiratoryRate: 14,
            oxygenSaturation: 97,
            recoveryScore: 70,
            recoveryConfidence: 1,
            recoveryZTotal: 0,
            dayStrain: 8,
            targetCeiling: 14,
            trimp: 60,
            zoneSeconds: [],
            maxHeartRateUsed: 190,
            sleepDurationSeconds: 8 * 3600,
            sleepScore: 80,
            sleepEfficiency: 0.9,
            deepSeconds: 4_000,
            remSeconds: 5_000,
            coreSeconds: 16_000,
            awakeSeconds: 1_000,
            timeInBedSeconds: 8.5 * 3600,
            sleepMidpointMinutes: 200,
            sleepStart: nil,
            wakeTime: nil,
            napSeconds: 0,
            dataQuality: .good,
            dataQualityReasons: [],
            computedAt: dayStart,
            engineVersion: 1
        )
    }
}
