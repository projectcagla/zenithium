//
//  HealthKitService.swift
//  Zenithium
//
//  The HealthKit actor. Spec §8.
//
//  Concurrency contract, enforced by construction:
//  · Every HealthKit object is mapped to a `Sendable` DTO inside the query callback, before
//    anything is returned. No `HKSample`, `HKWorkout` or `HKQueryAnchor` ever crosses an
//    isolation boundary.
//  · Every continuation resumes exactly once. Resumption ownership is claimed on the actor,
//    so the completion path and the cancellation path cannot both resume.
//  · Cancelling the surrounding task stops the underlying `HKQuery`.
//

import Foundation
import HealthKit

/// The result of one anchored change-detection pass, reduced to `Sendable` values.
private struct AnchoredChangeResult: Sendable {
    let addedCount: Int
    let deletedCount: Int
    let anchorData: Data?

    var hasChanges: Bool { addedCount > 0 || deletedCount > 0 }
}

/// Reads HealthKit on behalf of the rest of the app.
actor HealthKitService: HealthDataProviding {

    // MARK: - State

    private let store = HKHealthStore()
    private let anchorStore: HealthKitAnchorStore

    /// Running one-shot queries, so cancellation can stop them.
    private var activeQueries: [UUID: HKQuery] = [:]

    /// Resumption ownership per running query. Whoever removes the entry owns the resume,
    /// which is what makes double-resumption impossible.
    private var pendingResumptions: [UUID: @Sendable () -> Void] = [:]

    /// Queries whose cancellation arrived before their continuation was registered.
    ///
    /// `withTaskCancellationHandler` runs `onCancel` the moment the task is cancelled, which
    /// can be before the continuation body has run — the body is what registers the
    /// resumption. `cancelQuery` then found nothing to resume, the body registered a
    /// resumption nobody would ever call, and the await never returned. A cancelled read is
    /// supposed to fail fast; instead it hung for the life of the process.
    ///
    /// So cancellation leaves a mark, and registration checks for it.
    private var cancelledBeforeRegistration: Set<UUID> = []

    /// Query identifiers whose `runQuery` call has not returned yet.
    ///
    /// `onCancel` hands its work to an unstructured `Task`, which can run after the query it
    /// refers to has already finished. Without this set that late arrival would leave a mark
    /// nobody ever clears, and the set would grow for the life of the process.
    private var liveQueryIDs: Set<UUID> = []

    /// Long-lived observer queries.
    private var observerQueries: [HKObserverQuery] = []

    /// The single change-stream consumer (ASSUMPTION BG-2).
    private var streamContinuation: AsyncStream<HealthChangeEvent>.Continuation?

    private var backgroundDeliveryEnabled = false

    init(anchorStore: HealthKitAnchorStore = HealthKitAnchorStore()) {
        self.anchorStore = anchorStore
    }

    // MARK: - Availability and authorization

    func isHealthDataAvailable() async -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ZenithiumError.healthDataUnavailable
        }
        let readTypes = HealthKitTypeCatalog.readTypes
        let store = self.store
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            store.requestAuthorization(toShare: Set<HKSampleType>(), read: readTypes) { success, error in
                if let error {
                    continuation.resume(throwing: Self.mapError(error, kind: .sleepAnalysis))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ZenithiumError.healthAuthorizationDenied)
                }
            }
        }
        ZenithiumLog.health.notice("Authorization sheet completed for \(readTypes.count, privacy: .public) read types")
    }

    /// ASSUMPTION API-6: HealthKit deliberately does not report read authorization, so this
    /// reports only what it can know — whether the sheet still needs to be shown. A genuine
    /// denial surfaces later as `HKError.errorAuthorizationDenied` on a query, which
    /// `mapError` turns into `ZenithiumError.healthAuthorizationDenied` and the UI turns into
    /// the recoverable Settings gate (§5.6).
    func authorizationReport(now: Date) async -> HealthAuthorizationReport {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable(at: now)
        }
        let readTypes = HealthKitTypeCatalog.readTypes
        let store = self.store
        let status: HKAuthorizationRequestStatus? = await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: Set<HKSampleType>(), read: readTypes) { status, error in
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
        let overall: HealthAuthorizationState
        if let status {
            switch status {
            case .shouldRequest: overall = .notDetermined
            case .unnecessary: overall = .authorized
            case .unknown: overall = .notDetermined
            @unknown default: overall = .notDetermined
            }
        } else {
            overall = .notDetermined
        }
        var byKind: [HealthDataKind: HealthAuthorizationState] = [:]
        for kind in HealthDataKind.allCases {
            byKind[kind] = overall
        }
        return HealthAuthorizationReport(overall: overall, byKind: byKind, checkedAt: now)
    }

    func fetchCharacteristics() async throws -> UserCharacteristics {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ZenithiumError.healthDataUnavailable
        }
        var dateOfBirth: Date?
        if let components = try? store.dateOfBirthComponents() {
            dateOfBirth = Calendar(identifier: .gregorian).date(from: components)
        }
        var sex: BiologicalSexValue = .notSet
        if let object = try? store.biologicalSex() {
            sex = HealthKitMapping.biologicalSex(from: object.biologicalSex)
        }
        return UserCharacteristics(
            dateOfBirth: dateOfBirth,
            biologicalSex: sex,
            maxHeartRateOverride: nil
        )
    }

    // MARK: - Baseline series

    func fetchBaselineSeries(
        days: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> BaselineSeries {
        // §4.2.1 — the window ends at the start of today, so today can never contaminate the
        // baseline it is scored against.
        let end = calendar.startOfDay(for: now)
        guard days > 0,
              let start = calendar.date(byAdding: .day, value: -days, to: end) else {
            return .empty(rangeStart: end, rangeEnd: end)
        }
        let timeZoneIdentifier = calendar.timeZone.identifier
        // Read the metrics concurrently rather than one after another. Each child reports its
        // own outcome, so §4.3 still holds: an unavailable metric is dropped and never
        // zero-filled, while cancellation and hard authorization failures still reach the
        // caller. Yol haritası v4, A7.
        let metrics: [MetricKind] = MetricKind.allCases
        let results: [MetricFetchOutcome] = await withBoundedTaskGroup(
            over: metrics,
            limit: ZenithiumConcurrency.maximumConcurrentHealthReads
        ) { (metric: MetricKind) -> MetricFetchOutcome in
            do {
                let samples: [DailyMetricSample] = try await self.fetchDailyAverages(
                    metric: metric,
                    start: start,
                    end: end,
                    calendar: calendar,
                    timeZoneIdentifier: timeZoneIdentifier
                )
                return .samples(samples)
            } catch {
                return .failed(Self.normalized(error, metric: metric))
            }
        }

        // `withBoundedTaskGroup` answers one result per input, in input order, so the metric
        // and its outcome are paired positionally. This used to build a dictionary and look
        // each metric back up, which added a `nil` branch that could not occur and a
        // `uniqueKeysWithValues` trap that only `allCases` being distinct kept unreached.
        var samplesByMetric: [MetricKind: [DailyMetricSample]] = [:]
        for (metric, outcome) in zip(metrics, results) {
            switch outcome {
            case .samples(let samples):
                if !samples.isEmpty { samplesByMetric[metric] = samples }
            case .failed(let error):
                // §4.3 drops a metric the device has nothing for. It does not cover a metric
                // being withheld — a locked store, a denied permission — so those refuse the
                // whole series rather than hand `BaselineEngine` a quietly shortened one.
                if error.blocksPartialResults { throw error }
                ZenithiumLog.health.error("Baseline fetch failed for \(metric.rawValue, privacy: .public)")
            }
        }
        return BaselineSeries(samplesByMetric: samplesByMetric, rangeStart: start, rangeEnd: end)
    }

    /// What one metric's baseline read produced.
    ///
    /// A task group's result has to be `Sendable`, and `any Error` is not — so the two cases
    /// the caller distinguishes are named rather than carried as an opaque error.
    /// Yol haritası v4, A7.
    private enum MetricFetchOutcome: Sendable {
        case samples([DailyMetricSample])
        case failed(ZenithiumError)
    }

    /// The same shape for the overnight read, whose child answers with one number or none.
    ///
    /// `.average(nil)` and `.failed` say different things and the difference decides whether
    /// the night is scored: no reading is a gap §4.3 renormalizes around, while a refusal is
    /// a reason not to produce a score at all.
    private enum MetricAverageOutcome: Sendable {
        case average(Double?)
        case failed(ZenithiumError)
    }

    /// Normalizes anything a child read can throw into the typed surface.
    ///
    /// `runQuery` opens with `Task.checkCancellation()`, which throws `CancellationError` —
    /// not `ZenithiumError.cancelled`. A plain fall-through to `healthQueryFailed` therefore
    /// classified an abandoned read as a merely unreadable metric, and the pass carried on
    /// scoring the day from whatever the other children had managed to return.
    private static func normalized(_ error: any Error, metric: MetricKind) -> ZenithiumError {
        if let typed = error as? ZenithiumError { return typed }
        if error is CancellationError { return .cancelled }
        return .healthQueryFailed(kind: metric.healthDataKind, detail: "\(error)")
    }

    private func fetchDailyAverages(
        metric: MetricKind,
        start: Date,
        end: Date,
        calendar: Calendar,
        timeZoneIdentifier: String
    ) async throws -> [DailyMetricSample] {
        let quantityType = HealthKitTypeCatalog.quantityType(for: metric)
        let options = HealthKitTypeCatalog.aggregationOption(for: metric)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let anchorDate = calendar.startOfDay(for: start)
        var interval = DateComponents()
        interval.day = 1
        let kind = metric.healthDataKind

        return try await runQuery { completion in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    completion(.failure(Self.mapError(error, kind: kind)))
                    return
                }
                guard let collection else {
                    completion(.success([]))
                    return
                }
                let samples = HealthKitMapping.dailySamples(
                    from: collection,
                    metric: metric,
                    start: start,
                    end: end,
                    calendar: calendar,
                    timeZoneIdentifier: timeZoneIdentifier
                )
                completion(.success(samples))
            }
            return query
        }
    }

    // MARK: - Vital signs (Faz 11)

    func fetchVitalSamples(
        sign: VitalSign,
        days: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> [VitalSample] {
        // The window ends at the start of tomorrow so today's own reading is included —
        // unlike the recovery baseline, which must exclude today because today is what it
        // scores. Here today *is* the reading.
        let todayStart = calendar.startOfDay(for: now)
        guard days > 0,
              let end = calendar.date(byAdding: .day, value: 1, to: todayStart),
              let start = calendar.date(byAdding: .day, value: -days, to: todayStart) else {
            return []
        }

        let quantityType = HealthKitTypeCatalog.quantityType(for: sign)
        let unit = HealthKitTypeCatalog.unit(for: sign)
        let scale = HealthKitTypeCatalog.displayScale(for: sign)
        let options = HealthKitTypeCatalog.aggregationOption(for: sign)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        var interval = DateComponents()
        interval.day = 1

        return try await runQuery { completion in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    completion(.failure(Self.mapVitalError(error, sign: sign)))
                    return
                }
                guard let collection else {
                    completion(.success([]))
                    return
                }

                var samples: [VitalSample] = []
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity = options == .cumulativeSum
                        ? statistics.sumQuantity()
                        : statistics.averageQuantity()
                    guard let quantity else { return }
                    let value = quantity.doubleValue(for: unit) * scale
                    guard value.isFinite else { return }
                    samples.append(
                        VitalSample(
                            sign: sign,
                            dayStart: calendar.startOfDay(for: statistics.startDate),
                            value: value
                        )
                    )
                }
                completion(.success(samples))
            }
            return query
        }
    }

    // MARK: - Menstrual flow (Faz 12)

    func fetchMenstrualFlowDays(
        days: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> [MenstrualFlowDay] {
        let todayStart = calendar.startOfDay(for: now)
        guard days > 0,
              let end = calendar.date(byAdding: .day, value: 1, to: todayStart),
              let start = calendar.date(byAdding: .day, value: -days, to: todayStart) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample] = try await runQuery { completion in
            let query = HKSampleQuery(
                sampleType: HealthKitTypeCatalog.menstrualFlowType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, results, error in
                if let error {
                    completion(.failure(Self.mapCycleError(error)))
                    return
                }
                completion(.success((results as? [HKCategorySample]) ?? []))
            }
            return query
        }

        // One entry per day. HealthKit can hold several flow samples for a single day, and
        // the cycle engine counts days, not samples.
        var byDay: [Date: Bool] = [:]
        for sample in samples {
            // `.unspecified` and `.none` are logged absences, not bleeding. Counting them
            // would put a period start wherever somebody recorded a dry day.
            let value = HKCategoryValueVaginalBleeding(rawValue: sample.value)
            guard let value, value != .none, value != .unspecified else { continue }

            let day = calendar.startOfDay(for: sample.startDate)
            let isStart = (sample.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) ?? false
            byDay[day] = (byDay[day] ?? false) || isStart
        }

        return byDay
            .map { MenstrualFlowDay(dayStart: $0.key, isCycleStart: $0.value) }
            .sorted { $0.dayStart < $1.dayStart }
    }

    /// Cycle reads get their own error mapping for the same reason vitals do: the failure
    /// is not about a `HealthDataKind`.
    private static func mapCycleError(_ error: any Error) -> ZenithiumError {
        let nsError = error as NSError
        if let shared = sharedHealthKitMapping(nsError) { return shared }
        return .persistenceReadFailed(detail: nsError.localizedDescription)
    }

    // MARK: - Overnight

    func fetchOvernightBiometrics(
        for night: DateInterval,
        calendar: Calendar
    ) async throws -> OvernightData {
        let timeZoneIdentifier = calendar.timeZone.identifier

        // ASSUMPTION API-8 — overnight metrics are averaged over the sleep window widened by
        // two hours each way, because HealthKit writes resting heart rate and wrist
        // temperature as day-spanning samples that need not lie strictly inside the night.
        let widened = DateInterval(
            start: night.start.addingTimeInterval(-Self.overnightWindowPadding),
            end: night.end.addingTimeInterval(Self.overnightWindowPadding)
        )

        let sleepSegments = try await fetchSleepSegments(
            in: DateInterval(start: widened.start, end: widened.end),
            fallbackTimeZoneIdentifier: timeZoneIdentifier
        )

        // Naps in the daytime preceding the night, feeding the next night's credit (§5.2,
        // ASSUMPTION SLEEP-4).
        let napWindow = DateInterval(
            start: night.start.addingTimeInterval(-Self.napLookbackWindow),
            end: night.start
        )
        let napSegments = try await fetchSleepSegments(
            in: napWindow,
            fallbackTimeZoneIdentifier: timeZoneIdentifier
        )

        // Same shape as the baseline read: one wave rather than one metric at a time.
        // Yol haritası v4, A7.
        let metrics: [MetricKind] = MetricKind.allCases
        let fetched: [MetricAverageOutcome] = await withBoundedTaskGroup(
            over: metrics,
            limit: ZenithiumConcurrency.maximumConcurrentHealthReads
        ) { (metric: MetricKind) -> MetricAverageOutcome in
            do {
                return .average(try await self.fetchAverageQuantity(metric: metric, in: widened))
            } catch {
                return .failed(Self.normalized(error, metric: metric))
            }
        }
        // This was a `try?`, which is where the locked-device path leaked. `fetchAverageQuantity`
        // already drops the failures §4.3 allows to be dropped and rethrows only the ones that
        // withhold data — and the `try?` above it then swallowed those too, so a night read on
        // a locked phone reached `RecoveryEngine` as a set of missing metrics rather than as a
        // refusal, and the engine renormalized its weights and scored the day.
        var averages: [MetricKind: Double] = [:]
        for (metric, outcome) in zip(metrics, fetched) {
            switch outcome {
            case .average(let average):
                if let average { averages[metric] = average }
            case .failed(let error):
                if error.blocksPartialResults { throw error }
                ZenithiumLog.health.error("Overnight fetch failed for \(metric.rawValue, privacy: .public)")
            }
        }

        let values = averages
        let temperatureSupported = averages[.wristTemperature] != nil
        let oxygen = try await fetchAverageOxygenSaturation(in: widened)

        return OvernightData(
            night: night,
            timeZoneIdentifier: timeZoneIdentifier,
            heartRateVariability: values[.heartRateVariability],
            restingHeartRate: values[.restingHeartRate],
            wristTemperature: values[.wristTemperature],
            respiratoryRate: values[.respiratoryRate],
            oxygenSaturation: oxygen,
            sleepSegments: sleepSegments,
            napSegments: napSegments.filter { $0.isAsleep },
            wristTemperatureSupported: temperatureSupported
        )
    }

    private func fetchSleepSegments(
        in interval: DateInterval,
        fallbackTimeZoneIdentifier: String
    ) async throws -> [SleepSegment] {
        let type = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await runQuery { completion in
            HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HealthQueryTuning.windowedQuerySampleLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    completion(.failure(Self.mapError(error, kind: .sleepAnalysis)))
                    return
                }
                let mapped = HealthKitMapping.sleepSegments(
                    from: samples ?? [],
                    fallbackTimeZoneIdentifier: fallbackTimeZoneIdentifier
                )
                completion(.success(mapped))
            }
        }
    }

    private func fetchAverageQuantity(
        metric: MetricKind,
        in interval: DateInterval
    ) async throws -> Double? {
        let type = HealthKitTypeCatalog.quantityType(for: metric)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let kind = metric.healthDataKind
        do {
            return try await runQuery { completion in
                HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HealthQueryTuning.windowedQuerySampleLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        completion(.failure(Self.mapError(error, kind: kind)))
                        return
                    }
                    completion(.success(
                        HealthKitMapping.averageValue(from: samples ?? [], metric: metric)
                    ))
                }
            }
        } catch let error as ZenithiumError {
            if error.blocksPartialResults { throw error }
            // §4.3 — an unreadable metric is dropped and its weight renormalized, never zeroed.
            ZenithiumLog.health.error("Overnight fetch failed for \(metric.rawValue, privacy: .public)")
            return nil
        }
    }

    private func fetchAverageOxygenSaturation(in interval: DateInterval) async throws -> Double? {
        let type = HKQuantityType(.oxygenSaturation)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        do {
            return try await runQuery { completion in
                HKSampleQuery(
                    sampleType: type,
                    predicate: predicate,
                    limit: HealthQueryTuning.windowedQuerySampleLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        completion(.failure(Self.mapError(error, kind: .oxygenSaturation)))
                        return
                    }
                    completion(.success(
                        HealthKitMapping.averageOxygenSaturation(from: samples ?? [])
                    ))
                }
            }
        } catch let error as ZenithiumError where error == .cancelled {
            throw error
        } catch {
            // Blood oxygen is displayed, never scored (§3), so a failure is never fatal.
            return nil
        }
    }

    // MARK: - Intraday heart rate

    func fetchIntradayHeartRates(in interval: DateInterval) async throws -> [HeartRateSample] {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await runQuery { completion in
            HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HealthQueryTuning.windowedQuerySampleLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    completion(.failure(Self.mapError(error, kind: .heartRate)))
                    return
                }
                // §8 — map and downsample inside the callback, so nothing HealthKit-shaped
                // is alive by the time the continuation resumes.
                let mapped = HealthKitMapping.heartRateSamples(from: samples ?? [])
                completion(.success(HealthKitMapping.downsample(mapped)))
            }
        }
    }

    // MARK: - Workouts

    func fetchWorkouts(in interval: DateInterval) async throws -> [WorkoutSummary] {
        let type = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: []
        )
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await runQuery { completion in
            HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HealthQueryTuning.windowedQuerySampleLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    completion(.failure(Self.mapError(error, kind: .workout)))
                    return
                }
                completion(.success(HealthKitMapping.workoutSummaries(from: samples ?? [])))
            }
        }
    }

    // MARK: - Observed HRmax

    /// ASSUMPTION HRMAX-2 — the 99.5th percentile of daily maxima, not the raw maximum, so a
    /// single dropout artefact cannot permanently inflate `HRmax`.
    func fetchObservedMaxHeartRate(
        lookbackDays: Int,
        now: Date,
        calendar: Calendar
    ) async throws -> Double? {
        let end = calendar.startOfDay(for: now)
        guard lookbackDays > 0,
              let start = calendar.date(byAdding: .day, value: -lookbackDays, to: end) else {
            return nil
        }
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let anchorDate = calendar.startOfDay(for: start)
        var interval = DateComponents()
        interval.day = 1
        let unit = HealthKitTypeCatalog.beatsPerMinute
        let plausible = Self.plausibleHeartRateRange

        let maxima: [Double] = try await runQuery { completion in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteMax,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    completion(.failure(Self.mapError(error, kind: .heartRate)))
                    return
                }
                guard let collection else {
                    completion(.success([]))
                    return
                }
                completion(.success(
                    HealthKitMapping.dailyMaxima(
                        from: collection,
                        unit: unit,
                        start: start,
                        end: end,
                        plausibleRange: plausible
                    )
                ))
            }
            return query
        }
        // `MathSupport.percentile` rather than a private copy. This file carried a
        // line-for-line duplicate while the shared one sat unused — two implementations of
        // one statistic, and the tests only ever reached one of them.
        return MathSupport.percentile(HealthQueryTuning.observedMaxPercentile, of: maxima)
    }

    // MARK: - Observation

    func observationStream() async -> AsyncStream<HealthChangeEvent> {
        streamContinuation?.finish()
        let (stream, continuation) = AsyncStream<HealthChangeEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(16)
        )
        streamContinuation = continuation
        return stream
    }

    func enableBackgroundDelivery() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ZenithiumError.healthDataUnavailable
        }
        guard !backgroundDeliveryEnabled else { return }
        backgroundDeliveryEnabled = true

        for sampleType in HealthKitTypeCatalog.observedSampleTypes {
            guard let kind = HealthKitTypeCatalog.kind(for: sampleType) else { continue }
            let query = HKObserverQuery(
                sampleType: sampleType,
                predicate: nil
            ) { [weak self] _, completionHandler, error in
                // ASSUMPTION API-9 — acknowledge HealthKit synchronously, then process. The
                // completion handler is not `Sendable` and must not be captured by a Task;
                // acknowledging first is safe because the anchor is persisted, so a wake lost
                // to termination is caught up on the next pass rather than dropped.
                completionHandler()
                if error != nil {
                    ZenithiumLog.health.error("Observer error for \(kind.rawValue, privacy: .public)")
                    return
                }
                guard let self else { return }
                Task { await self.processChanges(for: kind) }
            }
            observerQueries.append(query)
            store.execute(query)
            try await enableBackgroundDelivery(for: sampleType, kind: kind)
        }
        ZenithiumLog.health.notice("Background delivery enabled for \(self.observerQueries.count, privacy: .public) types")
    }

    private func enableBackgroundDelivery(
        for sampleType: HKSampleType,
        kind: HealthDataKind
    ) async throws {
        let store = self.store
        let frequency = HealthQueryTuning.backgroundDeliveryFrequency
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            store.enableBackgroundDelivery(for: sampleType, frequency: frequency) { success, error in
                if let error {
                    continuation.resume(throwing: Self.mapError(error, kind: kind))
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ZenithiumError.healthQueryFailed(
                        kind: kind,
                        detail: "Background delivery was refused."
                    ))
                }
            }
        }
    }

    func stopObserving() async {
        for query in observerQueries {
            store.stop(query)
        }
        observerQueries.removeAll()
        for (id, query) in activeQueries {
            store.stop(query)
            pendingResumptions.removeValue(forKey: id)?()
        }
        activeQueries.removeAll()
        streamContinuation?.finish()
        streamContinuation = nil
        backgroundDeliveryEnabled = false
    }

    /// Runs the anchored query that turns an observer fire into a described change, including
    /// deletions (§5.6), and advances the persisted anchor.
    private func processChanges(for kind: HealthDataKind) async {
        guard let sampleType = HealthKitTypeCatalog.objectType(for: kind) as? HKSampleType else {
            return
        }
        let storedAnchor = await anchorStore.anchorData(for: kind)
        let anchor = storedAnchor.flatMap(AnchorCoding.anchor(from:))
        do {
            let result = try await runAnchoredQuery(
                sampleType: sampleType,
                kind: kind,
                anchor: anchor
            )
            if let anchorData = result.anchorData {
                await anchorStore.setAnchorData(anchorData, for: kind)
            }
            guard result.hasChanges else { return }
            ZenithiumLog.health.debug(
                "Change in \(kind.rawValue, privacy: .public): added \(result.addedCount, privacy: .public), deleted \(result.deletedCount, privacy: .public)"
            )
            streamContinuation?.yield(
                HealthChangeEvent(
                    kinds: [kind],
                    observedAt: Date(),
                    includesDeletions: result.deletedCount > 0
                )
            )
        } catch {
            ZenithiumLog.health.error("Anchored query failed for \(kind.rawValue, privacy: .public)")
        }
    }

    private func runAnchoredQuery(
        sampleType: HKSampleType,
        kind: HealthDataKind,
        anchor: HKQueryAnchor?
    ) async throws -> AnchoredChangeResult {
        try await runQuery { completion in
            HKAnchoredObjectQuery(
                type: sampleType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    completion(.failure(Self.mapError(error, kind: kind)))
                    return
                }
                // The anchor is reduced to `Data` here, inside the callback, so that no
                // `HKQueryAnchor` is alive when the continuation resumes (§8).
                let anchorData = newAnchor.flatMap(AnchorCoding.data(from:))
                completion(.success(
                    AnchoredChangeResult(
                        addedCount: samples?.count ?? 0,
                        deletedCount: deleted?.count ?? 0,
                        anchorData: anchorData
                    )
                ))
            }
        }
    }

    // MARK: - Query plumbing

    /// Runs one HealthKit query as an `async` call.
    ///
    /// `build` receives the completion to invoke and returns the query to execute. The
    /// completion may be called from any queue; it only ever carries `Sendable` values.
    private func runQuery<Value: Sendable>(
        _ build: (@escaping @Sendable (Result<Value, ZenithiumError>) -> Void) -> HKQuery
    ) async throws -> Value {
        try Task.checkCancellation()
        let id = UUID()
        liveQueryIDs.insert(id)
        defer {
            liveQueryIDs.remove(id)
            cancelledBeforeRegistration.remove(id)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
                let query = build { result in
                    Task { [weak self] in
                        // Resumption ownership is claimed on the actor. Exactly one of the
                        // completion path and the cancellation path can win.
                        guard let self, await self.claimResumption(id: id) else { return }
                        switch result {
                        case .success(let value):
                            continuation.resume(returning: value)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
                // Cancellation may already have run. Registering here and waiting for a
                // `cancelQuery` that has been and gone is the hang this guard removes.
                // The query was built but never executed, so there is nothing to stop.
                if cancelledBeforeRegistration.remove(id) != nil {
                    continuation.resume(throwing: ZenithiumError.cancelled)
                    return
                }
                pendingResumptions[id] = {
                    continuation.resume(throwing: ZenithiumError.cancelled)
                }
                activeQueries[id] = query
                store.execute(query)
            }
        } onCancel: {
            Task { await self.cancelQuery(id: id) }
        }
    }

    /// Claims the right to resume a continuation. Returns `false` when the cancellation path
    /// already resumed it.
    private func claimResumption(id: UUID) -> Bool {
        let owned = pendingResumptions.removeValue(forKey: id) != nil
        if let query = activeQueries.removeValue(forKey: id), !owned {
            store.stop(query)
        }
        return owned
    }

    /// Stops a running query and resumes its continuation with `.cancelled`, if the
    /// completion path has not already taken ownership.
    private func cancelQuery(id: UUID) {
        if let query = activeQueries.removeValue(forKey: id) {
            store.stop(query)
        }
        if let resume = pendingResumptions.removeValue(forKey: id) {
            resume()
            return
        }
        // No continuation to resume. Either it has not registered yet — in which case the
        // mark makes registration fail immediately instead of waiting forever — or the query
        // already settled and `runQuery` has dropped the identifier, in which case there is
        // nothing left to do.
        if liveQueryIDs.contains(id) {
            cancelledBeforeRegistration.insert(id)
        }
    }

    // MARK: - Electrocardiogram

    func fetchECGRecords(days: Int, now: Date) async throws -> [ECGRecord] {
        let type = HKObjectType.electrocardiogramType()
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: []
        )
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await runQuery { completion in
            HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HealthQueryTuning.windowedQuerySampleLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    completion(.failure(Self.mapError(error, kind: .heartRate)))
                    return
                }
                let mapped = HealthKitMapping.ecgRecords(from: samples ?? [])
                completion(.success(mapped))
            }
        }
    }

    // MARK: - Constants and helpers

    /// ASSUMPTION API-8 — how far the overnight window is widened on each side.
    private static let overnightWindowPadding: TimeInterval = 2 * 3600

    /// ASSUMPTION SLEEP-4 — how far back naps are collected before the night starts.
    private static let napLookbackWindow: TimeInterval = 18 * 3600

    /// Sensor-plausible heart rate, matching `HeartRateSample.isPlausible`.
    private static let plausibleHeartRateRange: ClosedRange<Double> = 25...240

    /// Maps a HealthKit error into Zenithium's typed error. Authorization failures are the
    /// signal that drives the §5.6 recoverable gate.
    /// The same authorization branches as `mapError`, ending in a vital-shaped error.
    private static func mapVitalError(_ error: any Error, sign: VitalSign) -> ZenithiumError {
        let nsError = error as NSError
        if let shared = sharedHealthKitMapping(nsError) { return shared }
        return .vitalQueryFailed(sign: sign, detail: nsError.localizedDescription)
    }

    /// The HealthKit failures that mean the same thing wherever they are raised.
    ///
    /// Three call sites used to carry an identical copy of this switch, differing only in the
    /// error they fell through to. That is exactly the shape a new case gets added to twice
    /// and forgotten in the third — so there is one copy now, and the fall-through stays with
    /// each caller because that part genuinely differs.
    private static func sharedHealthKitMapping(_ nsError: NSError) -> ZenithiumError? {
        guard nsError.domain == HKError.errorDomain else { return nil }
        switch nsError.code {
        case HKError.Code.errorAuthorizationDenied.rawValue:
            return .healthAuthorizationDenied
        case HKError.Code.errorAuthorizationNotDetermined.rawValue:
            return .healthAuthorizationNotDetermined
        case HKError.Code.errorHealthDataUnavailable.rawValue,
             HKError.Code.errorHealthDataRestricted.rawValue:
            return .healthDataUnavailable
        case HKError.Code.errorDatabaseInaccessible.rawValue:
            // The device is locked and the store is encrypted. Named apart from a query
            // failure because the remedy is entirely different: not a retry and not a
            // permission, but waiting for an unlock. See `ProtectedDataGuard`.
            return .healthDataProtected
        default:
            return nil
        }
    }

    private static func mapError(_ error: any Error, kind: HealthDataKind) -> ZenithiumError {
        let nsError = error as NSError
        if let shared = sharedHealthKitMapping(nsError) { return shared }
        return .healthQueryFailed(kind: kind, detail: nsError.localizedDescription)
    }
}
