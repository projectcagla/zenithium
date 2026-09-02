//
//  DailyRecalculationCoordinator.swift
//  Zenithium
//
//  The pipeline: HealthKit → engines → store → widget snapshot → subscribers. Spec §10.
//
//  Idempotent, cancellable, and safe to run concurrently with itself: a second caller joins
//  the in-flight pass rather than starting a second one, so an observer wake landing at the
//  same moment as a pull-to-refresh does one unit of work, not two.
//

import Foundation

/// What one recalculation produced.
struct RecalculationResult: Sendable, Equatable {

    let dayStart: Date
    let computedAt: Date

    /// The window the day's intraday figures were integrated over.
    ///
    /// Carried on the result so a screen that needs to re-read the same span — the Faz 13
    /// split, for one — asks for exactly the window the numbers came from, instead of
    /// rebuilding a resolver and risking a slightly different one.
    let dayWindow: DateInterval

    let recovery: RecoveryOutput
    let sleep: SleepOutput
    let strain: StrainOutput?
    let muscle: [MuscleGroup: MuscleReadiness]
    let circadian: CircadianArc?

    let profile: UserProfileSnapshot
    let record: BiometricDaySnapshot

    /// Baseline confidence for the required metrics, `n/14` (§4.2.4).
    let calibrationProgress: Double
}

