//
//  TrainingLoadEngine.swift
//  Zenithium
//
//  The shared load mathematics. Faz 14.
//
//  Four questions, one engine:
//
//  * **How much lately, versus how much for a while?** The acute:chronic ratio, computed
//    exponentially rather than as a pair of rolling averages. A rolling mean lags by half
//    its window, so a week that changed on Monday only shows up in the number on Thursday.
//  * **How fast is it changing?** Week-over-week ramp.
//  * **How varied is the week?** Foster's monotony, and the strain figure built on it.
//  * **Fit or fresh?** Banister's two-component model: a slow-moving fitness term and a
//    fast-moving fatigue term, with form as their difference.
//
//  All four run off one input — a daily load series on the TRIMP scale `StrainEngine`
//  already produces. Nothing here reads HealthKit, and nothing here knows what sport the
//  user does; the lenses decide what to say about the numbers.
//
//  §12: every band in `LoadBand` describes *load*. The workload literature reports
//  association with injury, not causation, and this engine is not entitled to the stronger
//  claim — so it never makes it.
//

import Foundation

enum TrainingLoadEngine {

    // MARK: - Entry point

    static func analyse(_ input: TrainingLoadInput) -> TrainingLoadOutput {
        let series = densifiedSeries(input)
        let constants = EngineConstants.TrainingLoad.self

        let track = exponentialTrack(series)
        let chronicWindow = series.suffix(constants.chronicWindowDays)
        let activeDays = chronicWindow.filter { $0.load > 0 }.count

        // A ratio needs a denominator that means something. Both tests matter: the chronic
        // term can be non-zero off a single hard day, and eight scattered days is the point
        // where the twenty-eight-day term starts describing a habit rather than an incident.
        let canDivide = track.chronic > 0 && activeDays >= constants.minimumActiveDaysForRatio
        let recentRatios = canDivide ? Array(track.dailyRatios.suffix(constants.acuteWindowDays)) : []
        let smoothed = recentRatios.isEmpty ? nil : MathSupport.mean(recentRatios)

        let thisWeek = series.suffix(constants.acuteWindowDays)
        let lastWeek = series.dropLast(constants.acuteWindowDays).suffix(constants.acuteWindowDays)
        let weekLoad = thisWeek.reduce(0) { $0 + $1.load }
        let previousWeekLoad = lastWeek.reduce(0) { $0 + $1.load }

        let monotony = monotony(of: Array(thisWeek))

        return TrainingLoadOutput(
            acuteLoad: track.acute,
            chronicLoad: track.chronic,
            ratio: smoothed,
            instantRatio: canDivide ? track.acute / track.chronic : nil,
            recentRatios: recentRatios,
            band: smoothed.map(LoadBand.band(forRatio:)),
            weekLoad: weekLoad,
            previousWeekLoad: previousWeekLoad,
            rampRate: previousWeekLoad > 0 ? (weekLoad - previousWeekLoad) / previousWeekLoad : nil,
            monotony: monotony,
            fosterStrain: monotony.map { weekLoad * $0 },
            fitnessFatigue: fitnessFatigue(series),
            activeDaysInChronicWindow: activeDays
        )
    }

    // MARK: - Series

