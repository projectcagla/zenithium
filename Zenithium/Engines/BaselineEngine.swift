//
//  BaselineEngine.swift
//  Zenithium
//
//  The 60-day EWMA baseline shared by every engine. Spec §4 in full.
//
//  The five guards in §4.2 are all enforced here rather than at call sites:
//  1. Today never contaminates the baseline it is scored against — the caller folds a day in
//     only after scoring it, and `scoringBaseline(from:)` reads state as of yesterday.
//  2. Winsorization happens on ingest, before the update.
//  3. σ floors apply to every σ this engine hands out.
//  4. Cold start suppresses the score below 5 days and blends toward the prior below 14.
//  5. A missing day does not advance the EWMA — there is no interpolation anywhere here.
//

import Foundation

enum BaselineEngine {

    /// Folds one day's value into a metric's baseline.
    ///
    /// - Parameters:
    ///   - state: the baseline as it stands.
    ///   - sample: the day's value in the metric's canonical unit.
    ///   - day: the day the value belongs to, normalised to local midnight.
    /// - Returns: the new state plus what happened to the value.
    static func update(
        _ state: BaselineSnapshot,
        with sample: Double,
        on day: Date
    ) -> BaselineUpdate {
        let metric = state.metric

        // Reject sensor artefacts outright. §4.2.2 winsorizes *extreme but real* days; a
        // value outside the physiological range is not a day, it is a fault, and folding it
        // in — even clamped — would drag the baseline.
        guard sample.isFinite, metric.plausibleRange.contains(sample) else {
            return BaselineUpdate(
                snapshot: state,
                rawValue: sample,
                storedValue: sample,
                wasWinsorized: false,
                wasRejected: true
            )
        }

        // §4.2.5 — a day already folded in, or an out-of-order day, leaves the EWMA alone.
        // This is also what makes the whole pipeline idempotent: recomputing a day cannot
        // fold its value in twice.
        if let lastUpdated = state.lastUpdated, day <= lastUpdated {
            return BaselineUpdate(
                snapshot: state,
                rawValue: sample,
                storedValue: sample,
                wasWinsorized: false,
                wasRejected: false
            )
        }

        // §4.2.6 — seeding. Below three valid days there is no trustworthy μ or σ yet, so
        // values accumulate and no EWMA step runs.
        if state.sampleCount < EngineConstants.Baseline.minSamplesForSeed {
            return seed(state, with: sample, on: day)
        }

        // §4.2.2 — winsorize against the baseline as it stands, then fold the clamped value.
        let sigma = state.effectiveStandardDeviation
        let winsorized = MathSupport.winsorize(
            sample,
            mean: state.mean,
            sigma: sigma,
            multiple: EngineConstants.Baseline.winsorSigmaMultiple
        )
        let value = winsorized.value

        // §4.1 — the EWMA step. Variance uses the *previous* mean, which is what makes the
        // recursion match the closed form.
        let alpha = EngineConstants.Baseline.alpha
        let previousMean = state.mean
        let deviation = value - previousMean
        let newMean = alpha * value + (1 - alpha) * previousMean
        let newVariance = (1 - alpha) * (state.variance + alpha * deviation * deviation)

        let snapshot = BaselineSnapshot(
            metric: metric,
            mean: newMean,
            variance: max(newVariance, 0),
            sampleCount: state.sampleCount + 1,
            lastUpdated: day,
            seedValues: []
        )
        return BaselineUpdate(
            snapshot: snapshot,
            rawValue: sample,
            storedValue: value,
            wasWinsorized: winsorized.wasClamped,
            wasRejected: false
        )
    }

