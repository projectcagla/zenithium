//
//  EngineConstants.swift
//  Zenithium
//
//  Every magic number in the app, each citing the section of the specification it comes from.
//
//  ASSUMPTION CONST-1: a value that *defines a taxonomy* — a band cut-off, a σ floor, a
//  population prior, a mass class, a zone band — is declared on the `Domain` type that owns
//  the taxonomy, and forwarded here. A value used in a *formula* is declared here. Each
//  number therefore has exactly one definition site, which is the point of the §9 rule.
//
//  ASSUMPTION CONST-2: this file is a **leaf** in the dependency graph. It may read `Domain`
//  and nothing else, and every layer may read it. That is what lets `Health` take its
//  downsampling interval and `Models` take its sleep-need default from here without either
//  of them depending on the engines, and without the number being written down twice.
//

import Foundation

enum EngineConstants {

    /// The version stamped on every computed record. Bumping it triggers a backfill (§7).
    static let engineVersion: Int = 1

    // MARK: - Baseline (§4)

    enum Baseline {

        /// §4.1 — the EWMA window in days.
        static let windowDays: Int = 60

        /// §4.1 — `α = 2/(60+1)`.
        static let alpha: Double = 2.0 / 61.0

        /// §4.2.2 — winsorize to `μ ± 3σ` before folding a value in.
        static let winsorSigmaMultiple: Double = 3.0

        /// §4.2.4 — below this many valid days there is no score at all.
        static let minSamplesForScore: Int = 5

        /// §4.2.4 — at this many valid days the baseline is fully personal, `w = 1`.
        static let fullConfidenceSamples: Int = 14

        /// §4.2.6 — `μ₀` is the mean of the first ≥ 3 valid days.
        static let minSamplesForSeed: Int = 3

        /// ASSUMPTION BASE-2 — winsorization is skipped below this many days, because
        /// clamping against a one-sample σ would freeze the baseline near its first value.
        static let minSamplesForWinsorization: Int = 3

        /// §4.2.3 — forwards to the metric that owns the floor (ASSUMPTION CONST-1).
        static func sigmaFloor(for metric: MetricKind) -> Double {
            metric.sigmaFloor
        }

        /// §4.2.4 — forwards to the metric that owns the prior (ASSUMPTION CONST-1).
        static func prior(for metric: MetricKind) -> MetricPrior {
            metric.prior
        }
    }

    // MARK: - Recovery (§5.1)

    enum Recovery {

        /// §5.1 — forwards to the driver that owns its weight (ASSUMPTION CONST-1).
        static func weight(for driver: RecoveryDriver) -> Double {
            driver.specWeight
        }

        /// §5.1 — every z-score is clamped to this range after computation.
        static let zClampRange: ClosedRange<Double> = -3.0...3.0

        /// §5.1 — `SleepNorm = clamp((SleepScore − 70) / 15, −3, +3)`.
        static let sleepNormCenter: Double = 70.0
        static let sleepNormScale: Double = 15.0

        /// §5.1 — `Recovery = 100 / (1 + e^(−1.2·Z_total))`.
        static let logisticSlope: Double = 1.2

        /// §5.1 — the score is clamped into 1…100.
        static let scoreRange: ClosedRange<Double> = 1.0...100.0

        /// §5.1 — band cut-offs forward to `RecoveryBand` (ASSUMPTION CONST-1).
        static let redUpperBound: Double = RecoveryBand.redUpperBound
        static let yellowUpperBound: Double = RecoveryBand.yellowUpperBound
    }

    // MARK: - Sleep (§5.2)

    enum Sleep {

        /// §5.2 — `baselineNeed`, hours. Forwards to the profile default.
        static let defaultBaselineNeedHours: Double = 8.0

        /// §5.2 — `+ 0.25 · (yesterdayStrain / 21)`.
        static let strainNeedCoefficient: Double = 0.25

        /// §5.2 — `+ min(sleepDebt_h, 1.5)`.
        static let maxDebtContributionHours: Double = 1.5

        /// §5.2 — debt decays 25 % per night, accumulated over 7 nights.
        static let debtDecayPerNight: Double = 0.25
        static let debtWindowNights: Int = 7

        /// §5.2 — `− napCredit_h`, capped at 1.0 h, naps ≥ 20 min.
        static let maxNapCreditHours: Double = 1.0
        static let minNapSeconds: Double = 1200
        /// Maximum plausible daytime nap (3 hours). Longer segments are not physiological naps.
        static let maxNapSeconds: Double = 3 * 3600

        /// ASSUMPTION SLEEP-4 — naps count from the previous day.
        static let napLookbackDays: Int = 1

        /// §5.2 — `Efficiency = 100 · clamp((asleep/timeInBed − 0.75) / 0.20, 0, 1)`.
        static let efficiencyFloor: Double = 0.75
        static let efficiencySpan: Double = 0.20

        /// §5.2 — `Restorative = 100 · clamp(((deep + REM) / asleep) / 0.42, 0, 1)`.
        static let restorativeTarget: Double = 0.42

