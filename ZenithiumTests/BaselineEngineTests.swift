//
//  BaselineEngineTests.swift
//  ZenithiumTests
//
//  Spec §4 and the §11 requirements for EWMA convergence, winsorization and cold start.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Baseline engine")
struct BaselineEngineTests {

    private let day0 = iso("2025-01-01T00:00:00Z")

    private func day(_ offset: Int) -> Date {
        day0.addingTimeInterval(Double(offset) * TimeConversion.secondsPerDay)
    }

    // MARK: - §4.1

    @Test("Alpha is 2/(60+1)")
    func alphaMatchesWindow() {
        expectClose(
            EngineConstants.Baseline.alpha,
            2.0 / 61.0,
            tolerance: 1e-12,
            "alpha"
        )
    }

    @Test("EWMA converges to a constant input and its variance collapses")
    func ewmaConverges() {
        var state = BaselineSnapshot.empty(metric: .heartRateVariability)
        for index in 0..<400 {
            state = BaselineEngine.update(state, with: 50, on: day(index)).snapshot
        }
        expectClose(state.mean, 50, tolerance: 1e-9, "converged mean")
        expectClose(state.variance, 0, tolerance: 1e-9, "converged variance")
        #expect(state.sampleCount == 400)
    }

    @Test("A baseline seeds from the first three valid days")
    func seedsFromThreeDays() {
        var state = BaselineSnapshot.empty(metric: .restingHeartRate)
        state = BaselineEngine.update(state, with: 50, on: day(0)).snapshot
        #expect(state.sampleCount == 1)
        #expect(!state.isSeeded)

        state = BaselineEngine.update(state, with: 52, on: day(1)).snapshot
        #expect(state.sampleCount == 2)

        state = BaselineEngine.update(state, with: 54, on: day(2)).snapshot
        #expect(state.isSeeded)
        #expect(state.sampleCount == 3)
        // μ₀ is the mean of the three, V₀ their sample variance (§4.2.6).
        expectClose(state.mean, 52, tolerance: 1e-9, "seed mean")
        expectClose(state.variance, 4, tolerance: 1e-9, "seed variance")
    }

    // MARK: - §4.2.2 winsorization

    @Test("A 3σ outlier moves the mean no more than its clamped value would")
    func winsorizationDampensOutliers() {
        var seeded = BaselineSnapshot.empty(metric: .heartRateVariability)
        for index in 0..<3 {
            seeded = BaselineEngine.update(seeded, with: 55, on: day(index)).snapshot
        }
        // Give it a σ to clamp against, then fold in a wild but plausible reading.
        let stateWithSigma = BaselineSnapshot(
            metric: .heartRateVariability,
            mean: 55,
            variance: 64,
            sampleCount: 30,
            lastUpdated: day(3),
            seedValues: []
        )
        let update = BaselineEngine.update(stateWithSigma, with: 200, on: day(4))

        #expect(update.wasWinsorized)
        expectClose(update.storedValue, 79, tolerance: 1e-9, "clamped to μ + 3σ")

        // The unwinsorized fold, for comparison.
        let alpha = EngineConstants.Baseline.alpha
        let unclampedMean = alpha * 200 + (1 - alpha) * 55
        #expect(abs(update.snapshot.mean - 55) < abs(unclampedMean - 55))
    }

    @Test("An implausible reading is rejected outright and leaves the baseline untouched")
    func rejectsImplausibleValues() {
        let state = BaselineSnapshot(
            metric: .heartRateVariability,
            mean: 55,
            variance: 64,
            sampleCount: 30,
            lastUpdated: day(3),
            seedValues: []
        )
        // 900 ms is outside `MetricKind.plausibleRange`, so it is a sensor fault rather than
        // an extreme day — clamping it would still drag the baseline.
        let update = BaselineEngine.update(state, with: 900, on: day(4))
        #expect(update.wasRejected)
        #expect(update.snapshot == state)
    }

    @Test("A day already folded in cannot be folded in twice")
    func isIdempotentPerDay() {
        var state = BaselineSnapshot.empty(metric: .respiratoryRate)
        for index in 0..<5 {
            state = BaselineEngine.update(state, with: 14.5, on: day(index)).snapshot
        }
        let before = state
        let repeated = BaselineEngine.update(state, with: 18.0, on: day(4)).snapshot
        #expect(repeated == before)
    }

    @Test("A gap does not advance the EWMA")
    func gapsDoNotAdvance() {
        var withGap = BaselineSnapshot.empty(metric: .restingHeartRate)
        var without = BaselineSnapshot.empty(metric: .restingHeartRate)
        let values: [Double] = [50, 51, 52, 53, 54]

        for (index, value) in values.enumerated() {
            without = BaselineEngine.update(without, with: value, on: day(index)).snapshot
            // Same values, but spread across days with holes between them.
            withGap = BaselineEngine.update(withGap, with: value, on: day(index * 3)).snapshot
        }
        // The EWMA is driven by the sequence of values, not by elapsed time, so a gap
        // changes nothing except the recorded date.
        expectClose(withGap.mean, without.mean, tolerance: 1e-12, "mean")
        #expect(withGap.sampleCount == without.sampleCount)
    }

