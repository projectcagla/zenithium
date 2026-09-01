//
//  RecoveryEngineTests.swift
//  ZenithiumTests
//
//  Spec §11 golden vector 1, §4.3 renormalization, §4.2.4 cold start, §5.6 edge cases.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Recovery engine")
struct RecoveryEngineTests {

    /// §11.1 — the exact inputs the specification gives.
    ///
    /// Wrist temperature is expressed as an absolute reading against a personal mean, so the
    /// engine derives ΔT = +0.3 itself (ASSUMPTION BASE-3).
    private var goldenInput: RecoveryInput {
        RecoveryInput(
            heartRateVariability: observation(.heartRateVariability, value: 62, mean: 55, standardDeviation: 8),
            restingHeartRate: observation(.restingHeartRate, value: 50, mean: 54, standardDeviation: 3),
            wristTemperature: observation(.wristTemperature, value: 34.3, mean: 34.0, standardDeviation: 0.35),
            respiratoryRate: observation(.respiratoryRate, value: 14.2, mean: 14.8, standardDeviation: 0.8),
            sleepScore: 82,
            hasOvernightData: true,
            sleepWasImplausible: false
        )
    }

    // MARK: - §11 golden vector 1

    @Test("Golden vector 1 — every z-score")
    func goldenZScores() {
        let output = RecoveryEngine.compute(goldenInput)

        expectClose(output.contribution(for: .heartRateVariability)?.zScore ?? .nan, 0.8750, "Z_HRV")
        expectClose(output.contribution(for: .restingHeartRate)?.zScore ?? .nan, 1.3333, "Z_RHR")
        expectClose(output.contribution(for: .temperature)?.zScore ?? .nan, -0.8571, "Z_Temp")
        expectClose(output.contribution(for: .respiratory)?.zScore ?? .nan, 0.7500, "Z_Resp")
        expectClose(output.contribution(for: .sleep)?.zScore ?? .nan, 0.8000, "SleepNorm")
    }

    @Test("Golden vector 1 — Z_total, score, band and ceiling")
    func goldenScore() {
        let output = RecoveryEngine.compute(goldenInput)

        #expect(output.availability.isScored)
        expectClose(output.zTotal ?? .nan, 0.7951, "Z_total")
        expectClose(output.score ?? .nan, 72.2, "Recovery")
        #expect(output.band == .green)
        expectClose(output.targetStrainCeiling ?? .nan, 17.0, "Ceiling")
    }

    @Test("Golden vector 1 — driver shares sum to one and are ordered by magnitude")
    func goldenDrivers() {
        let output = RecoveryEngine.compute(goldenInput)

        #expect(output.drivers.count == 5)
        expectClose(output.drivers.map(\.share).reduce(0, +), 1.0, tolerance: 1e-9, "shares")

        let magnitudes = output.drivers.map { abs($0.contribution) }
        #expect(magnitudes == magnitudes.sorted(by: >))

        // HRV carries the largest positive contribution; temperature the only negative one.
        #expect(output.topPositiveDriver?.driver == .heartRateVariability)
        #expect(output.topNegativeDriver?.driver == .temperature)
        #expect(output.topPositiveSummary != nil)
        #expect(output.topNegativeSummary != nil)
    }

    // MARK: - §5.1 clamping

    @Test("Every z-score is clamped to ±3")
    func zScoresAreClamped() {
        let extreme = RecoveryInput(
            heartRateVariability: observation(.heartRateVariability, value: 400, mean: 55, standardDeviation: 8),
            restingHeartRate: observation(.restingHeartRate, value: 25, mean: 54, standardDeviation: 3),
            wristTemperature: nil,
            respiratoryRate: nil,
            sleepScore: 100,
            hasOvernightData: true,
            sleepWasImplausible: false
        )
        let output = RecoveryEngine.compute(extreme)
        for driver in output.drivers {
            #expect(driver.zScore <= 3.0)
            #expect(driver.zScore >= -3.0)
        }
        #expect((output.score ?? 0) <= 100)
        #expect((output.score ?? 0) >= 1)
    }

    // MARK: - §4.3 renormalization

    @Test("Missing wrist temperature renormalizes the survivors to sum to one")
    func missingTemperatureRenormalizes() {
        var input = goldenInput
        input = RecoveryInput(
            heartRateVariability: input.heartRateVariability,
            restingHeartRate: input.restingHeartRate,
            wristTemperature: nil,
            respiratoryRate: input.respiratoryRate,
            sleepScore: input.sleepScore,
            hasOvernightData: true,
            sleepWasImplausible: false
        )
        let output = RecoveryEngine.compute(input)

        #expect(output.missingDrivers == [.temperature])
        #expect(output.weightsWereRenormalized)

        let total = output.drivers.map(\.weight).reduce(0, +)
        expectClose(total, 1.0, tolerance: 1e-9, "renormalized weights sum")

        // ASSUMPTION RECOV-1 — divide by the surviving sum (0.90), which is what §4.3 and the
        // §11 test both require. §5.6's printed figures divide by 0.95 and sum to 0.9474.
        expectClose(output.contribution(for: .heartRateVariability)?.weight ?? .nan, 0.4444, tolerance: 0.0005, "HRV weight")
        expectClose(output.contribution(for: .restingHeartRate)?.weight ?? .nan, 0.2778, tolerance: 0.0005, "RHR weight")
        expectClose(output.contribution(for: .sleep)?.weight ?? .nan, 0.2222, tolerance: 0.0005, "Sleep weight")
        expectClose(output.contribution(for: .respiratory)?.weight ?? .nan, 0.0556, tolerance: 0.0005, "Resp weight")
    }

