//
//  SleepScoreEngine.swift
//  Zenithium
//
//  The sleep score. Spec §5.2 in full, §5.6 for the validity rules.
//
//      need_h      = baselineNeed + 0.25·(yesterdayStrain/21) + min(debt, 1.5) − napCredit
//      Duration    = 100 · clamp(asleep_h / need_h, 0, 1)                       w 0.50
//      Efficiency  = 100 · clamp((asleep/timeInBed − 0.75) / 0.20, 0, 1)        w 0.20
//      Restorative = 100 · clamp(((deep + REM) / asleep) / 0.42, 0, 1)          w 0.20
//      Consistency = 100 · max(0, 1 − |midpoint − μ_14d| / 90 min)              w 0.10
//

import Foundation

enum SleepScoreEngine {

    static func compute(_ input: SleepInput) -> SleepOutput {
        let asleepHours = TimeConversion.hours(fromSeconds: input.asleepSeconds)
        let needHours = need(for: input)
        let appliedDebt = min(max(input.sleepDebtHours, 0), EngineConstants.Sleep.maxDebtContributionHours)
        let appliedNapCredit = min(max(input.napCreditHours, 0), EngineConstants.Sleep.maxNapCreditHours)

        let validity = validity(for: input)
        guard validity.isScorable else {
            return SleepOutput(
                score: nil,
                needHours: needHours,
                asleepHours: asleepHours,
                components: [],
                droppedComponents: SleepComponent.allCases,
                validity: validity,
                appliedDebtHours: appliedDebt,
                appliedNapCreditHours: appliedNapCredit
            )
        }

        // Raw component scores. A component whose input is unavailable is `nil`, which drops
        // it and renormalizes the survivors (§5.2) — it is never scored as zero.
        var rawScores: [SleepComponent: Double] = [:]

        rawScores[.duration] = 100 * MathSupport.clamp(
            MathSupport.safeDivide(asleepHours, by: needHours),
            0,
            1
        )

        if input.timeInBedSeconds > 0 {
            let rawEfficiency = MathSupport.safeDivide(input.asleepSeconds, by: input.timeInBedSeconds)
            let efficiency = min(rawEfficiency, 1.0)
            rawScores[.efficiency] = 100 * MathSupport.clamp(
                MathSupport.safeDivide(
                    efficiency - EngineConstants.Sleep.efficiencyFloor,
                    by: EngineConstants.Sleep.efficiencySpan
                ),
                0,
                1
            )
        }

        if input.hasStageData, input.asleepSeconds > 0 {
            let restorativeFraction = MathSupport.safeDivide(
                input.deepSeconds + input.remSeconds,
                by: input.asleepSeconds
            )
            rawScores[.restorative] = 100 * MathSupport.clamp(
                MathSupport.safeDivide(restorativeFraction, by: EngineConstants.Sleep.restorativeTarget),
                0,
                1
            )
        }

        if let baselineMinutes = input.midpointBaselineMinutes {
            // ASSUMPTION SLEEP-5 — a circular difference, so 23:50 and 00:10 are 20 minutes
            // apart rather than most of a day.
            let deltaMinutes = abs(
                MathSupport.circularDifference(
                    input.midpointMinutesFromLocalMidnight,
                    baselineMinutes,
                    period: EngineConstants.Sleep.minutesPerDay
                )
            )
            let drift = MathSupport.safeDivide(
                deltaMinutes,
                by: EngineConstants.Sleep.consistencyToleranceMinutes,
                fallback: 1
            )
            rawScores[.consistency] = 100 * max(0, 1 - drift)
        }

        // §5.2 — renormalize the surviving weights to sum to 1.0.
        var survivingWeights: [SleepComponent: Double] = [:]
        for component in SleepComponent.allCases where rawScores[component] != nil {
            survivingWeights[component] = EngineConstants.Sleep.weight(for: component)
        }
        let normalizedWeights = MathSupport.renormalize(survivingWeights)

        var components: [SleepComponentScore] = []
        var total: Double = 0
        for component in SleepComponent.allCases {
            guard let score = rawScores[component], let weight = normalizedWeights[component] else {
                continue
            }
            components.append(
                SleepComponentScore(component: component, score: score, weight: weight)
            )
            total += score * weight
        }

        let dropped = SleepComponent.allCases.filter { rawScores[$0] == nil }

        return SleepOutput(
            score: components.isEmpty ? nil : total.rounded(),
            needHours: needHours,
            asleepHours: asleepHours,
            components: components,
            droppedComponents: dropped,
            validity: validity,
            appliedDebtHours: appliedDebt,
            appliedNapCreditHours: appliedNapCredit
        )
    }

