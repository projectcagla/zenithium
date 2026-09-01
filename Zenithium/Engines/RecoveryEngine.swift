//
//  RecoveryEngine.swift
//  Zenithium
//
//  The recovery score. Spec §5.1 in full, §4.3 for missing-metric renormalization,
//  §4.2.4 for cold start, §5.3 for the target ceiling.
//
//      Z_HRV     =  (HRV − μ) / σ
//      Z_RHR     = −(RHR − μ) / σ
//      Z_Temp    = −| ΔT / σ |
//      Z_Resp    = −(BR − μ) / σ
//      SleepNorm = clamp((SleepScore − 70) / 15, −3, +3)
//      Z_total   = Σ wᵢ·Zᵢ          (weights renormalized over the surviving terms)
//      Recovery  = clamp(100 / (1 + e^(−1.2·Z_total)), 1, 100)
//

import Foundation

enum RecoveryEngine {

    static func compute(_ input: RecoveryInput) -> RecoveryOutput {
        // §5.6 — the watch was not worn. No score, and the baselines are left alone by the
        // caller, which never folds an empty night in.
        guard input.hasOvernightData else {
            return .unavailable(.noOvernightData)
        }
        // §5.6 — a night under 2 h or over 14 h is `.suspect` and must not be scored.
        guard !input.sleepWasImplausible else {
            return .unavailable(.sleepImplausible)
        }
        // §4.3 — recovery is suppressed entirely if HRV or RHR is missing. These two are not
        // renormalized away; without them there is no score.
        guard let hrv = input.heartRateVariability else {
            return .unavailable(.heartRateVariabilityMissing)
        }
        guard let restingHR = input.restingHeartRate else {
            return .unavailable(.restingHeartRateMissing)
        }
        // §4.2.4 — below five valid days there is no score at all, only calibration progress.
        guard hrv.baseline.isScorable, restingHR.baseline.isScorable else {
            let collected = min(hrv.baseline.sampleCount, restingHR.baseline.sampleCount)
            return .calibrating(
                daysCollected: collected,
                daysRequired: EngineConstants.Baseline.fullConfidenceSamples
            )
        }

        // Raw z-scores, each clamped to [−3, +3] (§5.1).
        var zScores: [RecoveryDriver: Double] = [:]
        var observations: [RecoveryDriver: (value: Double, mean: Double, sigma: Double)] = [:]

        zScores[.heartRateVariability] = clampedZ(
            MathSupport.safeDivide(
                hrv.scoredQuantity - hrv.baseline.mean,
                by: hrv.baseline.standardDeviation
            )
        )
        observations[.heartRateVariability] = (
            hrv.value, hrv.baseline.mean, hrv.baseline.standardDeviation
        )

        zScores[.restingHeartRate] = clampedZ(
            -MathSupport.safeDivide(
                restingHR.scoredQuantity - restingHR.baseline.mean,
                by: restingHR.baseline.standardDeviation
            )
        )
        observations[.restingHeartRate] = (
            restingHR.value, restingHR.baseline.mean, restingHR.baseline.standardDeviation
        )

        if let sleepScore = input.sleepScore {
            // SleepNorm is already a normalized deviation, so it is clamped by the same rule
            // but not divided by a σ.
            zScores[.sleep] = clampedZ(
                MathSupport.safeDivide(
                    sleepScore - EngineConstants.Recovery.sleepNormCenter,
                    by: EngineConstants.Recovery.sleepNormScale
                )
            )
            observations[.sleep] = (
                sleepScore,
                EngineConstants.Recovery.sleepNormCenter,
                EngineConstants.Recovery.sleepNormScale
            )
        }

        if let temperature = input.wristTemperature, temperature.baseline.isScorable {
            // §5.1 — `Z_Temp = −|ΔT / σ|`. Deviation in either direction reads as load, so
            // the term can only ever be zero or negative.
            let delta = temperature.scoredQuantity
            zScores[.temperature] = clampedZ(
                -abs(MathSupport.safeDivide(delta, by: temperature.baseline.standardDeviation))
            )
            observations[.temperature] = (
                delta, 0, temperature.baseline.standardDeviation
            )
        }

        if let respiratory = input.respiratoryRate, respiratory.baseline.isScorable {
            zScores[.respiratory] = clampedZ(
                -MathSupport.safeDivide(
                    respiratory.scoredQuantity - respiratory.baseline.mean,
                    by: respiratory.baseline.standardDeviation
                )
            )
            observations[.respiratory] = (
                respiratory.value, respiratory.baseline.mean, respiratory.baseline.standardDeviation
            )
        }

        // §4.3 — drop the missing terms and renormalize the survivors to sum to 1.0. Never
        // substitute zero, which would silently bias the score toward the middle.
        var survivingWeights: [RecoveryDriver: Double] = [:]
        for driver in RecoveryDriver.allCases where zScores[driver] != nil {
            survivingWeights[driver] = EngineConstants.Recovery.weight(for: driver)
        }
        let weights = MathSupport.renormalize(survivingWeights)

        var zTotal: Double = 0
        var contributions: [RecoveryDriver: Double] = [:]
        for (driver, z) in zScores {
            guard let weight = weights[driver] else { continue }
            let contribution = weight * z
            contributions[driver] = contribution
            zTotal += contribution
        }

        let score = MathSupport.clamp(
            MathSupport.logisticPercentage(zTotal, slope: EngineConstants.Recovery.logisticSlope),
            to: EngineConstants.Recovery.scoreRange
        )
        let band = RecoveryBand.band(forScore: score)
        let ceiling = targetCeiling(forRecovery: score)

        // §5.1 — each driver's share of the total magnitude, for the breakdown UI.
        let magnitude = contributions.values.reduce(into: 0.0) { $0 += abs($1) }
        var drivers: [DriverContribution] = []
        for driver in RecoveryDriver.allCases {
            guard let z = zScores[driver],
                  let weight = weights[driver],
                  let contribution = contributions[driver],
                  let observation = observations[driver] else { continue }
            drivers.append(
                DriverContribution(
                    driver: driver,
                    zScore: z,
                    weight: weight,
                    contribution: contribution,
                    share: MathSupport.safeDivide(abs(contribution), by: magnitude),
                    observedValue: observation.value,
                    baselineMean: observation.mean,
                    baselineStandardDeviation: observation.sigma
                )
            )
        }
        drivers.sort { abs($0.contribution) > abs($1.contribution) }

        let topPositive = drivers.filter { $0.contribution > 0 }.max { abs($0.contribution) < abs($1.contribution) }
        let topNegative = drivers.filter { $0.contribution < 0 }.max { abs($0.contribution) < abs($1.contribution) }
        let missing = RecoveryDriver.allCases.filter { zScores[$0] == nil }

        // The score is only as trustworthy as its least-calibrated required input.
        let confidence = min(hrv.baseline.confidence, restingHR.baseline.confidence)

        return RecoveryOutput(
            availability: .scored,
            score: score,
            band: band,
            targetStrainCeiling: ceiling,
            zTotal: zTotal,
            confidence: confidence,
            drivers: drivers,
            missingDrivers: missing,
            topPositiveDriver: topPositive,
            topNegativeDriver: topNegative,
            topPositiveSummary: topPositive?.phrase,
            topNegativeSummary: topNegative?.phrase
        )
    }