    @Test("Weights always sum to one however many terms are dropped")
    func weightsAlwaysSumToOne() {
        let combinations: [(temp: Bool, resp: Bool, sleep: Bool)] = [
            (true, true, true), (false, true, true), (true, false, true),
            (true, true, false), (false, false, true), (false, true, false),
            (true, false, false), (false, false, false)
        ]
        for combination in combinations {
            let input = RecoveryInput(
                heartRateVariability: observation(.heartRateVariability, value: 62, mean: 55, standardDeviation: 8),
                restingHeartRate: observation(.restingHeartRate, value: 50, mean: 54, standardDeviation: 3),
                wristTemperature: combination.temp
                    ? observation(.wristTemperature, value: 34.3, mean: 34.0, standardDeviation: 0.35)
                    : nil,
                respiratoryRate: combination.resp
                    ? observation(.respiratoryRate, value: 14.2, mean: 14.8, standardDeviation: 0.8)
                    : nil,
                sleepScore: combination.sleep ? 82 : nil,
                hasOvernightData: true,
                sleepWasImplausible: false
            )
            let output = RecoveryEngine.compute(input)
            expectClose(
                output.drivers.map(\.weight).reduce(0, +),
                1.0,
                tolerance: 1e-9,
                "weights for temp:\(combination.temp) resp:\(combination.resp) sleep:\(combination.sleep)"
            )
        }
    }

    // MARK: - §4.3 suppression and §5.6 edge cases

    @Test("Missing HRV suppresses the score entirely")
    func missingHRVSuppresses() {
        let input = RecoveryInput(
            heartRateVariability: nil,
            restingHeartRate: observation(.restingHeartRate, value: 50, mean: 54, standardDeviation: 3),
            wristTemperature: nil,
            respiratoryRate: nil,
            sleepScore: 82,
            hasOvernightData: true,
            sleepWasImplausible: false
        )
        let output = RecoveryEngine.compute(input)
        #expect(output.score == nil)
        #expect(output.availability == .unavailable(.heartRateVariabilityMissing))
    }

    @Test("Missing resting heart rate suppresses the score entirely")
    func missingRestingHeartRateSuppresses() {
        let input = RecoveryInput(
            heartRateVariability: observation(.heartRateVariability, value: 62, mean: 55, standardDeviation: 8),
            restingHeartRate: nil,
            wristTemperature: nil,
            respiratoryRate: nil,
            sleepScore: 82,
            hasOvernightData: true,
            sleepWasImplausible: false
        )
        #expect(RecoveryEngine.compute(input).availability == .unavailable(.restingHeartRateMissing))
    }

    @Test("No overnight data yields no score and no ceiling")
    func noOvernightData() {
        let input = RecoveryInput(
            heartRateVariability: nil,
            restingHeartRate: nil,
            wristTemperature: nil,
            respiratoryRate: nil,
            sleepScore: nil,
            hasOvernightData: false,
            sleepWasImplausible: false
        )
        let output = RecoveryEngine.compute(input)
        #expect(output.availability == .unavailable(.noOvernightData))
        #expect(output.score == nil)
        #expect(output.targetStrainCeiling == nil)
    }

    @Test("An implausible night is not scored")
    func implausibleSleep() {
        var input = goldenInput
        input = RecoveryInput(
            heartRateVariability: input.heartRateVariability,
            restingHeartRate: input.restingHeartRate,
            wristTemperature: input.wristTemperature,
            respiratoryRate: input.respiratoryRate,
            sleepScore: nil,
            hasOvernightData: true,
            sleepWasImplausible: true
        )
        #expect(RecoveryEngine.compute(input).availability == .unavailable(.sleepImplausible))
    }

    // MARK: - §4.2.4 cold start

    @Test("Three baseline days yields calibrating, not a score")
    func threeDaysCalibrates() {
        let thin = ScoringBaseline(
            metric: .heartRateVariability,
            mean: 55,
            standardDeviation: 8,
            sampleCount: 3,
            confidence: 3.0 / 14.0,
            isScorable: false
        )
        let thinRHR = ScoringBaseline(
            metric: .restingHeartRate,
            mean: 54,
            standardDeviation: 3,
            sampleCount: 3,
            confidence: 3.0 / 14.0,
            isScorable: false
        )
        let input = RecoveryInput(
            heartRateVariability: MetricObservation(value: 62, baseline: thin),
            restingHeartRate: MetricObservation(value: 50, baseline: thinRHR),
            wristTemperature: nil,
            respiratoryRate: nil,
            sleepScore: 82,
            hasOvernightData: true,
            sleepWasImplausible: false
        )
        let output = RecoveryEngine.compute(input)
        #expect(output.score == nil)
        #expect(output.availability == .calibrating(daysCollected: 3, daysRequired: 14))
    }

    // MARK: - §5.3 ceiling

    @Test("Ceiling reference points", arguments: [(33.0, 10.2), (67.0, 16.2), (90.0, 19.6)])
    func ceilingReferencePoints(recovery: Double, expected: Double) {
        expectClose(
            RecoveryEngine.targetCeiling(forRecovery: recovery),
            expected,
            "ceiling at recovery \(recovery)"
        )
    }

    @Test("The ceiling is monotonic in recovery")
    func ceilingIsMonotonic() {
        var previous = -1.0
        for score in stride(from: 1.0, through: 100.0, by: 1.0) {
            let ceiling = RecoveryEngine.targetCeiling(forRecovery: score)
            #expect(ceiling > previous)
            #expect(ceiling <= EngineConstants.Strain.scaleMax)
            previous = ceiling
        }
    }
}
