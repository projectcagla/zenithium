//
//  CycleEngine.swift
//  Zenithium
//
//  Phase estimation and phase-aware baselines. Faz 12.
//
//  Two jobs. Work out which phase a day falls in from logged bleeding, and split a metric's
//  history by phase so today is compared against days like it.
//
//  The second job is the one that matters. A luteal resting heart rate compared against a
//  whole-cycle mean sits two or three beats high every single month, and a recovery engine
//  reading that difference reports a bad morning that is not one. Splitting the baseline
//  removes a systematic error; it does not add a feature.
//
//  §12: nothing here infers pregnancy, predicts fertility, or characterises a cycle as
//  regular or irregular. It estimates a phase from what the user logged, says how sure it
//  is, and stops.
//

import Foundation

enum CycleEngine {

    /// Fallback cycle length when there is not enough history to measure one.
    ///
    /// Twenty-eight is the textbook figure and the median is closer to twenty-nine, but the
    /// difference is inside the estimate's own error and the textbook number is the one a
    /// user will recognise if the app ever shows it.
    static let defaultCycleLength = 28

    /// Assumed luteal length, counted back from the next expected period.
    ///
    /// Fourteen days is the standard approximation. It is wrong for anyone whose luteal
    /// phase is shorter or longer, which is why every estimate carries a confidence rather
    /// than being presented as fact.
    static let assumedLutealLength = 14

    /// How many days around the expected ovulation are called ovulatory.
    static let ovulatoryWindow = 3

    /// Plausible cycle lengths. Anything outside is a logging gap, not a cycle.
    static let plausibleCycleLengths = 21...40

    /// How many complete cycles are needed before the measured length replaces the default.
    static let minimumCyclesForLength = 2

    /// How far back cycle history is read.
    static let historyWindowDays = 400

    // MARK: - Cycle starts

    /// The first day of each period, oldest first.
    ///
    /// A run of consecutive bleeding days is one period. HealthKit's own cycle-start flag is
    /// used where present; where it is not, a gap of at least three days since the last
    /// logged flow marks a new period — shorter gaps are far more often a missed log than a
    /// genuine second cycle.
    static func cycleStarts(from days: [MenstrualFlowDay], calendar: Calendar) -> [Date] {
        let ordered = days
            .map { MenstrualFlowDay(dayStart: calendar.startOfDay(for: $0.dayStart), isCycleStart: $0.isCycleStart) }
            .sorted { $0.dayStart < $1.dayStart }
        guard !ordered.isEmpty else { return [] }

        var starts: [Date] = []
        var previous: Date?

        for day in ordered {
            if day.isCycleStart {
                starts.append(day.dayStart)
                previous = day.dayStart
                continue
            }
            guard let last = previous else {
                starts.append(day.dayStart)
                previous = day.dayStart
                continue
            }
            let gap = calendar.dateComponents([.day], from: last, to: day.dayStart).day ?? 0
            if gap >= 3 {
                starts.append(day.dayStart)
            }
            previous = day.dayStart
        }

        // Deduplicate: HealthKit sometimes flags the same day both ways.
        var seen = Set<Date>()
        return starts.filter { seen.insert($0).inserted }
    }

    /// The measured cycle length, or `nil` when there is not enough history.
    static func measuredCycleLength(starts: [Date], calendar: Calendar) -> Int? {
        guard starts.count >= minimumCyclesForLength + 1 else { return nil }
        var lengths: [Double] = []
        for (earlier, later) in zip(starts, starts.dropFirst()) {
            guard let days = calendar.dateComponents([.day], from: earlier, to: later).day else { continue }
            guard plausibleCycleLengths.contains(days) else { continue }
            lengths.append(Double(days))
        }
        guard lengths.count >= minimumCyclesForLength, let mean = MathSupport.mean(lengths) else { return nil }
        return Int(mean.rounded())
    }

    // MARK: - Phase

