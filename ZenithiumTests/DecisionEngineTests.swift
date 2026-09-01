//
//  DecisionEngineTests.swift
//  ZenithiumTests
//
//  Tests for DecisionEngine, evidence graph, deterministic decision trace,
//  and scientific limitation disclosures.
//

import Foundation
import Testing
@testable import Zenithium

@Suite("Athletic decision engine and trace synthesis")
struct DecisionEngineTests {

    @Test("Cold start returns calibrate action with non-blocking limitation")
    func coldStartRequiresCalibration() {
        let cal = CalibrationState(recordedDaysCount: 2)
        let dq = DataQualityAssessment(
            grade: .degraded,
            wearHours: 6.0,
            nocturnalWearHours: 6.0,
            hasNocturnalHRV: true,
            hasNocturnalRHR: true,
            hasWristTemperature: false,
            hasSleepStages: true,
            confidenceFactor: 0.30,
            missingSensors: ["Bilek Sıcaklığı"],
            qualityIssues: []
        )

        let input = DecisionInput(
            recoveryScore: 75.0,
            recoveryBand: .green,
            sleepScore: 80.0,
            dataQuality: dq,
            calibration: cal
        )

        let result = DecisionEngine.decide(input: input)
        #expect(result.value.action == .calibrate)
        #expect(result.limitations.contains { $0.code == "COLD-START" })
        #expect(!result.calculationSteps.isEmpty)
    }

    @Test("Optimal recovery with mature baseline prescribes push with target strain")
    func optimalRecoveryPrescribesPush() {
        let cal = CalibrationState(recordedDaysCount: 30)
        let dq = DataQualityAssessment(
            grade: .excellent,
            wearHours: 20.0,
            nocturnalWearHours: 7.5,
            hasNocturnalHRV: true,
            hasNocturnalRHR: true,
            hasWristTemperature: true,
            hasSleepStages: true,
            confidenceFactor: 1.0,
            missingSensors: [],
            qualityIssues: []
        )

        let input = DecisionInput(
            recoveryScore: 88.0,
            recoveryBand: .green,
            sleepScore: 90.0,
            dataQuality: dq,
            calibration: cal
        )

        let result = DecisionEngine.decide(input: input)
        if case .push(let strain) = result.value.action {
            #expect(strain > 14.0)
        } else {
            Issue.record("Expected push action for 88% recovery")
        }

        #expect(result.isActionable)
        #expect(result.confidence.rating == .high)
        #expect(result.evidence.contains { $0.sourceCategory == "Toparlanma" })
        #expect(result.evidence.contains { $0.sourceCategory == "Uyku" })
        #expect(result.value.traceSteps.count >= 3)
    }

    @Test("Compromised recovery prescribes recover action")
    func compromisedRecoveryPrescribesRecover() {
        let cal = CalibrationState(recordedDaysCount: 30)
        let dq = DataQualityAssessment(
            grade: .excellent,
            wearHours: 20.0,
            nocturnalWearHours: 7.5,
            hasNocturnalHRV: true,
            hasNocturnalRHR: true,
            hasWristTemperature: true,
            hasSleepStages: true,
            confidenceFactor: 1.0,
            missingSensors: [],
            qualityIssues: []
        )

        let input = DecisionInput(
            recoveryScore: 28.0,
            recoveryBand: .red,
            sleepScore: 45.0,
            dataQuality: dq,
            calibration: cal
        )

        let result = DecisionEngine.decide(input: input)
        #expect(result.value.action == .recover)
        #expect(result.isActionable)
        #expect(result.value.suggestedActivities.contains(.walking))
    }
}
