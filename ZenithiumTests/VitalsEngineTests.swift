//
//  VitalsEngineTests.swift
//  ZenithiumTests
//
//  Baselines and the multivariate deviation score.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Vitals engine")
struct VitalsEngineTests {

    private let calendar = Calendar(identifier: .gregorian)

    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 9)) ?? Date()
    }

    private func samples(_ sign: VitalSign, _ values: [Double]) -> [VitalSample] {
        values.enumerated().map { offset, value in
            let day = calendar.date(byAdding: .day, value: -(values.count - 1 - offset), to: reference) ?? reference
            return VitalSample(sign: sign, dayStart: calendar.startOfDay(for: day), value: value)
        }
    }

    // MARK: - Baselines

    @Test("Taban çizgisi bugünü dışarıda bırakır")
    func baselineExcludesToday() throws {
        // Twenty days at 50, then today at 60. If today were folded into its own comparison
        // the mean would move and the z-score would shrink.
        let reading = VitalsEngine.reading(
            for: .restingHeartRate,
            samples: samples(.restingHeartRate, Array(repeating: 50.0, count: 20) + [60])
        )
        let mean = try #require(reading.baselineMean)
        #expect(abs(mean - 50) < 1e-9)
        let z = try #require(reading.zScore)
        #expect(z > 5)
    }

    @Test("Yeterli örnek yoksa z-skoru yok")
    func requiresEnoughSamples() {
        let reading = VitalsEngine.reading(for: .vo2Max, samples: samples(.vo2Max, [48, 47, 49]))
        #expect(reading.latest != nil)
        #expect(reading.zScore == nil)
        #expect(reading.baselineMean == nil)
    }

    /// A signal that sits still for a fortnight would otherwise produce a near-zero divisor
    /// and turn the next ordinary reading into a five-sigma event.
    @Test("Sapma tabanı düz seriyi patlatmaz")
    func deviationFloorHoldsFlatSeries() throws {
        let reading = VitalsEngine.reading(
            for: .restingHeartRate,
            samples: samples(.restingHeartRate, Array(repeating: 50.0, count: 20) + [51])
        )
        let deviation = try #require(reading.baselineDeviation)
        #expect(abs(deviation - 1.0) < 1e-9, "50 × 0.02 = 1.0 bekleniyordu, \(deviation)")
        let z = try #require(reading.zScore)
        #expect(abs(z - 1.0) < 1e-9)
    }

    // MARK: - Deviation score

    /// The orientation step is what makes combining signals legitimate: an HRV drop and a
    /// resting-heart-rate rise are the same story with opposite signs, and summing the raw
    /// z-scores would cancel them out on exactly the mornings this exists to catch.
    @Test("Zıt işaretli ama aynı yöndeki sinyaller birbirini götürmez")
    func orientationPreventsCancellation() throws {
        let flatHRV = Array(repeating: 60.0, count: 20)
        let flatRHR = Array(repeating: 50.0, count: 20)

        let readings = VitalsEngine.readings(
            from: samples(.heartRateVariability, flatHRV + [48])   // düşüş
                + samples(.restingHeartRate, flatRHR + [56])       // yükseliş
        )
        let score = VitalsEngine.deviationScore(from: readings)

        #expect(score.availableSignals == 2)
        #expect(score.magnitude > 1.0, "büyüklük: \(score.magnitude)")
        for contributor in score.contributors {
            #expect(contributor.orientedZ > 0, "\(contributor.sign) yönlendirilmemiş")
        }
        #expect(score.isWorthReporting)
    }

    @Test("Tek sinyalin hareketi rapor edilmez")
    func singleSignalIsNotReported() {
        let readings = VitalsEngine.readings(
            from: samples(.heartRateVariability, Array(repeating: 60.0, count: 20) + [40])
                + samples(.restingHeartRate, Array(repeating: 50.0, count: 21))
        )
        let score = VitalsEngine.deviationScore(from: readings)
        #expect(!score.isWorthReporting, "tek sinyal bir anomali değil")
        #expect(VitalsEngine.deviationSummary(for: score) == nil)
    }

    /// A morning where HRV is unusually *high* is not an anomaly to report.
    @Test("İyi yöndeki sapma uyarı üretmez")
    func favourableDeviationIsNotFlagged() {
        let readings = VitalsEngine.readings(
            from: samples(.heartRateVariability, Array(repeating: 60.0, count: 20) + [78])
                + samples(.restingHeartRate, Array(repeating: 50.0, count: 20) + [44])
        )
        let score = VitalsEngine.deviationScore(from: readings)
        #expect(score.magnitude == 0)
        #expect(!score.isWorthReporting)
    }

    /// §12: the sentence names signals and numbers, routes to a clinician, and never names
    /// a condition. `SafetyFilter` is the same gate the narrator uses.
    @Test("Sapma cümlesi güvenlik süzgecinden geçer")
    func summaryIsSafe() throws {
        let readings = VitalsEngine.readings(
            from: samples(.heartRateVariability, Array(repeating: 60.0, count: 20) + [42])
                + samples(.restingHeartRate, Array(repeating: 50.0, count: 20) + [58])
                + samples(.respiratoryRate, Array(repeating: 14.0, count: 20) + [16.5])
        )
        let score = VitalsEngine.deviationScore(from: readings)
        let summary = try #require(VitalsEngine.deviationSummary(for: score))
        #expect(SafetyFilter.isSafe(summary), "\(summary)")
        #expect(summary.contains("teşhis değil"))
    }

    @Test("Yalnızca birlikte hareket eden sinyaller skora girer")
    func onlyCoMovingSignalsParticipate() {
        let readings = VitalsEngine.readings(
            from: samples(.walkingSpeed, Array(repeating: 1.3, count: 20) + [0.9])
                + samples(.vo2Max, Array(repeating: 48.0, count: 20) + [40])
        )
        let score = VitalsEngine.deviationScore(from: readings)
        #expect(score.availableSignals == 0, "mobilite sinyalleri sabah anomalisine girmemeli")
    }

    // MARK: - Slope

    @Test("Eğim yönü doğru")
    func slopeDirection() throws {
        let rising = samples(.vo2Max, (0..<20).map { 45 + Double($0) * 0.1 })
        let slope = try #require(VitalsEngine.slopePerDay(of: rising))
        #expect(abs(slope - 0.1) < 1e-9)
        #expect(VitalsEngine.slopePerDay(of: Array(rising.prefix(4))) == nil)
    }
}