        /// §5.2 — `Consistency = 100 · max(0, 1 − |Δmidpoint| / 90 min)` over 14 days.
        static let consistencyToleranceMinutes: Double = 90.0
        static let consistencyWindowDays: Int = 14

        /// §5.2 — component weights.
        static func weight(for component: SleepComponent) -> Double {
            switch component {
            case .duration: return 0.50
            case .efficiency: return 0.20
            case .restorative: return 0.20
            case .consistency: return 0.10
            }
        }

        /// §5.6 — a night outside this range is rejected and flagged `.suspect`.
        static let minValidSleepSeconds: Double = 2 * 3600
        static let maxValidSleepSeconds: Double = 14 * 3600

        /// ASSUMPTION SLEEP-2 — asleep blocks tolerate gaps up to this long.
        static let contiguityToleranceSeconds: Double = 900

        /// ASSUMPTION SLEEP-1 — the window a night's midpoint must fall in, as hours from
        /// local midnight of the wake day. −6 h is 18:00 the previous evening.
        static let nightWindowStartHour: Double = -6
        static let nightWindowEndHour: Double = 12

        /// Minutes in a day, for the circular midpoint mean (ASSUMPTION SLEEP-5).
        static let minutesPerDay: Double = 1440
    }

    // MARK: - Strain (§5.3)

    enum Strain {

        /// §5.3 — the Whoop-scale ceiling.
        static let scaleMax: Double = 21.0

        /// §5.3 — `DailyStrain = 21 · (1 − e^(−k · TRIMP))`. Calibrated; do not change.
        static let trimpScaleK: Double = 0.0065

        /// §5.3 — Tanaka: `HRmax = 208 − 0.7 · age`.
        static let tanakaIntercept: Double = 208.0
        static let tanakaSlope: Double = 0.7

        /// §5.3, ASSUMPTION HRMAX-1 — age assumed when no date of birth is available.
        static let assumedAgeYears: Int = 35

        /// §5.3 — how far back the observed maximum looks.
        static let observedMaxLookbackDays: Int = 365

        /// ASSUMPTION HRMAX-2 — the percentile of daily maxima taken as observed `HRmax`.
        static let observedMaxPercentile: Double = 0.995

        /// §5.3 — the Banister constants, forwarded to the type that owns them.
        static func trimpConstants(for sex: BiologicalSexValue) -> TRIMPConstants {
            sex.trimpConstants
        }

        /// §5.3 — `Δt_i = clamp(t_i − t_{i−1}, 0, 60 s)`.
        static let maxSegmentSeconds: Double = 60.0

        /// §5.3, ASSUMPTION STRAIN-2 — a gap longer than this contributes nothing.
        static let maxGapSeconds: Double = 120.0

        /// §5.3 — `Ceiling = 21 · (Recovery/100)^0.65`.
        static let ceilingExponent: Double = 0.65

        /// The smallest heart-rate reserve the denominator may take, so a degenerate
        /// `HRmax ≤ RHR` cannot divide by zero (§15 rule 8).
        static let minimumHeartRateReserve: Double = 1.0

        /// ASSUMPTION DAY-1 — the local hour the day starts on when no wake time exists.
        static let dayBoundaryFallbackHour: Int = DayBoundary.fallbackHour
    }

    // MARK: - Fatigue (§5.4)

    enum Fatigue {

        /// §5.4 — `t½ = 24 h · sleepModifier · massClass`.
        static let baseHalfLifeHours: Double = 24.0

        /// §5.4 — `sleepModifier = clamp(1.35 − 0.006 · SleepScore, 0.75, 1.35)`.
        static let sleepModifierIntercept: Double = 1.35
        static let sleepModifierSlope: Double = 0.006
        static let sleepModifierRange: ClosedRange<Double> = 0.75...1.35

        /// §5.4 — the mass-class multiplier, forwarded to the taxonomy (ASSUMPTION CONST-1).
        static func massClassMultiplier(for massClass: MassClass) -> Double {
            switch massClass {
            case .large: return 1.15
            case .medium: return 1.00
            case .small: return 0.85
            }
        }

        /// §5.4 — `sessionLoad = clamp(Σ(sets · reps · RPE) / 3.0, 0, 100)`.
        static let strengthLoadDivisor: Double = 3.0

        /// §5.4 — `sessionLoad ∈ [0, 100]` and `Fatigue ≤ 100`.
        static let sessionLoadRange: ClosedRange<Double> = 0...100
        static let fatigueCeiling: Double = 100.0

        /// ASSUMPTION MUSCLE-3 — sessions older than this contribute under 1 % at the
        /// shortest half-life, so they are not projected.
        static let projectionWindowDays: Int = 14

        /// The smallest decayed contribution counted as "still contributing", for the
        /// session count shown in the muscle detail view.
        static let contributionEpsilon: Double = 0.5
    }