actor DailyRecalculationCoordinator {

    private let health: any HealthDataProviding
    private let store: any ZenithiumRepository
    private let calendarProvider: @Sendable () -> Calendar

    /// The in-flight pass, if any. This is the single-flight gate.
    private var inFlight: Task<RecalculationResult, any Error>?

    /// The in-flight deep historical backfill, so multiple passes do not duplicate 90-day history walks.
    private var inFlightBackfill: Task<Void, Never>?

    /// Subscribers to completed passes, so a background refresh updates a foregrounded UI.
    private var subscribers: [UUID: AsyncStream<RecalculationResult>.Continuation] = [:]

    /// Writes the widget snapshot and decides whether the widgets need to redraw.
    private let widgets: WidgetRefreshPublisher

    init(
        health: any HealthDataProviding,
        store: any ZenithiumRepository,
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent },
        widgets: WidgetRefreshPublisher = WidgetRefreshPublisher()
    ) {
        self.health = health
        self.store = store
        self.calendarProvider = calendarProvider
        self.widgets = widgets
    }

    // MARK: - Entry points

    /// Recomputes today. Concurrent callers join the pass already running.
    @discardableResult
    func recalculate(now: Date) async throws -> RecalculationResult {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { [weak self] () throws -> RecalculationResult in
            guard let self else { throw ZenithiumError.cancelled }
            return try await self.performRecalculation(now: now)
        }
        inFlight = task
        // Cleared by identity rather than unconditionally. Only the caller that installed a
        // task can reach these lines while it is in flight, so today the two are the same —
        // but `inFlight = nil` written flat is a line that stays correct only as long as that
        // argument holds, and the same gate in `DayRecordCache` already needed the guard.
        do {
            let result = try await task.value
            if inFlight == task { inFlight = nil }
            return result
        } catch {
            if inFlight == task { inFlight = nil }
            throw error
        }
    }

    /// Recomputes days whose records were produced by an older engine (§7).
    ///
    /// Bounded per pass so a version bump does not turn the next launch into a long stall;
    /// the remaining days are picked up by subsequent passes.
    func backfillPendingDays(now: Date, limit: Int = 7) async throws {
        let stale = try await store.dayRecordsNeedingBackfill(
            currentEngineVersion: EngineConstants.engineVersion
        )
        guard !stale.isEmpty else { return }
        ZenithiumLog.orchestration.notice(
            "Backfilling \(min(stale.count, limit), privacy: .public) of \(stale.count, privacy: .public) stale days"
        )
        // Every day in this pass shares one `now`, so they share one baseline rebuild.
        // Yol haritası v4, A8.
        for dayStart in stale.suffix(limit) {
            try Task.checkCancellation()
            _ = try? await recalculateDay(wakeDay: dayStart, now: now)
        }
    }

    /// Deep historical backfill: Discovers missing historical days from HealthKit (up to `windowDays`)
    /// and calculates them in chronological order (oldest -> newest).
    ///
    /// This immediately populates ACWR (acute/chronic load), HRV baselines, sleep consistency,
    /// sleep debt, and muscle fatigue models on first launch or sparse store states.
    func backfillHistoricalDays(now: Date, windowDays: Int = 90) async throws {
        let calendar = calendarProvider()
        let profile = try await store.profile()
        let resolver = DayWindowResolver(calendar: calendar, boundary: profile.dayBoundary)

        let today = calendar.startOfDay(for: now)
        let startDate = resolver.day(byAdding: -windowDays, to: today)

        let existingRecords = try await store.dayRecords(from: startDate, through: today)
        let existingDays = Set(existingRecords.map(\.dayStart))

        var missingDays: [Date] = []
        for offset in (1...windowDays).reversed() {
            let day = resolver.day(byAdding: -offset, to: today)
            if !existingDays.contains(day) {
                missingDays.append(day)
            }
        }

        guard !missingDays.isEmpty else { return }

        ZenithiumLog.orchestration.notice(
            "Starting deep historical backfill for \(missingDays.count, privacy: .public) missing days"
        )

        for wakeDay in missingDays {
            try Task.checkCancellation()
            // Set now to near the end of that day so strain and sleep compute against that day's window
            let dayNow = resolver.day(byAdding: 1, to: wakeDay).addingTimeInterval(-60)
            _ = try? await recalculateDay(wakeDay: wakeDay, now: dayNow)
        }

        // Recompute today now that the entire history is committed to the local store
        let finalResult = try await recalculateDay(wakeDay: today, now: now)
        publish(finalResult)
        await refreshWidgetTrend(now: now, result: finalResult)
        ZenithiumLog.orchestration.notice("Deep historical backfill completed successfully.")
    }

    /// A stream of completed passes. Each consumer gets its own.
    func results() -> AsyncStream<RecalculationResult> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<RecalculationResult>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        subscribers[id] = continuation
        return stream
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func publish(_ result: RecalculationResult) {
        for continuation in subscribers.values {
            continuation.yield(result)
        }
    }

    // MARK: - Pipeline

    private func performRecalculation(now: Date) async throws -> RecalculationResult {
        let calendar = calendarProvider()
        let today = calendar.startOfDay(for: now)
        let result = try await recalculateDay(wakeDay: today, now: now)
        publish(result)
        // The widget snapshot is written from the committed records, so its three-day trend
        // is real history rather than the single day this pass happened to compute.
        await refreshWidgetTrend(now: now, result: result)

        // Run deep historical backfill in the background with a single-flight gate if history is sparse
        scheduleHistoricalBackfillIfNeeded(now: now)

        return result
    }

    private func scheduleHistoricalBackfillIfNeeded(now: Date) {
        guard inFlightBackfill == nil else { return }
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                Task { await self.clearBackfillTask() }
            }
            do {
                try await self.backfillHistoricalDays(now: now, windowDays: 90)
            } catch {
                ZenithiumLog.orchestration.notice(
                    "Historical backfill stopped or cancelled: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        inFlightBackfill = task
    }

    /// Explicit cancellation handle for the background backfill task when backgrounding or observer stops.
    func cancelBackfill() {
        if let inFlightBackfill {
            inFlightBackfill.cancel()
            self.inFlightBackfill = nil
            ZenithiumLog.orchestration.notice("Historical backfill explicitly cancelled.")
        }
    }

    private func clearBackfillTask() {
        inFlightBackfill = nil
    }

    /// The whole pipeline for one day. Parameterised by day so the backfill path and the
    /// live path are the same code rather than two implementations that can drift.
    private func recalculateDay(wakeDay: Date, now: Date) async throws -> RecalculationResult {
        // Signposted so an Instruments trace can attribute a slow launch to this pipeline
        // rather than to the screen that happens to be waiting on it. Yol haritası v4, A9.
        try await ZenithiumSignpost.interval(ZenithiumSignpost.orchestration, "recalculateDay") {
            try await performRecalculation(wakeDay: wakeDay, now: now)
        }
    }

    private func performRecalculation(wakeDay: Date, now: Date) async throws -> RecalculationResult {
        try Task.checkCancellation()

        let calendar = calendarProvider()
        let profile = try await store.profile()
        let resolver = DayWindowResolver(calendar: calendar, boundary: profile.dayBoundary)
        let engineVersion = EngineConstants.engineVersion

        // 1. Baselines. Rebuilt from the trailing series each pass, which is what makes the
        //    whole pipeline idempotent: running it twice cannot fold a day in twice.
        let baselines = try await refreshBaselines(now: now, calendar: calendar)

        // 2. Sleep history & previous night's wake time (§5.2).
        let history = try await store.dayRecords(
            from: resolver.day(byAdding: -EngineConstants.Sleep.consistencyWindowDays, to: wakeDay),
            through: resolver.day(byAdding: -1, to: wakeDay)
        )
        let previousDay = resolver.day(byAdding: -1, to: wakeDay)
        let previousWakeTime = history.first(where: { calendar.isDate($0.dayStart, inSameDayAs: previousDay) })?.wakeTime

        // 3. The night that belongs to this wake day.
        let night = resolver.nightWindow(forWakeDay: wakeDay)
        let overnight = try await health.fetchOvernightBiometrics(
            for: night,
            calendar: calendar,
            previousWakeTime: previousWakeTime
        )

        // 4. Sleep.
        let sleepContext = resolveSleep(
            overnight: overnight,
            history: history,
            profile: profile,
            calendar: calendar,
            previousWakeTime: previousWakeTime
        )
        let sleepOutput = SleepScoreEngine.compute(sleepContext.input)

        // 4. Recovery.
        let recoveryInput = makeRecoveryInput(
            overnight: overnight,
            baselines: baselines,
            sleepOutput: sleepOutput
        )
        let recoveryOutput = RecoveryEngine.compute(recoveryInput)

        // 5. Strain over the physiological day (ASSUMPTION DAY-1).
        let dayWindow = resolver.window(containing: now, wakeTime: sleepContext.wakeTime)
        let strainOutput = try await computeStrain(
            dayWindow: dayWindow,
            profile: profile,
            baselines: baselines,
            overnight: overnight,
            recoveryScore: recoveryOutput.score,
            now: now,
            calendar: calendar
        )

        // 6. Muscle fatigue.
        let muscle = try await projectFatigue(
            now: now,
            calendar: calendar,
            resolver: resolver,
            profile: profile,
            baselines: baselines,
            sleepScore: sleepOutput.score
        )

        // 7. Circadian arc.
        let circadian = sleepContext.sleepStart.flatMap { sleepStart -> CircadianArc? in
            guard sleepContext.asleepSeconds > 0, let wakeTime = sleepContext.wakeTime else {
                return nil
            }
            return CircadianEngine.arc(
                CircadianInput(
                    sleepStart: sleepStart,
                    sleepDuration: sleepContext.asleepSeconds,
                    wakeTime: wakeTime,
                    recoveryScore: recoveryOutput.score,
                    anchors: EngineConstants.Circadian.defaultAnchors,
                    renderWindow: dayWindow.interval,
                    sampleInterval: nil
                )
            )
        }

        // 8. Persist.
        let write = makeWrite(
            dayStart: dayWindow.dayStart,
            timeZoneIdentifier: dayWindow.timeZoneIdentifier,
            now: now,
            engineVersion: engineVersion,
            overnight: overnight,
            sleepContext: sleepContext,
            sleepOutput: sleepOutput,
            recoveryOutput: recoveryOutput,
            strainOutput: strainOutput,
            baselines: baselines
        )
        let record = try await store.upsertDayRecord(write)

        let arrays = MuscleFatigueSnapshot.arrays(from: muscle)
        try await store.saveMuscleSnapshot(
            MuscleFatigueSnapshotRecord(
                computedAt: now,
                fatigueValues: arrays.fatigue,
                halfLifeHours: arrays.halfLife,
                sleepScoreUsed: sleepOutput.score ?? Self.neutralSleepScore,
                engineVersion: engineVersion
            )
        )

        return RecalculationResult(
            dayStart: dayWindow.dayStart,
            computedAt: now,
            dayWindow: dayWindow.interval,
            recovery: recoveryOutput,
            sleep: sleepOutput,
            strain: strainOutput,
            muscle: muscle,
            circadian: circadian,
            profile: profile,
            record: record,
            calibrationProgress: recoveryOutput.confidence
        )
    }

    // MARK: - Steps

    /// The baselines for one `now`, and the `now` they were built for.
    ///
    /// A backfill pass runs the pipeline for up to eight days against the same instant, and
    /// the baselines depend on nothing but that instant and the calendar. Without this memo
    /// the pass makes eight identical sixty-day HealthKit reads and eight identical writes,
    /// on exactly the launch that is already the slowest. Yol haritası v4, A8.
    ///
    /// Held for the pass rather than for a duration: the next pass has a different `now` and
    /// rebuilds, so there is no staleness to reason about.
    private var cachedBaselines: (now: Date, values: [MetricKind: BaselineSnapshot])?

    private func refreshBaselines(
        now: Date,
        calendar: Calendar
    ) async throws -> [MetricKind: BaselineSnapshot] {
        if let cachedBaselines, cachedBaselines.now == now {
            return cachedBaselines.values
        }
        let values = try await rebuildBaselines(now: now, calendar: calendar)
        cachedBaselines = (now, values)
        return values
    }

    private func rebuildBaselines(
        now: Date,
        calendar: Calendar
    ) async throws -> [MetricKind: BaselineSnapshot] {
        let series = try await health.fetchBaselineSeries(
            days: EngineConstants.Baseline.windowDays,
            now: now,
            calendar: calendar
        )
        var baselines: [MetricKind: BaselineSnapshot] = [:]
        for metric in MetricKind.allCases {
            let samples = series.samples(for: metric)
            guard !samples.isEmpty else { continue }
            baselines[metric] = BaselineEngine.rebuild(metric: metric, from: samples)
        }
        if !baselines.isEmpty {
            try await store.saveBaselines(baselines)
        }
        return baselines
    }

    /// Everything the sleep engine needs, plus the block boundaries the rest of the pipeline
    /// reuses for the day anchor and the circadian arc.
    private struct SleepContext: Sendable {
        let input: SleepInput
        let sleepStart: Date?
        let wakeTime: Date?
        let asleepSeconds: Double
        let deepSeconds: Double
        let remSeconds: Double
        let coreSeconds: Double
        let awakeSeconds: Double
        let timeInBedSeconds: Double
        let midpointMinutes: Double?
        let napSeconds: Double
        let hasOverlappingSegments: Bool
    }

    private func resolveSleep(
        overnight: OvernightData,
        history: [BiometricDaySnapshot],
        profile: UserProfileSnapshot,
        calendar: Calendar,
        previousWakeTime: Date?
    ) -> SleepContext {
        let segments = overnight.sleepSegments
        let block = SleepScoreEngine.longestAsleepBlock(in: segments)

        let asleepSeconds = block?.asleepSeconds ?? 0
        let sleepStart = block?.interval.start
        let wakeTime = block?.interval.end

        let deep: Double
        let rem: Double
        let core: Double
        let awake: Double
        let timeInBed: Double
        var midpointMinutes: Double?

        if let block {
            deep = SleepScoreEngine.stageSeconds([.asleepDeep], in: segments, clippedTo: block.interval)
            rem = SleepScoreEngine.stageSeconds([.asleepREM], in: segments, clippedTo: block.interval)
            core = SleepScoreEngine.stageSeconds(
                [.asleepCore, .asleepUnspecified], in: segments, clippedTo: block.interval
            )
            awake = SleepScoreEngine.stageSeconds([.awake], in: segments, clippedTo: block.interval)

            // ASSUMPTION SLEEP-3 — use `.inBed` when the source writes it, else the block's
            // own span, so efficiency is defined for sources that never write `.inBed`.
            let inBed = segments.seconds(in: [.inBed])
            timeInBed = inBed > 0 ? max(inBed, asleepSeconds) : block.interval.duration

            midpointMinutes = SleepScoreEngine.minutesFromLocalMidnight(
                SleepScoreEngine.midpoint(of: block.interval),
                calendar: calendar
            )
        } else {
            deep = 0; rem = 0; core = 0; awake = 0; timeInBed = 0
        }

        let naps = SleepScoreEngine.resolveNaps(
            candidates: overnight.napSegments,
            previousWakeTime: previousWakeTime,
            currentNightSleepBlock: block?.interval
        )
        let napSeconds: Double
        let napCredit: Double
        if let naps {
            napSeconds = naps
                .filter { $0.duration >= EngineConstants.Sleep.minNapSeconds }
                .reduce(into: 0.0) { $0 += $1.duration }
            napCredit = SleepScoreEngine.napCredit(from: naps)
        } else {
            napSeconds = 0
            napCredit = 0
        }

        // §5.2 — the 14-day circular mean of midpoints, and the decayed 7-night debt.
        let historyNewestFirst = history.sorted { $0.dayStart > $1.dayStart }
        let midpointBaseline = SleepScoreEngine.midpointBaseline(
            minutes: history.compactMap(\.sleepMidpointMinutes)
        )
        let shortfalls = historyNewestFirst.map {
            $0.sleepShortfallHours(against: profile.baselineSleepNeedHours)
        }
        let debt = SleepScoreEngine.sleepDebt(shortfallsNewestFirst: shortfalls)
        let yesterdayStrain = historyNewestFirst.first?.dayStrain ?? 0

        let input = SleepInput(
            asleepSeconds: asleepSeconds,
            timeInBedSeconds: timeInBed,
            deepSeconds: deep,
            remSeconds: rem,
            coreSeconds: core,
            awakeSeconds: awake,
            hasStageData: segments.hasStageDetail,
            midpointMinutesFromLocalMidnight: midpointMinutes ?? 0,
            midpointBaselineMinutes: midpointMinutes == nil ? nil : midpointBaseline,
            baselineNeedHours: profile.baselineSleepNeedHours,
            yesterdayStrain: yesterdayStrain,
            sleepDebtHours: debt,
            napCreditHours: napCredit
        )

        return SleepContext(
            input: input,
            sleepStart: sleepStart,
            wakeTime: wakeTime,
            asleepSeconds: asleepSeconds,
            deepSeconds: deep,
            remSeconds: rem,
            coreSeconds: core,
            awakeSeconds: awake,
            timeInBedSeconds: timeInBed,
            midpointMinutes: midpointMinutes,
            napSeconds: napSeconds,
            hasOverlappingSegments: segments.hasOverlappingSegments
        )
    }

    private func makeRecoveryInput(
        overnight: OvernightData,
        baselines: [MetricKind: BaselineSnapshot],
        sleepOutput: SleepOutput
    ) -> RecoveryInput {
        func observation(_ metric: MetricKind) -> MetricObservation? {
            guard let value = overnight.value(for: metric),
                  let state = baselines[metric] else { return nil }
            return MetricObservation(
                value: value,
                baseline: BaselineEngine.scoringBaseline(from: state)
            )
        }
        return RecoveryInput(
            heartRateVariability: observation(.heartRateVariability),
            restingHeartRate: observation(.restingHeartRate),
            wristTemperature: observation(.wristTemperature),
            respiratoryRate: observation(.respiratoryRate),
            sleepScore: sleepOutput.score,
            hasOvernightData: !overnight.isEmpty,
            sleepWasImplausible: sleepOutput.validity == .tooShort || sleepOutput.validity == .tooLong
        )
    }

    private func computeStrain(
        dayWindow: DayWindow,
        profile: UserProfileSnapshot,
        baselines: [MetricKind: BaselineSnapshot],
        overnight: OvernightData,
        recoveryScore: Double?,
        now: Date,
        calendar: Calendar
    ) async throws -> StrainOutput? {
        let samples = try await health.fetchIntradayHeartRates(in: dayWindow.interval)
        guard !samples.isEmpty else { return nil }

        // The RHR baseline is the denominator's floor, so the personal baseline is preferred
        // over a single night's reading, which is noisier.
        let restingHeartRate = baselines[.restingHeartRate]?.mean
            ?? overnight.restingHeartRate
            ?? MetricKind.restingHeartRate.prior.mean

        let observed = try? await health.fetchObservedMaxHeartRate(
            lookbackDays: EngineConstants.Strain.observedMaxLookbackDays,
            now: now,
            calendar: calendar
        )
        let age = profile.characteristics.age(at: now, calendar: calendar)
        let resolved = StrainEngine.resolveMaxHeartRate(
            override: profile.maxHeartRateOverride,
            observed: observed ?? nil,
            age: age
        )
        if resolved.source == .tanakaAssumedAge {
            ZenithiumLog.engine.notice(
                "ASSUMPTION HRMAX-1: no date of birth available, assuming age \(EngineConstants.Strain.assumedAgeYears, privacy: .public)"
            )
        }

        let anchor = try await store.strainAnchor(for: dayWindow.dayStart)
        let previous = try await store.dayRecord(for: dayWindow.dayStart)?.dayStrain

        return StrainEngine.compute(
            StrainInput(
                samples: samples,
                dayWindow: dayWindow,
                restingHeartRate: restingHeartRate,
                maxHeartRate: resolved.value,
                maxHeartRateSource: resolved.source,
                biologicalSex: profile.biologicalSex,
                anchor: anchor,
                previouslyReportedStrain: previous,
                recoveryScore: recoveryScore
            )
        )
    }

    /// ASSUMPTION MUSCLE-4: a workout's TRIMP is re-integrated from the intraday series over
    /// its own interval — one bounded query per workout — rather than apportioned from the
    /// daily total. A session's load then does not change when the rest of the day does.
    private func projectFatigue(
        now: Date,
        calendar: Calendar,
        resolver: DayWindowResolver,
        profile: UserProfileSnapshot,
        baselines: [MetricKind: BaselineSnapshot],
        sleepScore: Double?
    ) async throws -> [MuscleGroup: MuscleReadiness] {
        let windowStart = resolver.day(
            byAdding: -EngineConstants.Fatigue.projectionWindowDays,
            to: calendar.startOfDay(for: now)
        )
        let window = DateInterval(start: windowStart, end: max(windowStart, now))

        let restingHeartRate = baselines[.restingHeartRate]?.mean
            ?? MetricKind.restingHeartRate.prior.mean
        let age = profile.characteristics.age(at: now, calendar: calendar)
        let resolved = StrainEngine.resolveMaxHeartRate(
            override: profile.maxHeartRateOverride,
            observed: nil,
            age: age
        )

        var impacts: [MuscleSessionImpact] = []

        let workouts = (try? await health.fetchWorkouts(in: window)) ?? []
        for workout in workouts {
            try Task.checkCancellation()
            guard MuscleInvolvementMatrix.contributesMuscleImpact(workout.activity) else {
                // ASSUMPTION MUSCLE-2 — strength types add no muscle impact from HealthKit,
                // though their TRIMP still counts toward daily strain.
                continue
            }
            let samples = (try? await health.fetchIntradayHeartRates(in: workout.interval)) ?? []
            let sessionTRIMP = StrainEngine.trimp(
                for: workout.interval,
                samples: samples,
                restingHeartRate: restingHeartRate,
                maxHeartRate: resolved.value,
                biologicalSex: profile.biologicalSex
            )
            guard sessionTRIMP > 0 else { continue }
            impacts.append(
                FatigueEngine.impact(forWorkout: workout, sessionTRIMP: sessionTRIMP)
            )
        }

        let sessions = try await store.strengthSessions(from: window.start, through: window.end)
        for session in sessions {
            impacts.append(
                FatigueEngine.impact(
                    forStrengthSession: session.id,
                    pattern: session.pattern,
                    performedAt: session.performedAt,
                    entries: session.entries
                )
            )
        }

        return FatigueEngine.project(
            FatigueInput(
                sessions: impacts,
                sleepScore: sleepScore ?? Self.neutralSleepScore,
                now: now,
                projectionWindow: nil
            )
        )
    }

    // MARK: - Persistence assembly

    private func makeWrite(
        dayStart: Date,
        timeZoneIdentifier: String,
        now: Date,
        engineVersion: Int,
        overnight: OvernightData,
        sleepContext: SleepContext,
        sleepOutput: SleepOutput,
        recoveryOutput: RecoveryOutput,
        strainOutput: StrainOutput?,
        baselines: [MetricKind: BaselineSnapshot]
    ) -> DayRecordWrite {
        var write = DayRecordWrite(
            dayStart: dayStart,
            timeZoneIdentifier: timeZoneIdentifier,
            computedAt: now,
            engineVersion: engineVersion,
            clearsOvernightValues: overnight.isEmpty
        )

        write.heartRateVariability = overnight.heartRateVariability
        write.restingHeartRate = overnight.restingHeartRate
        write.respiratoryRate = overnight.respiratoryRate
        write.oxygenSaturation = overnight.oxygenSaturation

        // ASSUMPTION BASE-3 — the stored temperature field is the *delta* against the
        // personal baseline, derived here rather than taken from HealthKit.
        if let temperature = overnight.wristTemperature,
           let baseline = baselines[.wristTemperature] {
            write.wristTemperatureDelta = temperature - baseline.mean
        }

        write.recoveryScore = recoveryOutput.score
        write.recoveryConfidence = recoveryOutput.confidence
        write.recoveryZTotal = recoveryOutput.zTotal

        if let strainOutput {
            write.dayStrain = strainOutput.strain
            write.trimp = strainOutput.trimp
            write.strainAnchorTRIMP = strainOutput.anchor.trimp
            write.strainAnchorThrough = strainOutput.anchor.throughTimestamp
            write.zoneSeconds = strainOutput.zoneSeconds
            write.maxHeartRateUsed = strainOutput.maxHeartRateUsed
        }
        write.targetCeiling = recoveryOutput.targetStrainCeiling

        write.sleepDurationSeconds = sleepContext.asleepSeconds
        write.sleepScore = sleepOutput.score
        write.deepSeconds = sleepContext.deepSeconds
        write.remSeconds = sleepContext.remSeconds
        write.coreSeconds = sleepContext.coreSeconds
        write.awakeSeconds = sleepContext.awakeSeconds
        write.timeInBedSeconds = sleepContext.timeInBedSeconds
        write.sleepMidpointMinutes = sleepContext.midpointMinutes
        write.sleepStart = sleepContext.sleepStart
        write.wakeTime = sleepContext.wakeTime
        write.napSeconds = sleepContext.napSeconds
        var reasons = overnight.missingMetricReasons
        if sleepContext.timeInBedSeconds > 0 {
            let rawEfficiency = sleepContext.asleepSeconds / sleepContext.timeInBedSeconds
            write.sleepEfficiency = min(rawEfficiency, 1.0)
            if rawEfficiency > 1.0 || sleepContext.hasOverlappingSegments {
                reasons.append(.overlappingSleepRecords)
            }
        }

        if let validityReason = sleepOutput.validity.dataQualityReason {
            reasons.append(validityReason)
        }
        if recoveryOutput.confidence < 1, recoveryOutput.availability.isScored {
            reasons.append(.baselineStillCalibrating)
        }
        if let strainOutput, strainOutput.uncoveredSeconds > Self.sparseCoverageThreshold {
            reasons.append(.intradayHeartRateSparse)
        }
        write.dataQualityReasons = reasons
        write.dataQuality = DataQuality.verdict(for: reasons)

        return write
    }

    /// Refreshes the widget snapshot with a real three-day trend read from the store.
    ///
    /// Kept separate from the pass so the write can happen once the record for today is
    /// committed, and so a failure here never fails a recalculation the user is waiting on.
    func refreshWidgetTrend(now: Date, result: RecalculationResult? = nil) async {
        // The outcome is deliberately dropped here: a widget that failed to redraw must
        // never fail a recalculation the user is waiting on. Callers that do want to know
        // — tests, and the background scheduler deciding whether a wake earned anything —
        // call `publishWidgetSnapshot` directly.
        _ = await publishWidgetSnapshot(now: now, result: result)
    }

    /// Builds today's snapshot, writes it, and reloads the widgets if anything they draw
    /// actually moved.
    ///
    /// Until v4 the writing was the whole hop, and nothing ever told WidgetKit. A widget
    /// kept drawing the previous morning's score off a file that had already been replaced.
    @discardableResult
    func publishWidgetSnapshot(now: Date, result: RecalculationResult? = nil) async -> WidgetRefreshPublisher.Outcome {
        let calendar = calendarProvider()
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -2, to: today) else { return .noData }
        guard let records = try? await store.dayRecords(from: start, through: today),
              let latest = records.last else { return .noData }
        let trend = records.map {
            WidgetTrendPoint(
                dayStart: $0.dayStart,
                recoveryScore: $0.recoveryScore,
                dayStrain: $0.dayStrain,
                sleepScore: $0.sleepScore
            )
        }
        // The prescription is built here rather than on the watch, so every surface shows
        // the same suggestion. It needs the pass's own outputs, which is why the result is
        // handed in — a snapshot refresh triggered from anywhere else simply carries none.
        let prescriptionLine = result.flatMap {
            Self.prescriptionLine(result: $0, records: records, now: now)
        }
        let snapshot = WidgetSnapshot(
            formatVersion: WidgetSnapshot.currentFormatVersion,
            generatedAt: now,
            recoveryScore: latest.recoveryScore,
            recoveryBandRawValue: latest.recoveryBand?.rawValue,
            dayStrain: latest.dayStrain,
            targetCeiling: latest.targetCeiling,
            sleepScore: latest.sleepScore,
            isCalibrating: latest.recoveryScore == nil,
            calibrationProgress: latest.recoveryConfidence,
            trend: trend,
            prescriptionLine: prescriptionLine
        )
        return widgets.publish(snapshot)
    }

    /// One line describing today's session, for the snapshot.
    ///
    /// Deliberately terse: it is read on a watch face and in a control, where a sentence
    /// does not fit and a paragraph is unreadable.
    private static func prescriptionLine(
        result: RecalculationResult,
        records: [BiometricDaySnapshot],
        now: Date
    ) -> String? {
        // Three days of history is not enough for a load ratio, and the engine says so by
        // returning nil for it — which is the right answer here rather than a wrong number.
        let load = records.count >= EngineConstants.TrainingLoad.chronicWindowDays
            ? TrainingLoadEngine.analyse(
                TrainingLoadInput(
                    days: records.map { DailyLoad(dayStart: $0.dayStart, load: $0.dayStrain) },
                    referenceDay: now
                )
            )
            : nil

        guard let prescription = PrescriptionEngine.prescribe(
            recovery: result.recovery,
            lens: result.profile.trainingLens,
            load: load,
            muscles: Array(result.muscle.values),
            strainSoFar: result.strain?.strain ?? 0,
            biologicalSex: result.profile.biologicalSex,
            criticalSpeed: nil,
            circadian: result.circadian
        ) else { return nil }

        let session = prescription.primary
        guard session.kind != .rest else { return "Bugün dinlenme" }
        return "\(session.minutes) dk \(session.kind.displayName.lowercased())"
    }

    // MARK: - Constants

    /// The sleep score used when a night could not be scored.
    ///
    /// 100 would make fatigue clear at the fastest rate the model allows and 0 at the slowest;
    /// the value that yields a 1.0× half-life modifier is the only one that neither
    /// accelerates nor stalls recovery on a night Zenithium knows nothing about.
    /// `1.35 − 0.006·x = 1.0` → `x = 58.33`.
    static let neutralSleepScore: Double = (
        EngineConstants.Fatigue.sleepModifierIntercept - 1.0
    ) / EngineConstants.Fatigue.sleepModifierSlope

    /// Uncovered time past which the day is flagged as sparsely covered: two hours.
    private static let sparseCoverageThreshold: Double = 2 * 3600
}