    /// §5.3 — `Ceiling = 21 · (Recovery/100)^0.65`.
    ///
    /// Reference points: 33 → 10.2 · 67 → 16.2 · 90 → 19.6.
    static func targetCeiling(forRecovery recovery: Double) -> Double {
        let fraction = MathSupport.clamp(recovery / 100, 0, 1)
        guard fraction > 0 else { return 0 }
        return EngineConstants.Strain.scaleMax
            * pow(fraction, EngineConstants.Strain.ceilingExponent)
    }

    /// §5.1 — every z-score is clamped to `[−3, +3]` after computation.
    private static func clampedZ(_ value: Double) -> Double {
        MathSupport.clamp(value, to: EngineConstants.Recovery.zClampRange)
    }
}

private extension RecoveryOutput {

    /// A suppressed result: no score, no band, no ceiling, and a reason the UI can explain.
    static func unavailable(_ reason: RecoveryUnavailableReason) -> RecoveryOutput {
        RecoveryOutput(
            availability: .unavailable(reason),
            score: nil,
            band: nil,
            targetStrainCeiling: nil,
            zTotal: nil,
            confidence: 0,
            drivers: [],
            missingDrivers: [],
            topPositiveDriver: nil,
            topNegativeDriver: nil,
            topPositiveSummary: nil,
            topNegativeSummary: nil
        )
    }

    /// A still-calibrating result, carrying `n/14` progress (§4.2.4).
    static func calibrating(daysCollected: Int, daysRequired: Int) -> RecoveryOutput {
        RecoveryOutput(
            availability: .calibrating(daysCollected: daysCollected, daysRequired: daysRequired),
            score: nil,
            band: nil,
            targetStrainCeiling: nil,
            zTotal: nil,
            confidence: BaselineEngine.calibrationProgress(sampleCount: daysCollected),
            drivers: [],
            missingDrivers: [],
            topPositiveDriver: nil,
            topNegativeDriver: nil,
            topPositiveSummary: nil,
            topNegativeSummary: nil
        )
    }
}
