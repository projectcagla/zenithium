//
//  PipelineIntegrationTests.swift
//  ZenithiumTests
//
//  Spec §11: a `MockHealthProvider` end-to-end pipeline test. No HealthKit, no device, no
//  authorization prompt — the mock and an in-memory store stand in for both.
//

import Testing
import Foundation
import SwiftData
@testable import Zenithium

@Suite("Pipeline")
struct PipelineIntegrationTests {

    private let now = iso("2025-06-15T19:30:00Z")

    private func makeStore() throws -> ZenithiumStore {
        let container = try ModelContainerFactory.makeInMemory()
        return ZenithiumStore(modelContainer: container)
    }

    private func makeCoordinator(
        configuration: MockHealthProvider.Configuration = .complete,
        store: ZenithiumStore
    ) -> DailyRecalculationCoordinator {
        DailyRecalculationCoordinator(
            health: MockHealthProvider(configuration: configuration),
            store: store,
            calendarProvider: { TestCalendars.utc }
        )
    }

    // MARK: - End to end

    @Test("A full pass produces a scored day and persists it")
    func endToEnd() async throws {
        let store = try makeStore()
        let coordinator = makeCoordinator(store: store)

        let result = try await coordinator.recalculate(now: now)

        // Recovery is scored: ninety days of complete mock history is well past the
        // fourteen-day threshold.
        #expect(result.recovery.availability.isScored)
        let score = try #require(result.recovery.score)
        #expect(score >= 1 && score <= 100)
        #expect(result.recovery.band != nil)

        let ceiling = try #require(result.recovery.targetStrainCeiling)
        #expect(ceiling > 0 && ceiling <= EngineConstants.Strain.scaleMax)

        // Sleep scored, strain computed, all sixteen groups projected.
        #expect(result.sleep.validity == .valid)
        #expect(result.sleep.score != nil)
        #expect(result.strain != nil)
        #expect(result.muscle.count == MuscleGroup.allCases.count)
        #expect(result.circadian != nil)

        // And it reached the store.
        let stored = try await store.dayRecord(for: result.dayStart)
        #expect(stored != nil)
        #expect(stored?.recoveryScore == result.recovery.score)
        #expect(stored?.engineVersion == EngineConstants.engineVersion)
    }

    @Test("Running the pipeline twice changes nothing")
    func isRerunnable() async throws {
        let store = try makeStore()
        let coordinator = makeCoordinator(store: store)

        let first = try await coordinator.recalculate(now: now)
        let second = try await coordinator.recalculate(now: now)

        // Idempotency is what makes a background pass safe to run alongside a foreground one:
        // baselines are rebuilt from the series each pass, so a day cannot fold in twice.
        expectClose(second.recovery.score ?? .nan, first.recovery.score ?? .nan, tolerance: 1e-9, "recovery")
        expectClose(second.sleep.score ?? .nan, first.sleep.score ?? .nan, tolerance: 1e-9, "sleep")
        expectClose(
            second.strain?.trimp ?? .nan,
            first.strain?.trimp ?? .nan,
            tolerance: 1e-6,
            "TRIMP"
        )

        let records = try await store.recentDayRecords(limit: 10)
        #expect(records.filter { $0.dayStart == first.dayStart }.count == 1)
    }

    @Test("Concurrent callers join one pass rather than starting two")
    func singleFlight() async throws {
        let store = try makeStore()
        let coordinator = makeCoordinator(store: store)

        async let first = coordinator.recalculate(now: now)
        async let second = coordinator.recalculate(now: now)
        let results = try await [first, second]

        #expect(results[0].dayStart == results[1].dayStart)
        expectClose(
            results[0].recovery.score ?? .nan,
            results[1].recovery.score ?? .nan,
            tolerance: 1e-12,
            "same pass"
        )
        let records = try await store.recentDayRecords(limit: 10)
        #expect(records.filter { $0.dayStart == results[0].dayStart }.count == 1)
    }

    // MARK: - §4.3 degraded sources

    @Test("A watch without wrist temperature still scores, with the term dropped")
    func withoutWristTemperature() async throws {
        let store = try makeStore()
        let coordinator = makeCoordinator(
            configuration: .withoutWristTemperature,
            store: store
        )

        let result = try await coordinator.recalculate(now: now)

        #expect(result.recovery.availability.isScored)
        #expect(result.recovery.missingDrivers.contains(.temperature))
        #expect(result.recovery.weightsWereRenormalized)
        expectClose(
            result.recovery.drivers.map(\.weight).reduce(0, +),
            1.0,
            tolerance: 1e-9,
            "weights still sum to one"
        )
        #expect(result.record.dataQuality == .partial)
        #expect(result.record.dataQualityReasons.contains(.wristTemperatureMissing))
    }

