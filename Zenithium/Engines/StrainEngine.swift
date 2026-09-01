//
//  StrainEngine.swift
//  Zenithium
//
//  Cardiovascular strain. Spec §5.3 in full.
//
//      x(t)        = clamp((HR(t) − RHR) / (HRmax − RHR), 0, 1)
//      Δt_i        = clamp(t_i − t_{i−1}, 0, 60 s)      gaps > 120 s contribute nothing
//      TRIMP       = Σ (Δt_i/60) · x_i · b · e^(c · x_i)
//      DailyStrain = 21 · (1 − e^(−0.0065 · TRIMP))
//
//  Calibration anchors this must reproduce (±0.1):
//      TRIMP  65 → 7.2 · 135 → 12.3 · 200 → 15.3 · 365 → 19.0 · 500 → 20.2
//

import Foundation

enum StrainEngine {

    static func compute(_ input: StrainInput) -> StrainOutput {
        let constants = EngineConstants.Strain.trimpConstants(for: input.biologicalSex)

        // §15 rule 8 — the reserve is the denominator of every `x(t)`, so a degenerate
        // `HRmax ≤ RHR` is floored rather than allowed to divide by zero or go negative.
        let reserve = max(
            input.maxHeartRate - input.restingHeartRate,
            EngineConstants.Strain.minimumHeartRateReserve
        )

        // ASSUMPTION STRAIN-1 — resume from the anchor so a recompute extends the day
        // forward rather than rebuilding it, which is what keeps the value monotonic.
        let anchor = input.anchor
        var trimp = anchor?.trimp ?? 0
        var zoneSeconds = normalizedZoneSeconds(anchor?.zoneSeconds)
        var previousTimestamp = anchor?.throughTimestamp ?? input.dayWindow.start
        var lastTimestamp = previousTimestamp
        var contributingSamples = 0
        var uncoveredSeconds: Double = 0

        let samples = input.samples
            .filter { $0.isPlausible && $0.timestamp > previousTimestamp && $0.timestamp <= input.dayWindow.end }
            .sorted { $0.timestamp < $1.timestamp }

        for sample in samples {
            let gap = sample.timestamp.timeIntervalSince(previousTimestamp)
            previousTimestamp = sample.timestamp
            lastTimestamp = sample.timestamp

            // ASSUMPTION STRAIN-2 — a gap longer than the cut-off opens a new segment and
            // contributes nothing. The time is recorded as uncovered so the UI can say
            // coverage was sparse rather than implying an easy day.
            guard gap <= EngineConstants.Strain.maxGapSeconds else {
                uncoveredSeconds += gap
                continue
            }
            let delta = MathSupport.clamp(gap, 0, EngineConstants.Strain.maxSegmentSeconds)
            guard delta > 0 else { continue }

            let x = MathSupport.clamp(
                MathSupport.safeDivide(sample.beatsPerMinute - input.restingHeartRate, by: reserve),
                0,
                1
            )
            let minutes = delta / TimeConversion.secondsPerMinute
            trimp += minutes * x * constants.b * exp(constants.c * x)

            let zone = HeartRateZone.zone(forReserveFraction: x)
            zoneSeconds[zone.index] += delta
            contributingSamples += 1
        }

        let rawStrain = strain(forTRIMP: trimp)

        // ASSUMPTION STRAIN-1 — a recompute may raise a value the user has already seen but
        // never lower it.
        let previous = input.previouslyReportedStrain ?? 0
        let wasClamped = rawStrain < previous
        let finalStrain = max(rawStrain, previous)

        let ceiling = input.recoveryScore.map(RecoveryEngine.targetCeiling(forRecovery:))

        return StrainOutput(
            strain: finalStrain,
            trimp: trimp,
            anchor: StrainAnchor(
                trimp: trimp,
                throughTimestamp: lastTimestamp,
                zoneSeconds: zoneSeconds
            ),
            zoneSeconds: zoneSeconds,
            targetCeiling: ceiling,
            wasClampedToPreviousValue: wasClamped,
            maxHeartRateUsed: input.maxHeartRate,
            maxHeartRateSource: input.maxHeartRateSource,
            contributingSampleCount: contributingSamples,
            uncoveredSeconds: uncoveredSeconds
        )
    }

    /// §5.3 — `DailyStrain = 21 · (1 − e^(−k · TRIMP))`.
    ///
    /// Defined by `StrainScale`, which the watch also compiles. Kept here as a forwarder so
    /// the phone's call sites read the same as they always did. Yol haritası v4, C1.
    static func strain(forTRIMP trimp: Double) -> Double {
        StrainScale.strain(forTRIMP: trimp)
    }

    /// The inverse of `strain(forTRIMP:)`. See `StrainScale.trimp(forStrain:)`.
    ///
    /// Faz 19 needs this to forecast a session: rather than guessing what a planned run
    /// costs, the same integral that scores a finished day is run backwards, so the number
    /// on the prescription is on the same scale as the number the user sees tonight.
    static func trimp(forStrain strain: Double) -> Double? {
        StrainScale.trimp(forStrain: strain)
    }