    /// Which phase a day falls in.
    ///
    /// Returns `nil` when there is no logged period to count from — an estimate with no
    /// anchor would be a guess dressed as a measurement.
    static func phase(
        on day: Date,
        flowDays: [MenstrualFlowDay],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> CyclePhaseEstimate? {
        let target = calendar.startOfDay(for: day)
        let starts = cycleStarts(from: flowDays, calendar: calendar)
        guard let mostRecent = starts.last(where: { $0 <= target }) else { return nil }

        let elapsed = calendar.dateComponents([.day], from: mostRecent, to: target).day ?? 0
        guard elapsed >= 0 else { return nil }

        let measured = measuredCycleLength(starts: starts, calendar: calendar)
        let length = measured ?? defaultCycleLength
        let dayOfCycle = elapsed + 1

        // Past one and a half cycle lengths since the last logged period, the count has
        // stopped meaning anything — almost always a gap in logging rather than a cycle
        // that long. Reporting a phase from it would be inventing one.
        guard dayOfCycle <= Int(Double(length) * 1.5) else { return nil }

        let ovulationDay = length - assumedLutealLength
        let phase: CyclePhase
        switch dayOfCycle {
        case ...5:
            phase = .menstrual
        case ..<(ovulationDay - ovulatoryWindow / 2):
            phase = .follicular
        case ...(ovulationDay + ovulatoryWindow / 2):
            phase = .ovulatory
        default:
            phase = .luteal
        }

        return CyclePhaseEstimate(
            phase: phase,
            dayOfCycle: dayOfCycle,
            cycleLength: length,
            confidence: confidence(
                measuredLength: measured,
                cycleCount: starts.count,
                dayOfCycle: dayOfCycle,
                cycleLength: length
            )
        )
    }

    /// How much to trust a phase estimate.
    ///
    /// Three things reduce it, and each corresponds to a real source of error: not knowing
    /// this person's cycle length, having seen too few cycles to know it is stable, and
    /// being deep into the second half where an assumed luteal length has had the most room
    /// to drift.
    static func confidence(
        measuredLength: Int?,
        cycleCount: Int,
        dayOfCycle: Int,
        cycleLength: Int
    ) -> Double {
        var score = 1.0
        if measuredLength == nil { score *= 0.65 }
        if cycleCount < 3 { score *= 0.80 }

        // Bleeding days are directly observed, so they keep full confidence; everything
        // after is inferred, and the further in, the more the assumption carries.
        if dayOfCycle > 5 {
            let progress = Double(dayOfCycle - 5) / Double(max(1, cycleLength - 5))
            score *= 1.0 - 0.25 * MathSupport.clamp(progress, 0, 1)
        }
        return MathSupport.clamp(score, 0, 1)
    }

    // MARK: - Phase-aware baselines

    /// Split a metric's daily history into the two baseline groups.
    ///
    /// Days whose phase cannot be estimated are dropped rather than pooled. Putting an
    /// unknown day into either group is exactly the contamination this function exists to
    /// prevent.
    static func partition(
        values: [(day: Date, value: Double)],
        flowDays: [MenstrualFlowDay],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [CycleBaselineGroup: [Double]] {
        var grouped: [CycleBaselineGroup: [Double]] = [:]
        for entry in values {
            guard let estimate = phase(on: entry.day, flowDays: flowDays, calendar: calendar) else { continue }
            guard estimate.isConfident else { continue }
            grouped[estimate.phase.baselineGroup, default: []].append(entry.value)
        }
        return grouped
    }

    /// Below this many days in a group, the phase-aware baseline is not used.
    ///
    /// Ten is roughly two cycles' worth of luteal mornings. Fewer than that and the
    /// phase-specific mean is noisier than the pooled one it would replace, which would make
    /// the comparison worse rather than better.
    static let minimumSamplesPerGroup = 10

    /// The phase-aware mean and deviation for today, or `nil` when there is not enough
    /// history in this phase to beat the pooled baseline.
    static func phaseBaseline(
        for group: CycleBaselineGroup,
        partitioned: [CycleBaselineGroup: [Double]]
    ) -> (mean: Double, deviation: Double)? {
        guard let values = partitioned[group], values.count >= minimumSamplesPerGroup else { return nil }
        guard let mean = MathSupport.mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return (mean, variance.squareRoot())
    }

    /// How far apart the two phase means sit, for one metric.
    ///
    /// This is the number that justifies the whole feature: if it is near zero for a given
    /// person, the pooled baseline was fine for them and the app can say so.
    static func phaseShift(partitioned: [CycleBaselineGroup: [Double]]) -> Double? {
        guard let follicular = phaseBaseline(for: .follicularPhase, partitioned: partitioned),
              let luteal = phaseBaseline(for: .lutealPhase, partitioned: partitioned) else { return nil }
        return luteal.mean - follicular.mean
    }

    // MARK: - Copy

    /// The sentence shown beside a recovery score.
    ///
    /// Names the phase, says what that phase does to the numbers, and — when there is enough
    /// history — gives the person's own phase mean so the comparison is theirs rather than a
    /// textbook's. Never advice.
    static func context(
        for estimate: CyclePhaseEstimate,
        metric: MetricKind,
        phaseMean: Double?
    ) -> String {
        var sentence = "\(estimate.qualifier) — döngünün \(estimate.dayOfCycle). günü."
        if let phaseMean {
            sentence += " Bu fazdaki \(metric.displayName.lowercased()) ortalaman \(ZenithiumFormat.metric(phaseMean, digits: metric == .heartRateVariability ? 0 : 1))."
        }
        sentence += " \(estimate.phase.physiologyNote)"
        return sentence
    }
}
