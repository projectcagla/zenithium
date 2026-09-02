//
//  TodayViewModel.swift
//  Zenithium
//
//  The Today screen: how recovered am I. Spec §1, §10.
//

import Foundation
import Observation

@MainActor
@Observable
final class TodayViewModel {

    /// Everything the Today screen renders. Assembled once, so the view computes nothing.
    struct Content: Sendable, Equatable {
        let recovery: RecoveryOutput
        let record: BiometricDaySnapshot
        let circadian: CircadianArc?
        let strain: StrainOutput?
        let profile: UserProfileSnapshot

        /// §12 copy, resolved here so no view can invent it.
        let headline: String
        let guidance: String
        let driverSentence: String

        var score: Double { recovery.score ?? 0 }
        var band: RecoveryBand { recovery.band ?? .yellow }
        var ceiling: Double? { recovery.targetStrainCeiling }
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isRefreshing = false

    /// The narrated briefing. `nil` until the first pass has produced one; the card is
    /// simply absent until then rather than showing a placeholder.
    private(set) var briefing: Briefing?

    /// Today's suggestion (Faz 19), and where it sits in a plan (Faz 20). Both arrive with
    /// the briefing rather than with the score, because both depend on reads the recovery
    /// pipeline does not make.
    private(set) var prescription: Prescription?
    private(set) var planPosition: PlanPosition?

    /// Epistemic decision trace synthesized by DecisionEngine (Epistemic Layer).
    private(set) var athleticDecision: EngineResult<AthleticDecision>?

    /// Evidence-backed recommendations (Faz 34 Bölüm B).
    private(set) var recommendations: [Recommendation] = []

    private let coordinator: any RecalculationDriving
    private let health: any HealthAuthorizing
    private let nowProvider: @Sendable () -> Date
    private var observationTask: Task<Void, Never>?
    private var briefingTask: Task<Void, Never>?

    /// Writes the briefing. `AdaptiveNarrator` by default, which uses the on-device model
    /// when there is one and the deterministic narrator otherwise.
    private let narrator: any IntelligenceProviding

    /// Read for the correlation and laboratory lines in the briefing.
    private let journal: (any JournalRepository)?
    private let bloodMarkers: (any BloodMarkerRepository)?
    private let records: (any BiometricDayRepository)?
    private let sessions: (any StrengthSessionRepository)?

    /// Read only when the profile has cycle awareness switched on (Faz 12).
    private let cycleSource: (any HealthDataProviding)?

    /// The goal being worked towards, if any (Faz 20).
    private let goals: (any GoalEventRepository)?

    /// Fits the critical-speed model so an endurance prescription can name a pace band
    /// rather than only a duration.
    private let workoutSource: (any HealthDataProviding)?

    init(
        coordinator: any RecalculationDriving,
        health: any HealthAuthorizing,
        narrator: any IntelligenceProviding = AdaptiveNarrator(),
        journal: (any JournalRepository)? = nil,
        bloodMarkers: (any BloodMarkerRepository)? = nil,
        records: (any BiometricDayRepository)? = nil,
        sessions: (any StrengthSessionRepository)? = nil,
        cycleSource: (any HealthDataProviding)? = nil,
        goals: (any GoalEventRepository)? = nil,
        workoutSource: (any HealthDataProviding)? = nil,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.coordinator = coordinator
        self.health = health
        self.narrator = narrator
        self.journal = journal
        self.bloodMarkers = bloodMarkers
        self.records = records
        self.sessions = sessions
        self.cycleSource = cycleSource
        self.goals = goals
        self.workoutSource = workoutSource
        self.nowProvider = nowProvider
    }

    /// Stops observing. Called from the view's `.onDisappear`.
    ///
    /// This is an explicit method rather than a `deinit`: `deinit` is nonisolated, so reading
    /// a `@MainActor` stored property from it is a strict-concurrency error.
    func onDisappear() {
        observationTask?.cancel()
        observationTask = nil
        briefingTask?.cancel()
        briefingTask = nil
    }