    /// TRIMP for a planned session held at a fixed fraction of heart-rate reserve.
    static func trimp(
        forMinutes minutes: Double,
        reserveFraction: Double,
        biologicalSex: BiologicalSexValue
    ) -> Double {
        StrainScale.trimp(
            forMinutes: minutes,
            reserveFraction: reserveFraction,
            biologicalSex: biologicalSex
        )
    }

    /// How many minutes at `reserveFraction` reach `trimp`.
    static func minutes(
        forTRIMP trimp: Double,
        reserveFraction: Double,
        biologicalSex: BiologicalSexValue
    ) -> Double? {
        StrainScale.minutes(
            forTRIMP: trimp,
            reserveFraction: reserveFraction,
            biologicalSex: biologicalSex
        )
    }

    /// §5.4 — the same mapping on the 0…100 scale, for a session's muscle load.
    static func sessionLoad(forTRIMP trimp: Double) -> Double {
        guard trimp.isFinite, trimp > 0 else { return 0 }
        let exponent = MathSupport.clamp(-EngineConstants.Strain.trimpScaleK * trimp, -60, 0)
        return MathSupport.clamp(
            100 * (1 - exp(exponent)),
            to: EngineConstants.Fatigue.sessionLoadRange
        )
    }

    /// §5.4 — a logged strength session's load,
    /// `clamp(Σ(sets · reps · RPE) / 3.0, 0, 100)`.
    static func sessionLoad(forVolumeLoad volumeLoad: Double) -> Double {
        MathSupport.clamp(
            MathSupport.safeDivide(volumeLoad, by: EngineConstants.Fatigue.strengthLoadDivisor),
            to: EngineConstants.Fatigue.sessionLoadRange
        )
    }

    /// TRIMP for one bounded interval of the intraday series, used to attribute a workout's
    /// share of the day to the muscle engine (§5.4).
    ///
    /// This deliberately re-integrates from the samples rather than apportioning the daily
    /// total, so a workout's load does not change when the rest of the day does.
    static func trimp(
        for interval: DateInterval,
        samples: [HeartRateSample],
        restingHeartRate: Double,
        maxHeartRate: Double,
        biologicalSex: BiologicalSexValue
    ) -> Double {
        let constants = biologicalSex.trimpConstants
        let reserve = max(
            maxHeartRate - restingHeartRate,
            EngineConstants.Strain.minimumHeartRateReserve
        )
        let window = samples
            .filter { $0.isPlausible && interval.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
        guard let first = window.first else { return 0 }

        var total: Double = 0
        var previous = first.timestamp
        for sample in window.dropFirst() {
            let gap = sample.timestamp.timeIntervalSince(previous)
            previous = sample.timestamp
            guard gap <= EngineConstants.Strain.maxGapSeconds else { continue }
            let delta = MathSupport.clamp(gap, 0, EngineConstants.Strain.maxSegmentSeconds)
            guard delta > 0 else { continue }
            let x = MathSupport.clamp(
                MathSupport.safeDivide(sample.beatsPerMinute - restingHeartRate, by: reserve),
                0,
                1
            )
            total += (delta / TimeConversion.secondsPerMinute) * x * constants.b * exp(constants.c * x)
        }
        return total
    }

    // MARK: - HRmax resolution

    /// §5.3 — `HRmax` = user override if set, else `max(observed 12-month max, Tanaka)`.
    ///
    /// ASSUMPTION HRMAX-1: with no age available the estimate assumes 35, and the source is
    /// reported as `.tanakaAssumedAge` so the UI can invite a correction and the log can say
    /// once that the assumption was used.
    /// ASSUMPTION HRMAX-2: `observed` is a percentile of daily maxima, not a raw maximum.
    static func resolveMaxHeartRate(
        override: Double?,
        observed: Double?,
        age: Int?
    ) -> (value: Double, source: MaxHeartRateSource) {
        if let override, override.isFinite, override > 0 {
            return (override, .userOverride)
        }
        let effectiveAge = age ?? EngineConstants.Strain.assumedAgeYears
        let tanaka = EngineConstants.Strain.tanakaIntercept
            - EngineConstants.Strain.tanakaSlope * Double(effectiveAge)
        let tanakaSource: MaxHeartRateSource = age == nil ? .tanakaAssumedAge : .tanaka

        guard let observed, observed.isFinite, observed > 0 else {
            return (tanaka, tanakaSource)
        }
        return observed >= tanaka ? (observed, .observed) : (tanaka, tanakaSource)
    }

    // MARK: - Helpers

    /// Ensures a zone array is exactly six long, so positional access is always in range.
    private static func normalizedZoneSeconds(_ seconds: [Double]?) -> [Double] {
        let zoneCount = HeartRateZone.allCases.count
        guard let seconds else { return Array(repeating: 0, count: zoneCount) }
        if seconds.count == zoneCount { return seconds }
        var normalized = Array(repeating: 0.0, count: zoneCount)
        for (index, value) in seconds.enumerated() where index < zoneCount {
            normalized[index] = value
        }
        return normalized
    }
}