    // MARK: - §4.2.3 σ floors

    @Test("Sigma floors apply to every metric", arguments: MetricKind.allCases)
    func sigmaFloorsApply(metric: MetricKind) {
        let degenerate = BaselineSnapshot(
            metric: metric,
            mean: 10,
            variance: 0,
            sampleCount: 30,
            lastUpdated: day(0),
            seedValues: []
        )
        #expect(degenerate.effectiveStandardDeviation == metric.sigmaFloor)
        let scoring = BaselineEngine.scoringBaseline(from: degenerate)
        #expect(scoring.standardDeviation >= metric.sigmaFloor)
    }

    @Test("The declared floors match the specification")
    func floorValues() {
        expectClose(MetricKind.heartRateVariability.sigmaFloor, 3.0, tolerance: 1e-12, "HRV")
        expectClose(MetricKind.restingHeartRate.sigmaFloor, 1.5, tolerance: 1e-12, "RHR")
        expectClose(MetricKind.wristTemperature.sigmaFloor, 0.15, tolerance: 1e-12, "Temp")
        expectClose(MetricKind.respiratoryRate.sigmaFloor, 0.30, tolerance: 1e-12, "BR")
    }

    // MARK: - §4.2.4 cold start

    @Test("Fewer than five days is not scorable")
    func belowFiveDaysIsNotScorable() {
        for count in 0..<5 {
            let state = BaselineSnapshot(
                metric: .heartRateVariability,
                mean: 55,
                variance: 64,
                sampleCount: count,
                lastUpdated: day(0),
                seedValues: []
            )
            #expect(!BaselineEngine.scoringBaseline(from: state).isScorable)
        }
        let five = BaselineSnapshot(
            metric: .heartRateVariability,
            mean: 55,
            variance: 64,
            sampleCount: 5,
            lastUpdated: day(0),
            seedValues: []
        )
        #expect(BaselineEngine.scoringBaseline(from: five).isScorable)
    }

    @Test("Ten days gives a confidence of 0.714")
    func confidenceAtTenDays() {
        let state = BaselineSnapshot(
            metric: .heartRateVariability,
            mean: 55,
            variance: 64,
            sampleCount: 10,
            lastUpdated: day(0),
            seedValues: []
        )
        expectClose(
            BaselineEngine.scoringBaseline(from: state).confidence,
            0.714,
            tolerance: 0.001,
            "confidence at n = 10"
        )
    }

    @Test("A thin baseline blends toward the population prior")
    func blendsTowardPrior() {
        let personalMean: Double = 80
        let state = BaselineSnapshot(
            metric: .heartRateVariability,
            mean: personalMean,
            variance: 64,
            sampleCount: 7,
            lastUpdated: day(0),
            seedValues: []
        )
        let scoring = BaselineEngine.scoringBaseline(from: state)
        let weight = 7.0 / 14.0
        let expected = weight * personalMean + (1 - weight) * MetricKind.heartRateVariability.prior.mean
        expectClose(scoring.mean, expected, tolerance: 1e-9, "blended mean")
        // It must sit strictly between the personal value and the prior.
        #expect(scoring.mean < personalMean)
        #expect(scoring.mean > MetricKind.heartRateVariability.prior.mean)
    }

    @Test("Wrist temperature keeps a personal mean while blending sigma (BASE-4)")
    func temperatureBlendsSigmaOnly() {
        let state = BaselineSnapshot(
            metric: .wristTemperature,
            mean: 34.2,
            variance: 0.09,
            sampleCount: 7,
            lastUpdated: day(0),
            seedValues: []
        )
        let scoring = BaselineEngine.scoringBaseline(from: state)
        // Blending the absolute mean toward a delta-scale prior of 0 would be meaningless.
        expectClose(scoring.mean, 34.2, tolerance: 1e-12, "personal mean retained")
        #expect(scoring.standardDeviation > 0.3)
    }

    @Test("Rebuilding from a series is deterministic and idempotent")
    func rebuildIsDeterministic() {
        let samples = (0..<40).map { index in
            DailyMetricSample(
                dayStart: day(index),
                value: 50 + Double(index % 7),
                timeZoneIdentifier: "UTC"
            )
        }
        let first = BaselineEngine.rebuild(metric: .restingHeartRate, from: samples)
        let second = BaselineEngine.rebuild(metric: .restingHeartRate, from: samples.shuffled())
        #expect(first == second)
    }
}