    /// §4.2.6 — accumulates values until three are available, then seeds μ and V from them.
    ///
    /// ASSUMPTION BASE-2: no winsorization happens here, because clamping against a
    /// one-sample σ would freeze the baseline near its first value.
    private static func seed(
        _ state: BaselineSnapshot,
        with sample: Double,
        on day: Date
    ) -> BaselineUpdate {
        let metric = state.metric
        var values = state.seedValues
        values.append(sample)

        let prior = metric.prior
        let priorVariance = prior.standardDeviation * prior.standardDeviation

        if values.count >= EngineConstants.Baseline.minSamplesForSeed {
            // μ₀ is the mean of the first ≥ 3 valid days; V₀ their sample variance.
            let seededMean = MathSupport.mean(values) ?? prior.mean
            let seededVariance = MathSupport.sampleVariance(values) ?? priorVariance
            let snapshot = BaselineSnapshot(
                metric: metric,
                mean: seededMean,
                variance: max(seededVariance, 0),
                sampleCount: values.count,
                lastUpdated: day,
                seedValues: []
            )
            return BaselineUpdate(
                snapshot: snapshot,
                rawValue: sample,
                storedValue: sample,
                wasWinsorized: false,
                wasRejected: false
            )
        }

        // Still collecting. The running mean is kept so the calibrating UI has something
        // honest to show; the variance stays at the prior until there is enough to measure.
        let snapshot = BaselineSnapshot(
            metric: metric,
            mean: MathSupport.mean(values) ?? prior.mean,
            variance: priorVariance,
            sampleCount: values.count,
            lastUpdated: day,
            seedValues: values
        )
        return BaselineUpdate(
            snapshot: snapshot,
            rawValue: sample,
            storedValue: sample,
            wasWinsorized: false,
            wasRejected: false
        )
    }

    /// Rebuilds a baseline from a series of daily samples, oldest first.
    ///
    /// Used for the initial 60-day backfill and for an engine-version rebuild (§7). Feeding
    /// the same series twice produces the same state, because `update` refuses to re-fold a
    /// day it has already seen.
    static func rebuild(
        metric: MetricKind,
        from samples: [DailyMetricSample]
    ) -> BaselineSnapshot {
        var state = BaselineSnapshot.empty(metric: metric)
        for sample in samples.sorted(by: { $0.dayStart < $1.dayStart }) {
            state = update(state, with: sample.value, on: sample.dayStart).snapshot
        }
        return state
    }

    /// The baseline a value should actually be scored against (§4.2.3, §4.2.4).
    ///
    /// - `n < 5` → not scorable at all.
    /// - `5 ≤ n < 14` → blended toward the population prior with `w = n/14`.
    /// - `n ≥ 14` → fully personal.
    ///
    /// ASSUMPTION BASE-4: wrist temperature blends σ only. Its prior is stated on the `ΔT`
    /// scale (mean 0) while its EWMA tracks the absolute reading (BASE-3), so blending its
    /// mean toward 0 would be meaningless.
    ///
    /// ASSUMPTION BASE-5: σ is blended toward the prior on the same `w` as μ. The
    /// specification blends only μ, but a σ measured from six days is at least as unreliable
    /// as a mean measured from six days, and the σ floor alone does not address it.
    static func scoringBaseline(from state: BaselineSnapshot) -> ScoringBaseline {
        let metric = state.metric
        let prior = metric.prior
        let sampleCount = state.sampleCount
        let confidence = MathSupport.clamp(
            Double(sampleCount) / Double(EngineConstants.Baseline.fullConfidenceSamples),
            0,
            1
        )
        let isScorable = sampleCount >= EngineConstants.Baseline.minSamplesForScore

        let personalSigma = state.standardDeviation
        let blendedSigma = confidence * personalSigma + (1 - confidence) * prior.standardDeviation
        let sigma = max(blendedSigma, metric.sigmaFloor)

        let mean: Double
        if metric.isScoredAsDeviation {
            mean = state.mean
        } else {
            mean = confidence * state.mean + (1 - confidence) * prior.mean
        }

        return ScoringBaseline(
            metric: metric,
            mean: mean,
            standardDeviation: sigma,
            sampleCount: sampleCount,
            confidence: confidence,
            isScorable: isScorable
        )
    }

    /// The calibration progress a `.calibrating` view state shows, `n/14` (§4.2.4).
    static func calibrationProgress(sampleCount: Int) -> Double {
        MathSupport.clamp(
            Double(sampleCount) / Double(EngineConstants.Baseline.fullConfidenceSamples),
            0,
            1
        )
    }
}