    @Test("A source without sleep stages drops Restorative and renormalizes")
    func withoutSleepStages() async throws {
        let store = try makeStore()
        let coordinator = makeCoordinator(configuration: .withoutSleepStages, store: store)

        let result = try await coordinator.recalculate(now: now)

        #expect(result.sleep.droppedComponents.contains(.restorative))
        expectClose(
            result.sleep.components.map(\.weight).reduce(0, +),
            1.0,
            tolerance: 1e-9,
            "weights still sum to one"
        )
        #expect(result.sleep.score != nil)
    }

    @Test("Denied authorization surfaces as a typed error, not a crash")
    func deniedAuthorization() async throws {
        let store = try makeStore()
        var configuration = MockHealthProvider.Configuration.complete
        configuration.authorizationState = .denied
        let coordinator = DailyRecalculationCoordinator(
            health: MockHealthProvider(configuration: configuration),
            store: store,
            calendarProvider: { TestCalendars.utc }
        )

        await #expect(throws: ZenithiumError.healthAuthorizationDenied) {
            _ = try await coordinator.recalculate(now: now)
        }
    }

    // MARK: - Store round trips

    @Test("A partial write leaves untouched fields alone (STORE-5)")
    func partialWritesPreserveFields() async throws {
        let store = try makeStore()
        let dayStart = TestCalendars.utc.startOfDay(for: now)

        var first = DayRecordWrite(
            dayStart: dayStart,
            timeZoneIdentifier: "UTC",
            computedAt: now,
            engineVersion: EngineConstants.engineVersion
        )
        first.recoveryScore = 72
        first.sleepScore = 84
        _ = try await store.upsertDayRecord(first)

        // An evening strain-only refresh must not clobber the morning's recovery score.
        var second = DayRecordWrite(
            dayStart: dayStart,
            timeZoneIdentifier: "UTC",
            computedAt: now.addingTimeInterval(3600),
            engineVersion: EngineConstants.engineVersion
        )
        second.dayStrain = 11.4
        let updated = try await store.upsertDayRecord(second)

        expectClose(updated.recoveryScore ?? .nan, 72, tolerance: 1e-9, "recovery preserved")
        expectClose(updated.sleepScore ?? .nan, 84, tolerance: 1e-9, "sleep preserved")
        expectClose(updated.dayStrain, 11.4, tolerance: 1e-9, "strain written")
    }

    @Test("Clearing overnight values removes the score they produced (§5.6)")
    func deletionClearsOvernightValues() async throws {
        let store = try makeStore()
        let dayStart = TestCalendars.utc.startOfDay(for: now)

        var first = DayRecordWrite(
            dayStart: dayStart,
            timeZoneIdentifier: "UTC",
            computedAt: now,
            engineVersion: EngineConstants.engineVersion
        )
        first.recoveryScore = 72
        first.heartRateVariability = 62
        first.dayStrain = 11.4
        _ = try await store.upsertDayRecord(first)

        var cleared = DayRecordWrite(
            dayStart: dayStart,
            timeZoneIdentifier: "UTC",
            computedAt: now.addingTimeInterval(60),
            engineVersion: EngineConstants.engineVersion,
            clearsOvernightValues: true
        )
        cleared.dayStrain = 11.4
        let updated = try await store.upsertDayRecord(cleared)

        #expect(updated.recoveryScore == nil)
        #expect(updated.heartRateVariability == nil)
        // Strain is a daytime measure and survives an overnight deletion.
        expectClose(updated.dayStrain, 11.4, tolerance: 1e-9, "strain retained")
    }

    @Test("The profile is created on first read and round-trips edits")
    func profileRoundTrip() async throws {
        let store = try makeStore()

        let initial = try await store.profile()
        #expect(!initial.hasCompletedOnboarding)
        expectClose(
            initial.baselineSleepNeedHours,
            EngineConstants.Sleep.defaultBaselineNeedHours,
            tolerance: 1e-9,
            "default need"
        )

        var write = UserProfileWrite()
        write.baselineSleepNeedHours = 8.5
        write.biologicalSex = .male
        write.hasCompletedOnboarding = true
        let updated = try await store.updateProfile(write)

        expectClose(updated.baselineSleepNeedHours, 8.5, tolerance: 1e-9, "need")
        #expect(updated.biologicalSex == .male)
        #expect(updated.hasCompletedOnboarding)

        // And there is still exactly one profile.
        let reread = try await store.profile()
        #expect(reread == updated)
    }

    @Test("Baselines round-trip through the store")
    func baselineRoundTrip() async throws {
        let store = try makeStore()
        let snapshot = BaselineSnapshot(
            metric: .heartRateVariability,
            mean: 55,
            variance: 64,
            sampleCount: 30,
            lastUpdated: now,
            seedValues: []
        )
        try await store.saveBaselines([.heartRateVariability: snapshot])

        let loaded = try await store.baselines()
        #expect(loaded[.heartRateVariability] == snapshot)

        try await store.resetBaselines()
        #expect(try await store.baselines().isEmpty)
    }

    // MARK: - Mock determinism (ASSUMPTION MOCK-1)

    @Test("The mock returns the same values however many times it is asked")
    func mockIsDeterministic() async throws {
        let provider = MockHealthProvider(configuration: .complete)
        let calendar = TestCalendars.utc

        let first = try await provider.fetchBaselineSeries(days: 30, now: now, calendar: calendar)
        let second = try await provider.fetchBaselineSeries(days: 30, now: now, calendar: calendar)
        #expect(first == second)

        let night = DateInterval(
            start: iso("2025-06-14T22:00:00Z"),
            end: iso("2025-06-15T08:00:00Z")
        )
        let overnightA = try await provider.fetchOvernightBiometrics(for: night, calendar: calendar)
        let overnightB = try await provider.fetchOvernightBiometrics(for: night, calendar: calendar)
        #expect(overnightA == overnightB)
    }

    @Test("Two providers with the same seed agree")
    func mockSeedsAreReproducible() async throws {
        let calendar = TestCalendars.utc
        let a = MockHealthProvider(seed: 42, configuration: .complete)
        let b = MockHealthProvider(seed: 42, configuration: .complete)
        let c = MockHealthProvider(seed: 43, configuration: .complete)

        let seriesA = try await a.fetchBaselineSeries(days: 20, now: now, calendar: calendar)
        let seriesB = try await b.fetchBaselineSeries(days: 20, now: now, calendar: calendar)
        let seriesC = try await c.fetchBaselineSeries(days: 20, now: now, calendar: calendar)

        #expect(seriesA == seriesB)
        #expect(seriesA != seriesC)
    }

    @Test("Intraday samples arrive sorted and plausible")
    func intradaySamplesAreWellFormed() async throws {
        let provider = MockHealthProvider(configuration: .complete)
        let interval = DateInterval(
            start: iso("2025-06-15T06:00:00Z"),
            end: iso("2025-06-15T20:00:00Z")
        )
        let samples = try await provider.fetchIntradayHeartRates(in: interval)

        #expect(!samples.isEmpty)
        #expect(samples == samples.sorted { $0.timestamp < $1.timestamp })
        for sample in samples {
            #expect(sample.isPlausible)
        }
    }

    // MARK: - Day windows

    @Test("A wake-anchored day survives a spring-forward transition")
    func dayWindowAcrossDST() {
        let resolver = DayWindowResolver(calendar: TestCalendars.newYork, boundary: .wakeAnchored)
        // 07:00 EST on 2025-03-08 is 12:00 UTC. The next 07:00 local is EDT, at 11:00 UTC —
        // twenty-three hours later in absolute time, because the clocks moved.
        let wake = iso("2025-03-08T12:00:00Z")
        let window = resolver.window(containing: wake.addingTimeInterval(3600), wakeTime: wake)

        #expect(window.start == wake)
        expectClose(window.duration, 23 * 3600, tolerance: 1, "spring-forward day is 23 hours")
        #expect(!window.usedFallbackAnchor)
    }

    @Test("An instant before wake belongs to the previous physiological day")
    func lateNightBelongsToYesterday() {
        let resolver = DayWindowResolver(calendar: TestCalendars.utc, boundary: .wakeAnchored)
        let wake = iso("2025-06-15T07:00:00Z")
        // 01:00 is the tail of yesterday, which is the whole point of the wake anchor.
        let window = resolver.window(containing: iso("2025-06-15T01:00:00Z"), wakeTime: wake)

        #expect(window.start == iso("2025-06-14T07:00:00Z"))
        #expect(window.dayStart == iso("2025-06-14T00:00:00Z"))
    }

    @Test("Without a wake time the day falls back to 04:00 and says so")
    func fallbackAnchor() {
        let resolver = DayWindowResolver(calendar: TestCalendars.utc, boundary: .wakeAnchored)
        let window = resolver.window(containing: iso("2025-06-15T10:00:00Z"), wakeTime: nil)

        #expect(window.start == iso("2025-06-15T04:00:00Z"))
        #expect(window.usedFallbackAnchor)
    }

    @Test("The midnight boundary is a plain calendar day")
    func midnightBoundary() {
        let resolver = DayWindowResolver(calendar: TestCalendars.utc, boundary: .midnight)
        let window = resolver.window(containing: iso("2025-06-15T10:00:00Z"), wakeTime: iso("2025-06-15T07:00:00Z"))

        #expect(window.start == iso("2025-06-15T00:00:00Z"))
        #expect(window.boundary == .midnight)
    }
}
