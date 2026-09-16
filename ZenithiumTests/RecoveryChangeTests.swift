import Foundation
import Testing
@testable import Zenithium

@Suite("V1.1 score accounting and conservative prescriptions")
struct RecoveryChangeTests {
    private func output(hrv: Double, rhr: Double, temperature: Double? = nil) -> RecoveryOutput {
        func observation(_ metric: MetricKind, _ value: Double, _ mean: Double, _ deviation: Double) -> MetricObservation {
            MetricObservation(value: value, baseline: ScoringBaseline(metric: metric, mean: mean,
                standardDeviation: deviation, sampleCount: 30, confidence: 1, isScorable: true))
        }
        return RecoveryEngine.compute(RecoveryInput(
            heartRateVariability: observation(.heartRateVariability, hrv, 55, 8),
            restingHeartRate: observation(.restingHeartRate, rhr, 54, 3),
            wristTemperature: temperature.map { observation(.wristTemperature, $0, 34, 0.35) },
            respiratoryRate: nil, sleepScore: 80, hasOvernightData: true, sleepWasImplausible: false))
    }

    @Test("Opposing contributions and baseline changes sum to the observed score delta")
    func exactAccounting() throws {
        let old = output(hrv: 55, rhr: 54)
        let current = output(hrv: 62, rhr: 56)
        let recorded = try #require(old.score) - 4
        let change = try #require(RecoveryChangeEngine.compare(previousScore: recorded, previousOnCurrentBaseline: old, current: current))
        #expect(abs(change.contributions.reduce(0) { $0 + $1.points } + change.baselineAndModelPoints - change.delta) < 1e-9)
        #expect(abs(change.baselineAndModelPoints - 4) < 1e-8)
        #expect(change.contributions.first { $0.driver == .heartRateVariability }!.points > 0)
        #expect(change.contributions.first { $0.driver == .restingHeartRate }!.points < 0)
    }

    @Test("New measurement coverage is disclosed, unchanged scores have zero contributions")
    func coverageAndStability() throws {
        let before = output(hrv: 55, rhr: 54)
        let changed = try #require(RecoveryChangeEngine.compare(previousScore: before.score!, previousOnCurrentBaseline: before, current: output(hrv: 55, rhr: 54, temperature: 34.4)))
        #expect(changed.contributions.contains { $0.driver == .temperature && $0.coverageChanged })
        let same = try #require(RecoveryChangeEngine.compare(previousScore: before.score!, previousOnCurrentBaseline: before, current: before))
        #expect(same.delta == 0)
        #expect(same.contributions.allSatisfy { $0.points == 0 })
        #expect(RecoveryChangeEngine.compare(previousScore: .nan, previousOnCurrentBaseline: before, current: before) == nil)
    }

    @Test("Daily ceiling is respected in additive TRIMP space even with little remaining budget")
    func ceilingBudget() throws {
        let recovery = output(hrv: 70, rhr: 48)
        let ceiling = try #require(recovery.targetStrainCeiling)
        for used in [0.0, ceiling - 0.2, ceiling, ceiling + 1] {
            let prescription = try #require(PrescriptionEngine.prescribe(recovery: recovery, lens: .endurance,
                load: nil, muscles: [], strainSoFar: used, biologicalSex: .male,
                criticalSpeed: nil, circadian: nil, decision: .push(targetStrain: ceiling)))
            let added = StrainEngine.trimp(forStrain: prescription.primary.forecastStrain) ?? 0
            let remaining = max(0, (StrainEngine.trimp(forStrain: ceiling) ?? 0) - (StrainEngine.trimp(forStrain: used) ?? 0))
            #expect(added <= remaining * PrescriptionEngine.sessionShareOfCeiling + 1e-8)
        }
        let rest = try #require(PrescriptionEngine.prescribe(recovery: recovery, lens: .endurance,
            load: nil, muscles: [], strainSoFar: 0, biologicalSex: .male,
            criticalSpeed: nil, circadian: nil, decision: .recover))
        #expect(rest.ceiling == nil)
        #expect(rest.primary.kind == .rest || rest.primary.kind == .easyMovement)
    }

    @Test("Context starts and expires; future illness does not affect today's plan")
    func contextWindow() {
        let now = Date(timeIntervalSince1970: 1_780_300_800)
        let entry = PersonalContextEntry(kind: .illness, through: now.addingTimeInterval(100), note: "", startedAt: now)
        #expect(!entry.isActive(at: now.addingTimeInterval(-1)))
        #expect(entry.isActive(at: now))
        #expect(!entry.isActive(at: now.addingTimeInterval(101)))
    }

    @Test("Active illness changes decision and prescription without changing measured recovery")
    func contextDecisionAgreement() throws {
        let now = Date(timeIntervalSince1970: 1_780_300_800)
        let quality = DataQualityAssessment(grade: .excellent, wearHours: 8, nocturnalWearHours: 8,
            hasNocturnalHRV: true, hasNocturnalRHR: true, hasWristTemperature: true,
            hasSleepStages: true, confidenceFactor: 1, missingSensors: [], qualityIssues: [])
        let entry = PersonalContextEntry(kind: .illness, through: now.addingTimeInterval(100), note: "", startedAt: now)
        func decision(at date: Date) -> DecisionAction {
            DecisionEngine.decide(input: DecisionInput(recoveryScore: 88, recoveryBand: .green,
                sleepScore: 90, dataQuality: quality, calibration: CalibrationState(recordedDaysCount: 30),
                evaluatedAt: date, personalContexts: [entry])).value.action
        }
        #expect(decision(at: now) == .recover)
        if case .push = decision(at: now.addingTimeInterval(101)) {} else {
            Issue.record("Expired illness must no longer restrict the daily plan")
        }
        let measured = output(hrv: 70, rhr: 48)
        let prescription = try #require(PrescriptionEngine.prescribe(recovery: measured, lens: .endurance,
            load: nil, muscles: [], strainSoFar: 0, biologicalSex: .male,
            criticalSpeed: nil, circadian: nil, decision: decision(at: now)))
        #expect(prescription.ceiling == nil)
        #expect(prescription.primary.kind == .rest || prescription.primary.kind == .easyMovement)
        #expect(measured.score == output(hrv: 70, rhr: 48).score)
    }

    @Test("Generated prose cannot introduce numeric or written quantities")
    func noGeneratedQuantities() {
        for text in ["Skorun 82", "Üç saat dinlen", "Yüzde elli", "İki kat", "½ saat", "On puan", "İkişer gün", "Saatlik hedef"] {
            #expect(!NarrationGuard.containsNoQuantity(text))
        }
        #expect(NarrationGuard.containsNoQuantity("Bugünkü ritmini izle."))
    }
}
