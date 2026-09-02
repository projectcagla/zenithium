//
//  HealthDataProviding.swift
//  Zenithium
//
//  The only Health surface any other layer sees. Spec §8.
//
//  ASSUMPTION API-7: every requirement is `async`, and the read methods take the `Calendar`
//  they should bucket in. The specification lists some of these as synchronous and without a
//  calendar; an actor cannot witness a synchronous requirement without going `nonisolated`,
//  and §2.7 forbids a date computation that does not go through an injected calendar. The
//  shapes are otherwise exactly as specified.
//

import Foundation

/// The authorization subset, which is all a view model's permission gate needs.
///
/// Declared here rather than in `ViewModels` so that `HealthDataProviding` can inherit it:
/// a view model depending on `Health` is a downward arrow, the reverse would not be.
protocol HealthAuthorizing: Sendable {

    /// Whether health data exists on this device at all.
    func isHealthDataAvailable() async -> Bool

    /// Presents the system authorization sheet for Zenithium's read types.
    func requestAuthorization() async throws

    /// The current authorization picture (§5.6 — denial is a recoverable state, never a crash).
    func authorizationReport(now: Date) async -> HealthAuthorizationReport
}

/// The vital-sign read surface. Faz 11.
///
/// Split from `HealthDataProviding` on purpose. That protocol is the recovery pipeline's
/// contract and every method on it is load-bearing for a score; this one is a read for a
/// screen. Keeping them apart means the vitals screen can be given exactly what it needs,
/// and a future data source can implement one without the other.
protocol VitalsProviding: Sendable {

    /// Daily values for one vital sign across a window, oldest first, gaps absent.
    ///
    /// Gaps are absent rather than zero-filled for the same reason §4.2.5 forbids
    /// interpolating biometrics: a day the watch was not worn is unknown, and a zero would
    /// be read as a measurement.
    func fetchVitalSamples(
        sign: VitalSign,
        days: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> [VitalSample]

    /// Logged bleeding days across a window, oldest first. Faz 12.
    ///
    /// Read only when the user has turned cycle awareness on. Nothing else in Zenithium
    /// touches this data, and it never leaves the device — the same as everything else, but
    /// worth stating for a category people are right to be careful about.
    func fetchMenstrualFlowDays(
        days: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> [MenstrualFlowDay]
}

/// Everything Zenithium can ask of a health data source.
///
/// Nothing in this protocol mentions HealthKit. `HealthKitService` is one implementation;
/// `MockHealthProvider` is the other, and it is what the engines and tests are written
/// against so that no test needs a device, a watch, or an authorization prompt.
protocol HealthDataProviding: HealthAuthorizing, VitalsProviding {

    /// Date of birth and biological sex, for the Tanaka estimate and the TRIMP constants (§5.3).
    func fetchCharacteristics() async throws -> UserCharacteristics

    /// Daily aggregates for every baselined metric across the trailing `days`.
    ///
    /// The returned series excludes today, because a value is always scored against the
    /// baseline as of yesterday (§4.2.1). Days with no data are absent rather than zero —
    /// §4.2.5 forbids interpolating biometrics.
    func fetchBaselineSeries(days: Int, now: Date, calendar: Calendar) async throws -> BaselineSeries

    /// Everything recorded across one night, plus the surrounding day's naps (§5.2).
    func fetchOvernightBiometrics(
        for night: DateInterval,
        calendar: Calendar,
        previousWakeTime: Date?
    ) async throws -> OvernightData

    /// The intraday heart-rate series for an interval, already downsampled to at most one
    /// sample every 5 seconds (§8) and sorted ascending by timestamp.
    func fetchIntradayHeartRates(in interval: DateInterval) async throws -> [HeartRateSample]

    /// Workouts overlapping an interval, as `Sendable` summaries — never `HKWorkout` (§8).
    func fetchWorkouts(in interval: DateInterval) async throws -> [WorkoutSummary]

    /// The observed maximum heart rate over the trailing window, as the 99.5th percentile of
    /// daily maxima (ASSUMPTION HRMAX-2). `nil` when there is no heart-rate history.
    func fetchObservedMaxHeartRate(
        lookbackDays: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> Double?

    /// Registers observer queries and asks HealthKit to wake the app on change (§8).
    func enableBackgroundDelivery() async throws

    /// A stream of change events, one per observed category batch.
    ///
    /// Calling this more than once replaces the previous stream; there is a single
    /// consumer — `Orchestration/HealthObservationRelay.swift` (ASSUMPTION BG-2).
    func observationStream() async -> AsyncStream<HealthChangeEvent>

    /// Apple Watch ECG recordings across a window, oldest first. Faz 33.
    func fetchECGRecords(days: Int, now: Date) async throws -> [ECGRecord]

    /// Stops observation and tears down every running query. Idempotent.
    func stopObserving() async
}

extension HealthDataProviding {
    func fetchOvernightBiometrics(
        for night: DateInterval,
        calendar: Calendar
    ) async throws -> OvernightData {
        try await fetchOvernightBiometrics(for: night, calendar: calendar, previousWakeTime: nil)
    }

    func fetchECGRecords(days: Int, now: Date) async throws -> [ECGRecord] {
        []
    }
}
