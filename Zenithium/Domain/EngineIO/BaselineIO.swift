//
//  BaselineIO.swift
//  Zenithium
//
//  Baseline engine input and output. Spec §4 in full.
//

import Foundation

/// The persisted state of one metric's 60-day EWMA (§4.1), as a pure value type.
///
/// `Models/BaselineState.swift` is the SwiftData mirror of this; the engine only ever sees
/// the value type.
struct BaselineSnapshot: Sendable, Equatable, Hashable, Codable {

    /// Which metric this baseline tracks.
    let metric: MetricKind

    /// `μ_t` — the EWMA mean.
    let mean: Double

    /// `V_t` — the EWMA variance.
    let variance: Double

    /// `n` — the number of valid days folded in.
    let sampleCount: Int

    /// The day of the most recent fold. `nil` before seeding. A gap does not advance the
    /// EWMA, so this is how gaps are detected (§4.2.5).
    let lastUpdated: Date?

    /// Values collected before the seed threshold is reached (§4.2.6). Empty once seeded.
    let seedValues: [Double]

    init(
        metric: MetricKind,
        mean: Double,
        variance: Double,
        sampleCount: Int,
        lastUpdated: Date?,
        seedValues: [Double]
    ) {
        self.metric = metric
        self.mean = mean
        self.variance = variance
        self.sampleCount = sampleCount
        self.lastUpdated = lastUpdated
        self.seedValues = seedValues
    }

    /// A baseline that has seen nothing yet.
    static func empty(metric: MetricKind) -> BaselineSnapshot {
        BaselineSnapshot(
            metric: metric,
            mean: metric.prior.mean,
            variance: metric.prior.standardDeviation * metric.prior.standardDeviation,
            sampleCount: 0,
            lastUpdated: nil,
            seedValues: []
        )
    }

    /// `σ_t = √V_t`, before the floor is applied.
    var standardDeviation: Double {
        variance > 0 ? variance.squareRoot() : 0
    }

    /// `σ_eff = max(σ, floor)` — used in every z-score (§4.2.3).
    var effectiveStandardDeviation: Double {
        max(standardDeviation, metric.sigmaFloor)
    }

    /// Whether the baseline has been seeded from at least three valid days (§4.2.6).
    var isSeeded: Bool {
        sampleCount >= 3
    }
}

/// The result of folding one day's value into a baseline.
struct BaselineUpdate: Sendable, Equatable {

    /// The state after the fold.
    let snapshot: BaselineSnapshot

    /// The value as it arrived.
    let rawValue: Double

    /// The value after winsorization to `μ ± 3σ` (§4.2.2). Equal to `rawValue` when no
    /// clamping was needed, or when the baseline was too thin to winsorize (ASSUMPTION BASE-2).
    let storedValue: Double

    /// Whether the raw value was clamped. Logged, and surfaced in the trends detail so a
    /// clipped outlier is visible rather than silently rewritten.
    let wasWinsorized: Bool

    /// Whether the value was rejected outright as implausible (`MetricKind.plausibleRange`).
    /// A rejected value leaves the baseline untouched.
    let wasRejected: Bool

    init(
        snapshot: BaselineSnapshot,
        rawValue: Double,
        storedValue: Double,
        wasWinsorized: Bool,
        wasRejected: Bool
    ) {
        self.snapshot = snapshot
        self.rawValue = rawValue
        self.storedValue = storedValue
        self.wasWinsorized = wasWinsorized
        self.wasRejected = wasRejected
    }
}

/// The baseline a value is scored against, after cold-start prior blending (§4.2.4).
///
/// This is what the recovery engine consumes: it never sees the raw EWMA state, only the
/// mean and sigma it should actually divide by, plus the confidence that produced them.
///
/// **Wrist temperature is blended differently.** Its prior is expressed on the `ΔT` scale
/// (mean 0, σ 0.35), while its EWMA tracks the *absolute* reading (ASSUMPTION BASE-3).
/// Blending the personal absolute mean toward a prior mean of 0 would be meaningless, so for
/// `MetricKind.wristTemperature` the mean stays fully personal and only σ is blended toward
/// the prior. Every other metric blends both, per §4.2.4.
struct ScoringBaseline: Sendable, Equatable, Hashable {

    let metric: MetricKind

    /// `μ_used = w·μ_personal + (1−w)·μ_prior`, `w = min(n/14, 1)` (§4.2.4).
    let mean: Double

    /// The blended σ, floored (§4.2.3).
    let standardDeviation: Double

    /// `n`, the number of valid personal days.
    let sampleCount: Int

    /// `w = min(n/14, 1)` — also the value surfaced as the score's confidence.
    let confidence: Double

    /// Whether `n ≥ 5`, the threshold below which no score may be shown (§4.2.4).
    let isScorable: Bool

    init(
        metric: MetricKind,
        mean: Double,
        standardDeviation: Double,
        sampleCount: Int,
        confidence: Double,
        isScorable: Bool
    ) {
        self.metric = metric
        self.mean = mean
        self.standardDeviation = standardDeviation
        self.sampleCount = sampleCount
        self.confidence = confidence
        self.isScorable = isScorable
    }
}

/// One metric's value paired with the baseline it is scored against.
struct MetricObservation: Sendable, Equatable, Hashable {

    /// The value recorded for the scored day, in canonical units.
    let value: Double

    /// The baseline as of *yesterday* (§4.2.1) — today's value never contaminates it.
    let baseline: ScoringBaseline

    init(value: Double, baseline: ScoringBaseline) {
        self.value = value
        self.baseline = baseline
    }

    var metric: MetricKind { baseline.metric }

    /// The quantity actually scored: the raw value, or its deviation from the baseline mean
    /// for wrist temperature (§3, ASSUMPTION BASE-3).
    var scoredQuantity: Double {
        metric.isScoredAsDeviation ? value - baseline.mean : value
    }
}
