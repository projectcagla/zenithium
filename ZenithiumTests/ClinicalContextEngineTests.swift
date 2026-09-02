//
//  ClinicalContextEngineTests.swift
//  ZenithiumTests
//
//  Tests for ClinicalContext, ClinicalModifierRegistry, and ClinicalContextEngine. Spec §12 (Faz 33).
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Clinical Context Engine")
struct ClinicalContextEngineTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10)) ?? Date()
    }

    private func makeMarker(
        _ key: String,
        value: Double,
        unit: String,
        drawnAt: Date,
        reference: MarkerRange = .unbounded
    ) -> BloodMarkerSnapshot {
        BloodMarkerSnapshot(
            id: UUID(),
            marker: .standard(key),
            value: value,
            unitSymbol: unit,
            referenceRange: reference,
            optimalRange: .unbounded,
            drawnAt: drawnAt,
            note: ""
        )
    }

    // MARK: - Invariant: Neutral is a pure No-Op in DecisionEngine

    @Test("ClinicalContext.neutral DecisionEngine çıktısını zerre değiştirmez")
    func neutralIsPureNoOp() {
        let quality = DataQualityAssessment(
            grade: .excellent,
            wearHours: 23.0,
            nocturnalWearHours: 7.5,
            hasNocturnalHRV: true,
            hasNocturnalRHR: true,
            hasWristTemperature: true,
            hasSleepStages: true,
            confidenceFactor: 0.95,
            missingSensors: [],
            qualityIssues: []
        )
        let calibration = CalibrationState(
            recordedDaysCount: 30,
            hasHRVBaseline: true,
            hasRHRBaseline: true,
            hasWristTemperatureBaseline: true,
            hasSleepBaseline: true
        )

        let inputWithoutExplicitClinical = DecisionInput(
            recoveryScore: 82.0,
            recoveryBand: .green,
            sleepScore: 88.0,
            acuteLoad: 12.0,
            chronicLoad: 11.5,
            acwr: 1.04,
            muscleReadiness: [:],
            dataQuality: quality,
            calibration: calibration,
            lens: .endurance
        )

        let inputWithExplicitNeutral = DecisionInput(
            recoveryScore: 82.0,
            recoveryBand: .green,
            sleepScore: 88.0,
            acuteLoad: 12.0,
            chronicLoad: 11.5,
            acwr: 1.04,
            muscleReadiness: [:],
            dataQuality: quality,
            calibration: calibration,
            lens: .endurance,
            clinical: .neutral
        )

        let resultA = DecisionEngine.decide(input: inputWithoutExplicitClinical)
        let resultB = DecisionEngine.decide(input: inputWithExplicitNeutral)

        #expect(resultA.value.action == resultB.value.action)
        #expect(resultA.value.headline == resultB.value.headline)
        #expect(resultA.confidence.value == resultB.confidence.value)
        #expect(resultA.confidence.penaltyReasons == resultB.confidence.penaltyReasons)
        #expect(resultA.limitations == resultB.limitations)
        #expect(resultA.evidence.map(\.summary) == resultB.evidence.map(\.summary))
        #expect(resultA.evidence.map(\.weight) == resultB.evidence.map(\.weight))
        #expect(resultA.calculationSteps == resultB.calculationSteps)
    }

    // MARK: - Empty Input

    @Test("Boş girdi tam olarak .neutral döner")
    func emptyInputReturnsNeutral() {
        let context = ClinicalContextEngine.assess(
            markers: [],
            ecgRecords: [],
            sex: .male,
            now: date(2026, 6, 1),
            calendar: calendar
        )
        #expect(context == .neutral)
        #expect(context.confidenceMultiplier == 1.0)
        #expect(context.penaltyReasons.isEmpty)
        #expect(context.limitations.isEmpty)
        #expect(context.evidence.isEmpty)
        #expect(!context.suppressesHRVRecovery)
    }

    // MARK: - Modifiers: Triggered vs Non-Triggered

    @Test("Düşük hemoglobin çarpan uygular, normal hemoglobin uygulamaz")
    func hemoglobinLowTrigger() {
        let now = date(2026, 6, 1)
        let drawn = date(2026, 5, 20)

        let lowSample = [
            makeMarker("hemoglobin", value: 11.0, unit: "g/dL", drawnAt: drawn, reference: MarkerRange(minimum: 13.0, maximum: 17.5))
        ]
        let lowContext = ClinicalContextEngine.assess(markers: lowSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(lowContext.confidenceMultiplier == 0.85)
        #expect(!lowContext.penaltyReasons.isEmpty)
        #expect(lowContext.limitations.contains { $0.code == "CLINICAL-HEMOGLOBIN-LOW" })

        let normalSample = [
            makeMarker("hemoglobin", value: 15.0, unit: "g/dL", drawnAt: drawn, reference: MarkerRange(minimum: 13.0, maximum: 17.5))
        ]
        let normalContext = ClinicalContextEngine.assess(markers: normalSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(normalContext == .neutral)
    }

    @Test("Düşük ferritin çarpan uygular, normal ferritin uygulamaz")
    func ferritinLowTrigger() {
        let now = date(2026, 6, 1)
        let drawn = date(2026, 5, 20)

        let lowSample = [
            makeMarker("ferritin", value: 15.0, unit: "ng/mL", drawnAt: drawn, reference: MarkerRange(minimum: 30.0, maximum: 300.0))
        ]
        let lowContext = ClinicalContextEngine.assess(markers: lowSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(lowContext.confidenceMultiplier == 0.88)
        #expect(lowContext.limitations.contains { $0.code == "CLINICAL-FERRITIN-LOW" })

        let normalSample = [
            makeMarker("ferritin", value: 80.0, unit: "ng/mL", drawnAt: drawn, reference: MarkerRange(minimum: 30.0, maximum: 300.0))
        ]
        let normalContext = ClinicalContextEngine.assess(markers: normalSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(normalContext == .neutral)
    }

    @Test("Referans dışı TSH çarpan uygular, normal TSH uygulamaz")
    func tshShiftTrigger() {
        let now = date(2026, 6, 1)
        let drawn = date(2026, 5, 20)

        let highSample = [
            makeMarker("tsh", value: 5.8, unit: "mIU/L", drawnAt: drawn, reference: MarkerRange(minimum: 0.4, maximum: 4.0))
        ]
        let highContext = ClinicalContextEngine.assess(markers: highSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(highContext.confidenceMultiplier == 0.85)
        #expect(highContext.limitations.contains { $0.code == "CLINICAL-TSH-SHIFT" })

        let normalSample = [
            makeMarker("tsh", value: 2.1, unit: "mIU/L", drawnAt: drawn, reference: MarkerRange(minimum: 0.4, maximum: 4.0))
        ]
        let normalContext = ClinicalContextEngine.assess(markers: normalSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(normalContext == .neutral)
    }

    @Test("Yüksek hsCRP çarpan uygular, normal hsCRP uygulamaz")
    func hsCRPElevatedTrigger() {
        let now = date(2026, 6, 1)
        let drawn = date(2026, 5, 20)

        let highSample = [
            makeMarker("highSensitivityCRP", value: 4.5, unit: "mg/L", drawnAt: drawn, reference: MarkerRange(minimum: 0.0, maximum: 1.0))
        ]
        let highContext = ClinicalContextEngine.assess(markers: highSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(highContext.confidenceMultiplier == 0.90)
        #expect(highContext.limitations.contains { $0.code == "CLINICAL-HSCRP-ELEVATED" })

        let normalSample = [
            makeMarker("highSensitivityCRP", value: 0.4, unit: "mg/L", drawnAt: drawn, reference: MarkerRange(minimum: 0.0, maximum: 1.0))
        ]
        let normalContext = ClinicalContextEngine.assess(markers: normalSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(normalContext == .neutral)
    }

    @Test("Kreatin kinaz 5 katı aştığında çarpan uygulamaz ama kas sınırı ekler")
    func creatineKinaseSevereTrigger() {
        let now = date(2026, 6, 1)
        let drawn = date(2026, 5, 20)

        // Upper ref = 308, 5x = 1540 U/L
        let highSample = [
            makeMarker("creatineKinase", value: 2000.0, unit: "U/L", drawnAt: drawn, reference: MarkerRange(minimum: 39.0, maximum: 308.0))
        ]
        let context = ClinicalContextEngine.assess(markers: highSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(context.confidenceMultiplier == 1.0)
        #expect(context.limitations.contains { $0.code == "CLINICAL-CK-SEVERE" })
    }

    @Test("Atriyal fibrilasyon EKG kaydı HRV toparlanmasını baskılar ve karar dalını kilitler")
    func ecgAtrialFibrillationTrigger() {
        let now = date(2026, 6, 1)
        let ecg = ECGRecord(
            recordedAt: date(2026, 6, 1),
            classification: .atrialFibrillation,
            averageHeartRate: 92.0,
            sourceName: "Apple Watch"
        )

        let context = ClinicalContextEngine.assess(markers: [], ecgRecords: [ecg], sex: .male, now: now, calendar: calendar)
        #expect(context.suppressesHRVRecovery)
        #expect(context.limitations.contains { $0.code == "CLINICAL-ECG-AF" && $0.isBlocking })

        // Verify DecisionEngine integration
        let quality = DataQualityAssessment(
            grade: .excellent,
            wearHours: 23.0,
            nocturnalWearHours: 7.5,
            hasNocturnalHRV: true,
            hasNocturnalRHR: true,
            hasWristTemperature: true,
            hasSleepStages: true,
            confidenceFactor: 0.95,
            missingSensors: [],
            qualityIssues: []
        )
        let calibration = CalibrationState(
            recordedDaysCount: 30,
            hasHRVBaseline: true,
            hasRHRBaseline: true,
            hasWristTemperatureBaseline: true,
            hasSleepBaseline: true
        )

        let input = DecisionInput(
            recoveryScore: 85.0,
            recoveryBand: .green,
            sleepScore: 90.0,
            dataQuality: quality,
            calibration: calibration,
            clinical: context
        )

        let result = DecisionEngine.decide(input: input)
        #expect(result.value.action == .calibrate)
        #expect(result.limitations.contains { $0.code == "CLINICAL-AF-SUPPRESSED" && $0.isBlocking })
    }

    @Test("Belirsiz zayıf EKG kaydı çarpan 0.95 uygular")
    func ecgPoorReadingTrigger() {
        let now = date(2026, 6, 1)
        let ecg = ECGRecord(
            recordedAt: date(2026, 6, 1),
            classification: .inconclusivePoorReading,
            averageHeartRate: nil,
            sourceName: "Apple Watch"
        )

        let context = ClinicalContextEngine.assess(markers: [], ecgRecords: [ecg], sex: .male, now: now, calendar: calendar)
        #expect(context.confidenceMultiplier == 0.95)
        #expect(context.limitations.contains { $0.code == "CLINICAL-ECG-POOR-READING" })
    }

    // MARK: - Staleness Horizon

    @Test("Bayatlayan tahlil değerleri nötre iner")
    func staleMarkersDropToNeutral() {
        let now = date(2026, 6, 1)
        // 24 months ago -> validityMonths of ferritin is 3 months
        let staleDrawn = date(2024, 6, 1)

        let staleSample = [
            makeMarker("ferritin", value: 12.0, unit: "ng/mL", drawnAt: staleDrawn, reference: MarkerRange(minimum: 30.0, maximum: 300.0))
        ]

        let context = ClinicalContextEngine.assess(markers: staleSample, ecgRecords: [], sex: .male, now: now, calendar: calendar)
        #expect(context == .neutral)
        #expect(context.confidenceMultiplier == 1.0)
    }

    // MARK: - Multiplier Floor Clamping

    @Test("Tüm düzenleyiciler aynı anda tetiklense bile çarpan tabanı 0.70 altına inemez")
    func multiplierFloorClamp() {
        let now = date(2026, 6, 1)
        let drawn = date(2026, 5, 20)

        let extremeMarkers = [
            makeMarker("hemoglobin", value: 10.0, unit: "g/dL", drawnAt: drawn, reference: MarkerRange(minimum: 13.0, maximum: 17.5)), // x0.85
            makeMarker("ferritin", value: 10.0, unit: "ng/mL", drawnAt: drawn, reference: MarkerRange(minimum: 30.0, maximum: 300.0)),   // x0.88
            makeMarker("tsh", value: 6.0, unit: "mIU/L", drawnAt: drawn, reference: MarkerRange(minimum: 0.4, maximum: 4.0)),            // x0.85
            makeMarker("highSensitivityCRP", value: 8.0, unit: "mg/L", drawnAt: drawn, reference: MarkerRange(minimum: 0.0, maximum: 1.0)) // x0.90
        ]
        let ecg = ECGRecord(
            recordedAt: now,
            classification: .inconclusivePoorReading, // x0.95
            sourceName: "Apple Watch"
        )

        let context = ClinicalContextEngine.assess(markers: extremeMarkers, ecgRecords: [ecg], sex: .male, now: now, calendar: calendar)
        // 0.85 * 0.88 * 0.85 * 0.90 * 0.95 = ~0.543 -> clamped to 0.70
        #expect(context.confidenceMultiplier == ClinicalContextEngine.multiplierFloor)
        #expect(context.confidenceMultiplier == 0.70)
    }

    // MARK: - Disabled Modifiers

    @Test("Devre dışı bırakılan düzenleyici değerlendirmeye katılmaz")
    func disabledModifierIsSkipped() {
        let now = date(2026, 6, 1)
        let drawn = date(2026, 5, 20)

        let sample = [
            makeMarker("ferritin", value: 15.0, unit: "ng/mL", drawnAt: drawn, reference: MarkerRange(minimum: 30.0, maximum: 300.0))
        ]

        let disabledIDs: Set<String> = [ClinicalModifierRegistry.ferritinLow.id]
        let context = ClinicalContextEngine.assess(
            markers: sample,
            ecgRecords: [],
            disabledModifierIDs: disabledIDs,
            sex: .male,
            now: now,
            calendar: calendar
        )

        #expect(context == .neutral)
        #expect(context.confidenceMultiplier == 1.0)
    }
}