    /// §5.2 — the night's sleep need in hours.
    ///
    /// The result is floored at one hour so that a pathological setting cannot make
    /// `Duration` divide by something near zero and read 100 for a two-hour night.
    static func need(for input: SleepInput) -> Double {
        let strainTerm = EngineConstants.Sleep.strainNeedCoefficient
            * MathSupport.clamp(
                MathSupport.safeDivide(input.yesterdayStrain, by: EngineConstants.Strain.scaleMax),
                0,
                1
            )
        let debtTerm = min(max(input.sleepDebtHours, 0), EngineConstants.Sleep.maxDebtContributionHours)
        let napTerm = min(max(input.napCreditHours, 0), EngineConstants.Sleep.maxNapCreditHours)
        let raw = input.baselineNeedHours + strainTerm + debtTerm - napTerm
        return max(raw, 1.0)
    }

    /// §5.6 — nights under 2 h or over 14 h are rejected and the record flagged `.suspect`.
    static func validity(for input: SleepInput) -> SleepValidity {
        guard input.asleepSeconds > 0 else { return .noData }
        if input.asleepSeconds < EngineConstants.Sleep.minValidSleepSeconds { return .tooShort }
        if input.asleepSeconds > EngineConstants.Sleep.maxValidSleepSeconds { return .tooLong }
        return .valid
    }

    // MARK: - Debt and nap credit

    /// §5.2 — sleep debt over the trailing nights, decayed 25 % per night.
    ///
    /// - Parameter shortfallsNewestFirst: `max(0, need − actual)` in hours for each of the
    ///   trailing nights, most recent first.
    ///
    /// The most recent night carries full weight and each night before it carries 25 % less,
    /// so a bad night three days ago still counts for something and one a fortnight ago does
    /// not. The result is uncapped; `compute` applies the 1.5 h cap.
    static func sleepDebt(shortfallsNewestFirst: [Double]) -> Double {
        let window = min(shortfallsNewestFirst.count, EngineConstants.Sleep.debtWindowNights)
        guard window > 0 else { return 0 }
        var total: Double = 0
        var weight: Double = 1
        for index in 0..<window {
            let shortfall = max(shortfallsNewestFirst[index], 0)
            total += shortfall * weight
            weight *= (1 - EngineConstants.Sleep.debtDecayPerNight)
        }
        return total
    }

    /// §5.2 — nap credit in hours from naps of at least 20 minutes, before the 1 h cap.
    static func napCredit(from naps: [SleepSegment]) -> Double {
        let qualifying = naps.filter {
            $0.isAsleep && $0.duration >= EngineConstants.Sleep.minNapSeconds
        }
        let seconds = qualifying.reduce(into: 0.0) { $0 += $1.duration }
        return min(
            TimeConversion.hours(fromSeconds: seconds),
            EngineConstants.Sleep.maxNapCreditHours
        )
    }

    /// Resolves valid naps occurring between the previous night's wake time and the current night's start.
    /// Returns `nil` if previous wake time is unknown (nap cannot be determined).
    /// Discards segments that overlap the current night's sleep block or exceed `maxNapSeconds`.
    static func resolveNaps(
        candidates: [SleepSegment],
        previousWakeTime: Date?,
        currentNightSleepBlock: DateInterval? = nil
    ) -> [SleepSegment]? {
        guard let previousWakeTime else {
            return nil
        }
        return candidates.filter { segment in
            guard segment.isAsleep else { return false }
            // Must begin at or after previous night's wake time
            guard segment.start >= previousWakeTime else { return false }
            // Must not exceed maxNapSeconds (3 hours)
            guard segment.duration <= EngineConstants.Sleep.maxNapSeconds else { return false }
            // Must not overlap with current night's main sleep block
            if let currentNightSleepBlock, segment.interval.intersects(currentNightSleepBlock) {
                return false
            }
            return true
        }
    }

    /// Total qualifying nap seconds, or `nil` if previous night's wake time is unknown.
    static func totalNapSeconds(
        candidates: [SleepSegment],
        previousWakeTime: Date?,
        currentNightSleepBlock: DateInterval? = nil
    ) -> Double? {
        guard let naps = resolveNaps(
            candidates: candidates,
            previousWakeTime: previousWakeTime,
            currentNightSleepBlock: currentNightSleepBlock
        ) else {
            return nil
        }
        let qualifying = naps.filter { $0.duration >= EngineConstants.Sleep.minNapSeconds }
        return qualifying.reduce(into: 0.0) { $0 += $1.duration }
    }

