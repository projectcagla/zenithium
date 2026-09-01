//
//  DataQualityEngineTests.swift
//  ZenithiumTests
//
//  Tests for DataQualityEngine, wear coverage, sensor completeness,
//  and adversarial baseline maturity tiers.
//

import Foundation
import Testing
@testable import Zenithium

@Suite("Data quality and baseline calibration engine")
struct DataQualityEngineTests {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    @Test("Cold start baseline (0-3 days) applies high confidence attenuation")
    func coldStartTierAttenuation() {
        let cal0 = CalibrationState(recordedDaysCount: 0)
        #expect(cal0.tier == .coldStart)
        #expect(cal0.tier.confidenceMultiplier == 0.30)

        let cal3 = CalibrationState(recordedDaysCount: 3)
        #expect(cal3.tier == .coldStart)

        let cal7 = CalibrationState(recordedDaysCount: 7)
        #expect(cal7.tier == .developing)
        #expect(cal7.tier.confidenceMultiplier == 0.60)

        let cal14 = CalibrationState(recordedDaysCount: 14)
        #expect(cal14.tier == .established)
        #expect(cal14.tier.confidenceMultiplier == 0.85)

        let cal30 = CalibrationState(recordedDaysCount: 30)
        #expect(cal30.tier == .robust)
        #expect(cal30.tier.confidenceMultiplier == 1.00)
    }

    @Test("Night without HRV or RHR is flagged unusable for recovery")
    func missingOvernightBiometrics() {
        let cal = CalibrationState(recordedDaysCount: 14)
        let emptyOvernight = OvernightData(
            night: DateInterval(start: now.addingTimeInterval(-8 * 3600), duration: 8 * 3600),
            heartRateVariability: nil,
            restingHeartRate: nil,
            wristTemperature: nil,
            respiratoryRate: nil
        )

        let assessment = DataQualityEngine.assess(
            overnight: emptyOvernight,
            sleepSegments: [],
            daySamples: [],
            calibration: cal
        )

        #expect(!assessment.isUsableForRecovery)
        #expect(assessment.grade == .unusable)
        #expect(assessment.missingSensors.contains("Gece HRV (Kalp Hızı Değişkenliği)"))
        #expect(assessment.missingSensors.contains("Dinlenik Kalp Hızı (RHR)"))
    }

    @Test("Full overnight wear with HRV and RHR achieves excellent quality")
    func fullOvernightWear() {
        let cal = CalibrationState(recordedDaysCount: 30)
        let goodOvernight = OvernightData(
            night: DateInterval(start: now.addingTimeInterval(-8 * 3600), duration: 8 * 3600),
            heartRateVariability: 62.0,
            restingHeartRate: 52.0,
            wristTemperature: 0.1,
            respiratoryRate: 14.5
        )

        let sleepStart = now.addingTimeInterval(-8 * 3600)
        let segments = [
            SleepSegment(
                interval: DateInterval(start: sleepStart, duration: 2 * 3600),
                stage: .asleepDeep,
                sourceBundleIdentifier: "com.apple.health",
                timeZoneIdentifier: "UTC"
            ),
            SleepSegment(
                interval: DateInterval(start: sleepStart.addingTimeInterval(2 * 3600), duration: 2 * 3600),
                stage: .asleepREM,
                sourceBundleIdentifier: "com.apple.health",
                timeZoneIdentifier: "UTC"
            ),
            SleepSegment(
                interval: DateInterval(start: sleepStart.addingTimeInterval(4 * 3600), duration: 3.5 * 3600),
                stage: .asleepCore,
                sourceBundleIdentifier: "com.apple.health",
                timeZoneIdentifier: "UTC"
            )
        ]

        let assessment = DataQualityEngine.assess(
            overnight: goodOvernight,
            sleepSegments: segments,
            daySamples: [],
            calibration: cal
        )

        #expect(assessment.isUsableForRecovery)
        #expect(assessment.grade == DataQualityAssessment.Grade.excellent)
        #expect(assessment.nocturnalWearHours >= 7.0)
        #expect(assessment.missingSensors.isEmpty)
    }
}