    /// Fill the gaps.
    ///
    /// A day with no session is a zero, not a missing value. Dropping rest days would make
    /// a three-sessions-a-week athlete look like they train every day, and their ratio
    /// would never move.
    static func densifiedSeries(_ input: TrainingLoadInput) -> [DailyLoad] {
        let calendar = input.calendar
        let end = calendar.startOfDay(for: input.referenceDay)
        guard let earliest = input.days.map(\.dayStart).min() else {
            return [DailyLoad(dayStart: end, load: 0)]
        }
        let start = calendar.startOfDay(for: min(earliest, end))

        var byDay: [Date: Double] = [:]
        for day in input.days {
            let key = calendar.startOfDay(for: day.dayStart)
            guard key <= end else { continue }
            byDay[key, default: 0] += day.load
        }

        var series: [DailyLoad] = []
        var cursor = start
        while cursor <= end {
            series.append(DailyLoad(dayStart: cursor, load: byDay[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return series
    }

    /// Both exponential terms, and the ratio on every day along the way.
    ///
    /// ## Why the seed is the first week's mean, not the first day
    ///
    /// Seeding at day one leaves the chronic term carrying 14.5% of that single value after
    /// four weeks — enough to bend the answer. Measured on an unchanging four-week block
    /// whose true ratio is 1.00, day-one seeding reads **0.84**; it only reaches 0.99 after
    /// twelve weeks. Seeding at the first week's mean reads **0.99 from four weeks onward**.
    /// The bias is not subtle and it is not self-correcting on any useful timescale, so the
    /// stable seed is the correct one.
    static func exponentialTrack(_ series: [DailyLoad]) -> (acute: Double, chronic: Double, dailyRatios: [Double]) {
        let constants = EngineConstants.TrainingLoad.self
        guard !series.isEmpty else { return (0, 0, []) }

        let seedWindow = series.prefix(constants.acuteWindowDays).map(\.load)
        let seed = MathSupport.mean(seedWindow) ?? 0

        var acute = seed
        var chronic = seed
        var ratios: [Double] = []
        ratios.reserveCapacity(series.count)

        for day in series {
            acute = constants.acuteAlpha * day.load + (1 - constants.acuteAlpha) * acute
            chronic = constants.chronicAlpha * day.load + (1 - constants.chronicAlpha) * chronic
            ratios.append(chronic > 0 ? acute / chronic : 0)
        }
        return (acute, chronic, ratios)
    }

    // MARK: - Monotony

    /// Foster's monotony: the week's mean divided by its standard deviation.
    ///
    /// The population standard deviation is used rather than the sample one, because the
    /// seven days *are* the week — they are not a sample drawn from it.
    ///
    /// Returns `nil` when the week is flat enough that the divisor stops being meaningful,
    /// which includes a week of nothing but rest. Reporting "infinitely monotonous" for a
    /// week off would be arithmetically true and completely useless.
    static func monotony(of week: [DailyLoad]) -> Double? {
        let loads = week.map(\.load)
        guard loads.count >= 2, let mean = MathSupport.mean(loads), mean > 0 else { return nil }

        let variance = loads.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(loads.count)
        let deviation = variance.squareRoot()
        guard deviation > EngineConstants.TrainingLoad.monotonyStandardDeviationFloor else { return nil }

        return min(mean / deviation, EngineConstants.TrainingLoad.monotonyCeiling)
    }

    // MARK: - Fitness and fatigue

    /// Banister's two-component impulse–response model.
    ///
    /// Both terms are exponential decays of the same load series, differing only in time
    /// constant: fitness at 42 days, fatigue at 7. Their difference is what cyclists call
    /// form — the reason a taper works, since fatigue sheds in a week and fitness does not.
    static func fitnessFatigue(_ series: [DailyLoad]) -> FitnessFatigue {
        let constants = EngineConstants.TrainingLoad.self
        let fitnessDecay = exp(-1.0 / constants.fitnessTimeConstantDays)
        let fatigueDecay = exp(-1.0 / constants.fatigueTimeConstantDays)

        var fitness = 0.0
        var fatigue = 0.0
        for day in series {
            fitness = fitness * fitnessDecay + day.load * (1 - fitnessDecay)
            fatigue = fatigue * fatigueDecay + day.load * (1 - fatigueDecay)
        }
        return FitnessFatigue(fitness: fitness, fatigue: fatigue, form: fitness - fatigue)
    }

    // MARK: - Forecasting

    /// What the headline ratio becomes if today carries `load`.
    ///
    /// Steps both exponential terms one day and averages the resulting instantaneous ratio
    /// with the six before it, so the answer is comparable with what the screen shows
    /// rather than with the unsmoothed value nobody sees.
    static func projectedRatio(after load: Double, from output: TrainingLoadOutput) -> Double? {
        guard let instant = projectedInstantRatio(after: load, from: output) else { return nil }
        let window = EngineConstants.TrainingLoad.acuteWindowDays
        let previous = output.recentRatios.suffix(window - 1)
        return MathSupport.mean(Array(previous) + [instant])
    }

    /// The unsmoothed ratio one day on.
    static func projectedInstantRatio(after load: Double, from output: TrainingLoadOutput) -> Double? {
        let constants = EngineConstants.TrainingLoad.self
        let acute = constants.acuteAlpha * load + (1 - constants.acuteAlpha) * output.acuteLoad
        let chronic = constants.chronicAlpha * load + (1 - constants.chronicAlpha) * output.chronicLoad
        guard chronic > 0 else { return nil }
        return acute / chronic
    }

    /// The largest load today that keeps **today's own** ratio at or under `ceiling`.
    ///
    /// Deliberately the instantaneous ratio and not the headline one. A single day can
    /// barely move a seven-day mean, so asking what load holds the *smoothed* ratio under
    /// 1.30 answers "about 515" — arithmetically exact and completely useless as a ceiling.
    /// The question a prescription actually asks is the spike question: how big can today
    /// be before it is a jump relative to what the body is prepared for. That is the
    /// instantaneous term, and it gives usable answers — for an athlete whose hard days run
    /// 12–14, a 1.30 ceiling permits about 19 and a 1.50 ceiling about 28.
    ///
    /// Solving the one-day projection for `L`:
    ///
    ///     (αₐ·L + (1−αₐ)·A) / (α_c·L + (1−α_c)·C) = R
    ///     L·(αₐ − R·α_c) = R·(1−α_c)·C − (1−αₐ)·A
    ///
    /// The coefficient on the left turns non-positive only above `αₐ/α_c ≈ 3.6`, which no
    /// ceiling this app offers comes near — but it is guarded rather than allowed to return
    /// a negative allowance.
    static func loadCeiling(forInstantRatio ceiling: Double, from output: TrainingLoadOutput) -> Double? {
        let constants = EngineConstants.TrainingLoad.self
        guard output.chronicLoad > 0 else { return nil }

        let denominator = constants.acuteAlpha - ceiling * constants.chronicAlpha
        guard denominator > 0 else { return nil }

        let numerator = ceiling * (1 - constants.chronicAlpha) * output.chronicLoad
            - (1 - constants.acuteAlpha) * output.acuteLoad
        return max(0, numerator / denominator)
    }

    // MARK: - Copy

    /// One sentence about the ratio, or about why there is not one yet.
    static func summary(for output: TrainingLoadOutput) -> String {
        guard let ratio = output.ratio, let band = output.band else {
            let needed = max(0, EngineConstants.TrainingLoad.minimumActiveDaysForRatio - output.activeDaysInChronicWindow)
            return needed > 0
                ? "Yük oranı için \(needed) antrenman günü daha gerekiyor."
                : "Yük oranı için yeterli geçmiş yok."
        }
        return "Yük oranın \(ZenithiumFormat.metric(ratio, digits: 2)) — \(band.displayName.lowercased()) bant. \(band.explanation)"
    }

    /// One sentence about the week's shape, when there is one worth saying.
    static func monotonySummary(for output: TrainingLoadOutput) -> String? {
        guard let monotony = output.monotony else { return nil }
        if monotony >= 2.0 {
            return "Haftan tekdüze (\(ZenithiumFormat.metric(monotony, digits: 1))) — günler birbirine çok benziyor. Sert ve kolay günler arasındaki fark, toplam hacim kadar önemli."
        }
        return "Haftanın değişkenliği iyi (tekdüzelik \(ZenithiumFormat.metric(monotony, digits: 1)))."
    }
}