    // MARK: - Night resolution

    /// The longest contiguous asleep block in a set of segments (§5.5).
    ///
    /// ASSUMPTION SLEEP-2: runs of `.awake` up to 15 minutes do not break contiguity, because
    /// Apple emits many short interruptions and a strict reading would fragment a normal
    /// night into six or ten "blocks" of about ninety minutes each.
    ///
    /// Returns the block's interval and the asleep seconds inside it — which is less than the
    /// interval's duration whenever a tolerated interruption was absorbed.
    static func longestAsleepBlock(
        in segments: [SleepSegment]
    ) -> (interval: DateInterval, asleepSeconds: Double)? {
        let asleep = segments.filter(\.isAsleep).chronological
        guard let first = asleep.first else { return nil }

        var bestStart = first.start
        var bestEnd = first.end
        var bestAsleep = first.duration

        var currentStart = first.start
        var currentEnd = first.end
        var currentAsleep = first.duration

        for segment in asleep.dropFirst() {
            let gap = segment.start.timeIntervalSince(currentEnd)
            if gap <= EngineConstants.Sleep.contiguityToleranceSeconds {
                currentEnd = max(currentEnd, segment.end)
                currentAsleep += segment.duration
            } else {
                if currentAsleep > bestAsleep {
                    bestStart = currentStart
                    bestEnd = currentEnd
                    bestAsleep = currentAsleep
                }
                currentStart = segment.start
                currentEnd = segment.end
                currentAsleep = segment.duration
            }
        }
        if currentAsleep > bestAsleep {
            bestStart = currentStart
            bestEnd = currentEnd
            bestAsleep = currentAsleep
        }
        return (DateInterval(start: bestStart, end: max(bestStart, bestEnd)), bestAsleep)
    }

    /// The sleep midpoint of a block: `sleepStart + duration/2` (§5.5).
    static func midpoint(of interval: DateInterval) -> Date {
        interval.start.addingTimeInterval(interval.duration / 2)
    }

    /// Minutes from local midnight, for the circular consistency comparison (§5.2).
    static func minutesFromLocalMidnight(
        _ date: Date,
        calendar: Calendar
    ) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let hours = Double(components.hour ?? 0)
        let minutes = Double(components.minute ?? 0)
        let seconds = Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1_000_000_000.0
        let totalMinutes = hours * 60.0 + minutes + seconds / 60.0
        return MathSupport.wrap(
            totalMinutes,
            period: EngineConstants.Sleep.minutesPerDay
        )
    }

    /// The 14-day circular mean of midpoints (§5.2, ASSUMPTION SLEEP-5).
    ///
    /// Returns `nil` below two nights, which drops `Consistency` and renormalizes rather than
    /// comparing a night against itself and scoring a perfect 100.
    static func midpointBaseline(minutes: [Double]) -> Double? {
        let window = Array(minutes.suffix(EngineConstants.Sleep.consistencyWindowDays))
        guard window.count >= 2 else { return nil }
        return MathSupport.circularMean(window, period: EngineConstants.Sleep.minutesPerDay)
    }

    /// Stage seconds inside an interval, clipped to it and resolved for multi-source overlaps.
    ///
    /// Clipping alone is not sufficient when multiple devices (e.g. Apple Watch and iPhone)
    /// write concurrent segments. Overlapping segments are partitioned and resolved using
    /// physiological specificity priority (Deep > REM > Core > Unspecified > Awake > InBed)
    /// before measuring duration, guaranteeing that stage totals never exceed the block duration.
    static func stageSeconds(
        _ stages: Set<SleepStage>,
        in segments: [SleepSegment],
        clippedTo interval: DateInterval
    ) -> Double {
        let clipped = segments.compactMap { segment -> SleepSegment? in
            guard let overlap = interval.intersection(with: segment.interval), overlap.duration > 0 else {
                return nil
            }
            return SleepSegment(
                interval: overlap,
                stage: segment.stage,
                sourceBundleIdentifier: segment.sourceBundleIdentifier,
                timeZoneIdentifier: segment.timeZoneIdentifier
            )
        }
        return clipped.seconds(in: stages)
    }
}
