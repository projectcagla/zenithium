import Foundation

struct DailyDecisionContext: Sendable {
    let decision: EngineResult<AthleticDecision>
    let load: TrainingLoadOutput?
    let preferences: PersonalPreferences
}

/// One input path for the phone, widgets, and Watch. All surfaces honor the same context,
/// load history, preference and clinical limitations.
actor DailyDecisionCoordinator {
    private let records: (any BiometricDayRepository)?
    private let markers: (any BloodMarkerRepository)?
    private let health: (any HealthDataProviding)?
    init(records: (any BiometricDayRepository)?, markers: (any BloodMarkerRepository)?, health: (any HealthDataProviding)?) {
        self.records = records
        self.markers = markers
        self.health = health
    }

    func evaluate(_ result: RecalculationResult, preferences: PersonalPreferences) async throws -> DailyDecisionContext {
        let now = result.computedAt
        var load: TrainingLoadOutput?
        if let records {
            let days = try await records.dayRecords(from: now.addingTimeInterval(-120 * 86_400), through: now)
            load = TrainingLoadEngine.analyse(TrainingLoadInput(days: days.compactMap(\.recordedTrainingLoad), referenceDay: now))
        }
        let blood = try await markers?.bloodMarkers() ?? []
        let ecg = try await health?.fetchECGRecords(days: 30, now: now) ?? []
        let clinical = ClinicalContextEngine.assess(markers: blood, ecgRecords: ecg,
            disabledModifierIDs: preferences.disabledClinicalModifierIDs, sex: result.profile.biologicalSex, now: now)
        let decision = DecisionEngine.decide(input: DecisionInput(recoveryScore: result.recovery.score,
            recoveryBand: result.recovery.band, sleepScore: result.record.sleepScore, acuteLoad: load?.acuteLoad,
            chronicLoad: load?.chronicLoad, acwr: load?.ratio, muscleReadiness: result.muscle,
            dataQuality: result.dataQuality, calibration: result.calibration, lens: result.profile.trainingLens,
            clinical: clinical, preference: preferences.decision, evaluatedAt: now, personalContexts: preferences.contexts))
        return DailyDecisionContext(decision: decision, load: load, preferences: preferences)
    }
}