    /// First load, plus subscription to background passes.
    func onAppear() async {
        if state.isLoading {
            await refresh()
        }
        startObserving()
    }

    /// Re-runs the pipeline. Safe to call while one is already running — the coordinator is
    /// single-flight, so a rapid pull-to-refresh joins the pass instead of queueing another.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard await ensureAuthorized() else { return }
        do {
            let result = try await coordinator.recalculate(now: nowProvider())
            apply(result)
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    /// Requests Health access from the gate, then loads.
    func requestAuthorization() async {
        do {
            try await health.requestAuthorization()
            state = .loading
            await refresh()
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    private func startObserving() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.coordinator.results()
            for await result in stream {
                guard !Task.isCancelled else { return }
                self.apply(result)
            }
        }
    }

    private func ensureAuthorized() async -> Bool {
        guard await health.isHealthDataAvailable() else {
            state = .needsAuthorization(.unavailable)
            return false
        }
        let report = await health.authorizationReport(now: nowProvider())
        guard report.overall.permitsReads else {
            state = .needsAuthorization(report.overall)
            return false
        }
        return true
    }

    private func apply(_ result: RecalculationResult) {
        switch result.recovery.availability {
        case .calibrating(let collected, let required):
            state = .calibrating(
                progress: BaselineEngine.calibrationProgress(sampleCount: collected),
                daysCollected: collected,
                daysRequired: required
            )

        case .unavailable(let reason):
            state = .noData(reason: .recoveryUnavailable(reason))

        case .scored:
            startBriefing(for: result)
            let band = result.recovery.band ?? .yellow
            state = .loaded(
                Content(
                    recovery: result.recovery,
                    record: result.record,
                    circadian: result.circadian,
                    strain: result.strain,
                    profile: result.profile,
                    headline: SafetyCopy.recoveryHeadline(for: band),
                    guidance: SafetyCopy.recoveryGuidance(for: band),
                    driverSentence: SafetyCopy.driverSentence(
                        positive: result.recovery.topPositiveSummary,
                        negative: result.recovery.topNegativeSummary
                    )
                )
            )
        }
    }
    // MARK: - Briefing

    /// Build the narrated briefing off the critical path.
    ///
    /// Deliberately not awaited by `apply`: the recovery card must appear the moment the
    /// numbers exist, and the briefing — which may wait on a language model — arrives
    /// afterwards. A pass that lands while one is in flight replaces it.
    private func startBriefing(for result: RecalculationResult) {
        briefingTask?.cancel()
        briefingTask = Task { [weak self] in
            guard let self else { return }
            let context = await self.briefingContext(for: result)
            guard !Task.isCancelled else { return }
            let written = await self.narrator.briefing(for: context)
            guard !Task.isCancelled else { return }
            self.briefing = written

            let plan = await self.nextPlanPosition(for: result)
            let suggestion = await self.suggestion(for: result, context: context)
            let decision = await self.synthesizeDecision(for: result, context: context)
            let recommendations = await self.synthesizeRecommendations(for: result, context: context)
            guard !Task.isCancelled else { return }
            self.planPosition = plan
            self.prescription = suggestion
            self.athleticDecision = decision
            self.recommendations = recommendations
        }
    }

    /// Synthesizes the deterministic evidence-backed recommendations.
    private func synthesizeRecommendations(
        for result: RecalculationResult,
        context: BriefingContext
    ) async -> [Recommendation] {
        var load: TrainingLoadOutput?
        var daysCount = 14
        var sleepDebtLedger: SleepDebtLedger?
        var socialJetlag: SocialJetlag?
        if let records {
            let window = context.date.addingTimeInterval(-120 * 86_400)
            if let days = try? await records.dayRecords(from: window, through: context.date) {
                daysCount = days.count
                load = TrainingLoadEngine.analyse(
                    TrainingLoadInput(
                        days: days.map { DailyLoad(dayStart: $0.dayStart, load: $0.dayStrain) },
                        referenceDay: context.date
                    )
                )
                sleepDebtLedger = SleepDebtEngine.ledger(
                    days: days,
                    needHours: 8.0,
                    now: context.date,
                    calendar: Calendar.autoupdatingCurrent
                )
                socialJetlag = SleepDebtEngine.socialJetlag(
                    days: days,
                    now: context.date,
                    calendar: Calendar.autoupdatingCurrent
                )
            }
        }

        let calibration = CalibrationState(recordedDaysCount: max(1, daysCount))
        let overnight = OvernightData(
            night: DateInterval(start: result.record.dayStart.addingTimeInterval(-8 * 3600), duration: 8 * 3600),
            heartRateVariability: result.record.heartRateVariability,
            restingHeartRate: result.record.restingHeartRate,
            wristTemperature: result.record.wristTemperatureDelta,
            respiratoryRate: result.record.respiratoryRate
        )

        let sleepStart = result.record.sleepStart ?? result.record.dayStart.addingTimeInterval(-8 * 3600)
        var sleepSegments: [SleepSegment] = []
        if result.record.deepSeconds > 0 {
            sleepSegments.append(SleepSegment(interval: DateInterval(start: sleepStart, duration: result.record.deepSeconds), stage: .asleepDeep, sourceBundleIdentifier: "com.apple.health", timeZoneIdentifier: result.record.timeZoneIdentifier))
        }
        if result.record.remSeconds > 0 {
            sleepSegments.append(SleepSegment(interval: DateInterval(start: sleepStart.addingTimeInterval(result.record.deepSeconds), duration: result.record.remSeconds), stage: .asleepREM, sourceBundleIdentifier: "com.apple.health", timeZoneIdentifier: result.record.timeZoneIdentifier))
        }
        if result.record.coreSeconds > 0 {
            sleepSegments.append(SleepSegment(interval: DateInterval(start: sleepStart.addingTimeInterval(result.record.deepSeconds + result.record.remSeconds), duration: result.record.coreSeconds), stage: .asleepCore, sourceBundleIdentifier: "com.apple.health", timeZoneIdentifier: result.record.timeZoneIdentifier))
        }

        let dataQuality = DataQualityEngine.assess(
            overnight: overnight,
            sleepSegments: sleepSegments,
            daySamples: [],
            calibration: calibration
        )

        let userAge: Int? = result.profile.dateOfBirth.flatMap {
            Calendar.autoupdatingCurrent.dateComponents([.year], from: $0, to: context.date).year
        }

        let sleepDebtHours = sleepDebtLedger?.hours
        let socialJetlagHours = socialJetlag?.hours
        let lastNightSleepHours = result.record.sleepDurationSeconds > 0 ? result.record.sleepDurationSeconds / 3600 : nil

        let input = RecommendationInput(
            now: context.date,
            recoveryScore: result.recovery.score,
            recoveryBand: result.recovery.band,
            sleepDebtHours: sleepDebtHours,
            lastNightSleepHours: lastNightSleepHours,
            acuteLoad: load?.acuteLoad,
            chronicLoad: load?.chronicLoad,
            acwr: load?.ratio,
            vo2MaxPercentile: nil,
            socialJetlagHours: socialJetlagHours,
            dataQuality: dataQuality,
            calibration: calibration,
            userAge: userAge,
            userSex: result.profile.biologicalSex,
            userStatus: .recreational,
            lens: result.profile.trainingLens
        )

        return RecommendationEngine.recommendations(input: input)
    }

    /// Synthesizes the deterministic athletic decision trace.
    private func synthesizeDecision(
        for result: RecalculationResult,
        context: BriefingContext
    ) async -> EngineResult<AthleticDecision>? {
        var load: TrainingLoadOutput?
        var daysCount = 14
        if let records {
            let window = context.date.addingTimeInterval(-120 * 86_400)
            if let days = try? await records.dayRecords(from: window, through: context.date) {
                daysCount = days.count
                load = TrainingLoadEngine.analyse(
                    TrainingLoadInput(
                        days: days.map { DailyLoad(dayStart: $0.dayStart, load: $0.dayStrain) },
                        referenceDay: context.date
                    )
                )
            }
        }

        let calibration = CalibrationState(recordedDaysCount: max(1, daysCount))
        let overnight = OvernightData(
            night: DateInterval(start: result.record.dayStart.addingTimeInterval(-8 * 3600), duration: 8 * 3600),
            heartRateVariability: result.record.heartRateVariability,
            restingHeartRate: result.record.restingHeartRate,
            wristTemperature: result.record.wristTemperatureDelta,
            respiratoryRate: result.record.respiratoryRate
        )

        let sleepStart = result.record.sleepStart ?? result.record.dayStart.addingTimeInterval(-8 * 3600)
        var sleepSegments: [SleepSegment] = []
        if result.record.deepSeconds > 0 {
            sleepSegments.append(SleepSegment(interval: DateInterval(start: sleepStart, duration: result.record.deepSeconds), stage: .asleepDeep, sourceBundleIdentifier: "com.apple.health", timeZoneIdentifier: result.record.timeZoneIdentifier))
        }
        if result.record.remSeconds > 0 {
            sleepSegments.append(SleepSegment(interval: DateInterval(start: sleepStart.addingTimeInterval(result.record.deepSeconds), duration: result.record.remSeconds), stage: .asleepREM, sourceBundleIdentifier: "com.apple.health", timeZoneIdentifier: result.record.timeZoneIdentifier))
        }
        if result.record.coreSeconds > 0 {
            sleepSegments.append(SleepSegment(interval: DateInterval(start: sleepStart.addingTimeInterval(result.record.deepSeconds + result.record.remSeconds), duration: result.record.coreSeconds), stage: .asleepCore, sourceBundleIdentifier: "com.apple.health", timeZoneIdentifier: result.record.timeZoneIdentifier))
        }

        let dataQuality = DataQualityEngine.assess(
            overnight: overnight,
            sleepSegments: sleepSegments,
            daySamples: [],
            calibration: calibration
        )

        var markers: [BloodMarkerSnapshot] = []
        if let bloodMarkers {
            markers = (try? await bloodMarkers.bloodMarkers()) ?? []
        }
        var ecgRecords: [ECGRecord] = []
        if let workoutSource {
            ecgRecords = (try? await workoutSource.fetchECGRecords(days: 30, now: nowProvider())) ?? []
        }
        let disabledIDs = ClinicalModifierRegistry.disabledModifierIDs()
        let clinicalContext = ClinicalContextEngine.assess(
            markers: markers,
            ecgRecords: ecgRecords,
            disabledModifierIDs: disabledIDs,
            sex: result.profile.biologicalSex,
            now: nowProvider()
        )

        let input = DecisionInput(
            recoveryScore: result.recovery.score,
            recoveryBand: result.recovery.band,
            sleepScore: result.record.sleepScore,
            acuteLoad: load?.acuteLoad,
            chronicLoad: load?.chronicLoad,
            acwr: load?.ratio,
            muscleReadiness: result.muscle,
            dataQuality: dataQuality,
            calibration: calibration,
            lens: result.profile.trainingLens,
            clinical: clinicalContext
        )

        return DecisionEngine.decide(input: input)
    }

    /// Today's prescription.
    ///
    /// Built from the same context the narrator saw, plus the load reading and the muscle
    /// map — so the sentence at the top of the screen and the session below it cannot
    /// disagree about what kind of day this is.
    private func suggestion(
        for result: RecalculationResult,
        context: BriefingContext
    ) async -> Prescription? {
        var load: TrainingLoadOutput?
        if let records {
            let window = context.date.addingTimeInterval(-120 * 86_400)
            if let days = try? await records.dayRecords(from: window, through: context.date) {
                load = TrainingLoadEngine.analyse(
                    TrainingLoadInput(
                        days: days.map { DailyLoad(dayStart: $0.dayStart, load: $0.dayStrain) },
                        referenceDay: context.date
                    )
                )
            }
        }

        return PrescriptionEngine.prescribe(
            recovery: result.recovery,
            lens: result.profile.trainingLens,
            load: load,
            muscles: Array(result.muscle.values),
            strainSoFar: result.strain?.strain ?? 0,
            biologicalSex: result.profile.biologicalSex,
            criticalSpeed: await criticalSpeedModel(now: context.date),
            circadian: result.circadian,
            // The narrator already read the phase; the prescription reads the same one, so
            // the sentence at the top of the screen and the session below it cannot
            // disagree about which phase this is. Yol haritası v4, C6.
            cycle: context.cyclePhase.map {
                CycleContext(
                    estimate: $0,
                    phaseBaselineHRV: context.cyclePhaseHRVMean,
                    todayHRV: result.record.heartRateVariability
                )
            }
        )
    }

    /// The critical-speed fit, when there are enough runs for one.
    ///
    /// Only used to attach a pace band to a prescribed session. A failure here costs the
    /// band and nothing else, so it is a silent optional rather than an error path.
    private func criticalSpeedModel(now: Date) async -> CriticalSpeedModel? {
        guard let workoutSource else { return nil }
        let window = now.addingTimeInterval(-Double(EnduranceEngine.effortWindowDays) * 86_400)
        guard let workouts = try? await workoutSource.fetchWorkouts(
            in: DateInterval(start: window, end: now)
        ) else { return nil }

        let runs = workouts.filter { $0.activity == .running }
        guard !runs.isEmpty else { return nil }
        return EnduranceEngine.fit(efforts: EnduranceViewModel.efforts(from: runs), now: now)
    }

    /// Where today sits relative to the next goal.
    ///
    /// Named apart from the `planPosition` property on purpose — a stored property and a
    /// method cannot share a name, and the pair reads clearly enough this way.
    private func nextPlanPosition(for result: RecalculationResult) async -> PlanPosition? {
        guard let goals else { return nil }
        let lookup = try? await goals.nextGoalEvent(onOrAfter: result.dayStart)
        guard let next = lookup ?? nil else { return nil }
        return PlanEngine.position(
            on: result.dayStart,
            event: next.event,
            planStart: next.planStart,
            calendar: Calendar.autoupdatingCurrent
        )
    }

    /// Gather everything the narrator gets to see.
    ///
    /// Every optional source is allowed to fail silently. A briefing missing its laboratory
    /// line is still a good briefing; a briefing that never appears because one repository
    /// threw is not.
    private func briefingContext(for result: RecalculationResult) async -> BriefingContext {
        let now = nowProvider()

        var correlations: [CorrelationResult] = []
        if let journal {
            correlations = (try? await Self.correlations(from: journal, records: records, now: now)) ?? []
        }

        var labObservations: [LabObservation] = []
        if let bloodMarkers, let markers = try? await bloodMarkers.bloodMarkers(), !markers.isEmpty {
            var sessionDates: [Date] = []
            if let earliest = markers.map(\.drawnAt).min(), let latest = markers.map(\.drawnAt).max() {
                let start = earliest.addingTimeInterval(-Double(LabInsightEngine.trainingSensitiveWindowHours) * 3600)
                let end = latest.addingTimeInterval(3600)
                if let workoutSource, let workouts = try? await workoutSource.fetchWorkouts(in: DateInterval(start: start, end: end)) {
                    sessionDates.append(contentsOf: workouts.map(\.interval.start))
                }
                if let sessions, let logged = try? await sessions.strengthSessions(from: start, through: end) {
                    sessionDates.append(contentsOf: logged.map(\.performedAt))
                }
            }
            labObservations = LabInsightEngine.observations(
                markers: markers,
                sex: result.profile.biologicalSex,
                sessionDates: sessionDates,
                now: now
            )
        }

        var recentScores: [Double] = []
        var previousStrain: Double?
        if let records {
            let window = now.addingTimeInterval(-7 * 86_400)
            if let days = try? await records.dayRecords(from: window, through: now) {
                let sorted = days.sorted { $0.dayStart < $1.dayStart }
                // Today's own record is excluded from the comparison mean; comparing a
                // number against an average that contains it flattens exactly the movement
                // the sentence is meant to report.
                let earlier = sorted.filter { $0.dayStart < result.dayStart }
                recentScores = earlier.compactMap(\.recoveryScore)
                previousStrain = earlier.last?.dayStrain
            }
        }

        let cycle = await cycleReading(for: result, now: now)

        return BriefingContext(
            date: now,
            lens: result.profile.trainingLens,
            recovery: result.recovery,
            sleep: result.sleep,
            previousStrain: previousStrain,
            currentStrain: result.strain?.strain,
            muscles: Array(result.muscle.values).sorted { $0.readiness < $1.readiness },
            correlations: correlations,
            labObservations: labObservations,
            recentRecoveryScores: recentScores,
            cyclePhase: cycle.phase,
            cyclePhaseHRVMean: cycle.hrvMean
        )
    }

    /// Today's cycle phase and the user's own HRV mean within it.
    ///
    /// Returns nothing at all unless the profile has cycle awareness switched on. It is
    /// never inferred from biological sex — reading menstrual data because somebody selected
    /// "female" would be the app deciding something about a person instead of them.
    private func cycleReading(
        for result: RecalculationResult,
        now: Date
    ) async -> (phase: CyclePhaseEstimate?, hrvMean: Double?) {
        guard result.profile.tracksMenstrualCycle, let cycleSource else { return (nil, nil) }

        let calendar = Calendar.autoupdatingCurrent
        guard let flowDays = try? await cycleSource.fetchMenstrualFlowDays(
            days: CycleEngine.historyWindowDays,
            now: now,
            calendar: calendar
        ), !flowDays.isEmpty else { return (nil, nil) }

        guard let phase = CycleEngine.phase(on: now, flowDays: flowDays, calendar: calendar) else {
            return (nil, nil)
        }

        // The phase-aware mean needs a long HRV history, and it is only used when the phase
        // itself is confident — scoring against the wrong phase is worse than pooling.
        guard phase.isConfident, let records else { return (phase, nil) }
        let window = now.addingTimeInterval(-Double(CycleEngine.historyWindowDays) * 86_400)
        guard let days = try? await records.dayRecords(from: window, through: now) else {
            return (phase, nil)
        }

        let values = days.compactMap { day -> (day: Date, value: Double)? in
            guard let hrv = day.heartRateVariability else { return nil }
            return (day.dayStart, hrv)
        }
        let partitioned = CycleEngine.partition(values: values, flowDays: flowDays, calendar: calendar)
        let baseline = CycleEngine.phaseBaseline(for: phase.phase.baselineGroup, partitioned: partitioned)
        return (phase, baseline?.mean)
    }

    /// Rank the journal correlations.
    ///
    /// Reuses `JournalViewModel.buildInsights` rather than restating the pairing rules —
    /// which day a behaviour belongs to, and why an unlogged day is not a control — so the
    /// briefing can never disagree with the Journal screen about the same data.
    private static func correlations(
        from journal: any JournalRepository,
        records: (any BiometricDayRepository)?,
        now: Date
    ) async throws -> [CorrelationResult] {
        guard let records else { return [] }
        let start = now.addingTimeInterval(-90 * 86_400)
        let days = try await journal.journalDays(from: start, through: now)
        guard !days.isEmpty else { return [] }
        let biometrics = try await records.dayRecords(from: start, through: now)
        return JournalViewModel.buildInsights(
            outcome: .recovery,
            logs: days,
            records: biometrics,
            calendar: Calendar.autoupdatingCurrent
        )
    }
}