    // MARK: - Circadian (§5.5)

    enum Circadian {

        /// §5.5 — the specification's anchor set, measured from the sleep midpoint.
        ///
        /// ASSUMPTION CIRC-1: this is the default, and it is injectable precisely because
        /// §5.5 flags the `Mid + 8.0 h` afternoon dip as a spec risk.
        static let midpointAnchors = CircadianAnchors(
            anchors: [
                CircadianAnchor(event: .wakeInertiaEnd, offsetHours: 2.0, alertness: 55),
                CircadianAnchor(event: .morningPeak, offsetHours: 4.5, alertness: 100),
                CircadianAnchor(event: .afternoonDip, offsetHours: 8.0, alertness: 62),
                CircadianAnchor(event: .secondaryPeak, offsetHours: 11.5, alertness: 88),
                CircadianAnchor(event: .melatoninOnset, offsetHours: 15.0, alertness: 30),
                CircadianAnchor(event: .sleepTrough, offsetHours: 18.5, alertness: 8)
            ],
            reference: .sleepMidpoint
        )

        /// ASSUMPTION CIRC-1 — the wake-anchored alternative, provided but not default.
        ///
        /// The offsets re-place the same six events relative to wake, which puts the
        /// afternoon dip near seven hours after waking rather than 4.75 h after it.
        static let wakeAnchors = CircadianAnchors(
            anchors: [
                CircadianAnchor(event: .wakeInertiaEnd, offsetHours: 0.5, alertness: 55),
                CircadianAnchor(event: .morningPeak, offsetHours: 3.0, alertness: 100),
                CircadianAnchor(event: .afternoonDip, offsetHours: 7.0, alertness: 62),
                CircadianAnchor(event: .secondaryPeak, offsetHours: 10.0, alertness: 88),
                CircadianAnchor(event: .melatoninOnset, offsetHours: 13.5, alertness: 30),
                CircadianAnchor(event: .sleepTrough, offsetHours: 17.0, alertness: 8)
            ],
            reference: .wakeTime
        )

        /// ASSUMPTION CIRC-1 — the default anchor set. Change this line to re-anchor.
        static let defaultAnchors = midpointAnchors

        /// §5.5 — `amplitude = 0.7 + 0.3 · (Recovery/100)`.
        static let amplitudeBase: Double = 0.7
        static let amplitudeRecoveryCoefficient: Double = 0.3

        /// ASSUMPTION CIRC-2 — 5-minute sampling, 288 points per day.
        static let sampleIntervalSeconds: TimeInterval = 300

        /// §11 — the arc may never exceed this anywhere.
        static let maxAlertness: Double = 100.0

        /// The period the curve wraps over.
        static let periodHours: Double = 24.0
    }

    // MARK: - Orchestration

    /// Faz 14 — the shared load mathematics under every lens.
    enum TrainingLoad {

        /// Short-horizon window, in days.
        static let acuteWindowDays: Int = 7

        /// Long-horizon window, in days.
        static let chronicWindowDays: Int = 28

        /// `α = 2/(N+1)` for the acute series. Williams (2017) showed the exponentially
        /// weighted ratio tracks changes sooner than the rolling-average form, which lags
        /// by half its window — the same reason §4.1 uses an EWMA for baselines.
        static let acuteAlpha: Double = 2.0 / 8.0

        /// `α = 2/(N+1)` for the chronic series.
        static let chronicAlpha: Double = 2.0 / 29.0

        /// The ratio is suppressed below this many days carrying load in the chronic
        /// window. A ratio computed against two training days is arithmetic, not a signal.
        static let minimumActiveDaysForRatio: Int = 8

        /// Banister's fitness time constant, in days.
        static let fitnessTimeConstantDays: Double = 42

        /// Banister's fatigue time constant, in days.
        static let fatigueTimeConstantDays: Double = 7

        /// Monotony is undefined when the week's standard deviation is at or below this,
        /// which happens when every day is identical — including every day being zero.
        static let monotonyStandardDeviationFloor: Double = 0.5

        /// Monotony is capped here for display. Above it the figure stops discriminating.
        static let monotonyCeiling: Double = 6.0
    }

    enum Orchestration {

        /// ASSUMPTION BG-2 — observer events are coalesced over this window.
        static let observerDebounceSeconds: TimeInterval = 30

        /// ASSUMPTION BG-1 — the background refresh task identifier.
        static let backgroundTaskIdentifier = "com.zenithium.refresh.daily"

        /// ASSUMPTION BG-1 — how long after wake the background refresh may first run.
        static let backgroundEarliestOffsetMinutes: Double = 30

        /// ASSUMPTION BG-1 — the fallback hour when no wake time is known.
        static let backgroundFallbackHour: Int = 6

        /// §8 — intraday downsampling, forwarded to the Health boundary that applies it.
        static let intradayDownsampleSeconds: TimeInterval = 5

        /// How many days a full rebuild recomputes.
        static let backfillWindowDays: Int = 90
    }
}
