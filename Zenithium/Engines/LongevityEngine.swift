//
//  LongevityEngine.swift
//  Zenithium
//
//  The long-horizon composite. Faz 29.
//
//  ## How each pillar becomes a number
//
//  Every pillar scores 0–100, and every one is scored **against the user's own history**
//  rather than against a population table. That is the difference between a number that
//  means something to one person and a number that ranks them against strangers whose data
//  Zenithium does not have.
//
//  The mechanism is the same throughout: take the signal's percentile position within its
//  own long window, orient it so higher is fitter, and average the signals a pillar owns.
//  A signal with too little history is simply absent, and the pillar's weight is redistributed
//  rather than filled with a guess.
//

import Foundation

enum LongevityEngine {

    /// How far back the composite looks.
    ///
    /// A year. Shorter and it tracks a training block rather than a direction; longer and it
    /// stops responding to anything the user does.
    static let windowDays = 365

    /// Below this many values, a signal does not take part.
    static let minimumSamples = 20

    /// Below this coverage there is no composite at all — a score built on one pillar would
    /// be a single trend line wearing a composite's clothes.
    static let minimumCoverage = 0.45

    // MARK: - Entry point

    static func score(
        vitals: [VitalReading],
        days: [BiometricDaySnapshot],
        now: Date = Date()
    ) -> LongevityScore? {
        var components: [LongevityComponent] = []

        if let component = cardiorespiratory(vitals) { components.append(component) }
        if let component = autonomic(days) { components.append(component) }
        if let component = sleep(days) { components.append(component) }
        if let component = mobility(vitals) { components.append(component) }
        if let component = activity(days) { components.append(component) }

        let coverage = components.reduce(0) { $0 + $1.pillar.weight }
        guard coverage >= minimumCoverage else { return nil }

        // Renormalise by the coverage actually achieved. Without this, a user missing the
        // mobility signals would score 15 points lower for owning a different watch.
        let weighted = components.reduce(0) { $0 + $1.contribution }
        let score = MathSupport.clamp(weighted / coverage, 0, 100)

        let changes = components.compactMap(\.monthlyChange)
        let monthlyChange = changes.isEmpty ? nil : MathSupport.mean(changes)

        return LongevityScore(
            score: score,
            components: components.sorted { $0.pillar.weight > $1.pillar.weight },
            coverage: coverage,
            monthlyChange: monthlyChange
        )
    }

    // MARK: - Pillars

    private static func cardiorespiratory(_ vitals: [VitalReading]) -> LongevityComponent? {
        component(
            pillar: .cardiorespiratory,
            readings: vitals.filter { $0.sign == .vo2Max || $0.sign == .heartRateRecovery }
        )
    }

    private static func mobility(_ vitals: [VitalReading]) -> LongevityComponent? {
        component(
            pillar: .mobility,
            readings: vitals.filter {
                $0.sign == .walkingSpeed || $0.sign == .walkingSteadiness || $0.sign == .stairAscentSpeed
            }
        )
    }

    /// HRV and resting heart rate, scored from the day records rather than the vitals feed.
    ///
    /// Deliberately the same numbers recovery is built on: if the composite disagreed with
    /// the daily score about how the autonomic side is going, one of them would be wrong.
    private static func autonomic(_ days: [BiometricDaySnapshot]) -> LongevityComponent? {
        let hrv = days.compactMap(\.heartRateVariability)
        let resting = days.compactMap(\.restingHeartRate)

        var scores: [Double] = []
        if hrv.count >= minimumSamples, let latest = hrv.last {
            scores.append(percentileScore(of: latest, in: hrv, higherIsFitter: true))
        }
        if resting.count >= minimumSamples, let latest = resting.last {
            scores.append(percentileScore(of: latest, in: resting, higherIsFitter: false))
        }
        guard let mean = MathSupport.mean(scores) else { return nil }

        return LongevityComponent(
            pillar: .autonomic,
            score: mean,
            contribution: mean * LongevityPillar.autonomic.weight,
            inputCount: scores.count,
            monthlyChange: nil
        )
    }

    /// Duration and consistency together.
    ///
    /// Consistency is scored from the spread of sleep midpoints: a person who sleeps seven
    /// hours every night and one who averages seven across four and ten are not the same,
    /// and duration alone cannot tell them apart.
    private static func sleep(_ days: [BiometricDaySnapshot]) -> LongevityComponent? {
        let hours = days.map { $0.sleepDurationSeconds / 3600 }.filter { $0 > 0 }
        guard hours.count >= minimumSamples, let meanHours = MathSupport.mean(hours) else { return nil }

        // Seven to nine hours scores full; outside it falls away linearly, reaching zero
        // three hours out either side.
        let durationScore: Double
        switch meanHours {
        case 7...9: durationScore = 100
        case ..<7: durationScore = MathSupport.clamp(100 - (7 - meanHours) / 3 * 100, 0, 100)
        default: durationScore = MathSupport.clamp(100 - (meanHours - 9) / 3 * 100, 0, 100)
        }

        var scores = [durationScore]
        let midpoints = days.compactMap(\.sleepMidpointMinutes)
        if midpoints.count >= minimumSamples, let meanMidpoint = MathSupport.mean(midpoints) {
            let variance = midpoints.reduce(0) { $0 + ($1 - meanMidpoint) * ($1 - meanMidpoint) }
                / Double(midpoints.count)
            let deviationMinutes = variance.squareRoot()
            // A standard deviation of 30 minutes scores full; 150 minutes scores zero.
            scores.append(MathSupport.clamp(100 - (deviationMinutes - 30) / 120 * 100, 0, 100))
        }

        guard let mean = MathSupport.mean(scores) else { return nil }
        return LongevityComponent(
            pillar: .sleep,
            score: mean,
            contribution: mean * LongevityPillar.sleep.weight,
            inputCount: scores.count,
            monthlyChange: nil
        )
    }

    /// How many days in the window carried any load at all.
    ///
    /// Consistency, not intensity. For the persona this pillar exists for, "moved on five
    /// days out of seven" is the whole question, and a strain figure would answer a
    /// different one.
    private static func activity(_ days: [BiometricDaySnapshot]) -> LongevityComponent? {
        guard days.count >= minimumSamples else { return nil }
        let active = days.filter { $0.dayStrain > 1 }.count
        let share = Double(active) / Double(days.count)
        // Five days a week — about 0.71 — scores full.
        let score = MathSupport.clamp(share / 0.71 * 100, 0, 100)

        return LongevityComponent(
            pillar: .activity,
            score: score,
            contribution: score * LongevityPillar.activity.weight,
            inputCount: 1,
            monthlyChange: nil
        )
    }

    // MARK: - Shared

    /// Score a pillar from vital readings, and fit its direction.
    private static func component(pillar: LongevityPillar, readings: [VitalReading]) -> LongevityComponent? {
        var scores: [Double] = []
        var changes: [Double] = []

        for reading in readings {
            let values = reading.history.map(\.value)
            guard values.count >= minimumSamples, let latest = values.last else { continue }
            let higherIsFitter = reading.sign.polarity != .lowerIsFitter
            scores.append(percentileScore(of: latest, in: values, higherIsFitter: higherIsFitter))

            if let slope = VitalsEngine.slopePerDay(of: reading.history), let mean = MathSupport.mean(values), mean != 0 {
                // Convert the slope into score-points per month: a signal moving one per cent
                // of its own mean per month is worth roughly one point.
                let relativePerMonth = slope * 30 / abs(mean) * 100
                changes.append(higherIsFitter ? relativePerMonth : -relativePerMonth)
            }
        }

        guard let mean = MathSupport.mean(scores) else { return nil }
        return LongevityComponent(
            pillar: pillar,
            score: mean,
            contribution: mean * pillar.weight,
            inputCount: scores.count,
            monthlyChange: changes.isEmpty ? nil : MathSupport.mean(changes)
        )
    }

    /// Where a value sits inside its own history, as 0…100.
    ///
    /// A percentile against the user's own year, not against a population. Zenithium does
    /// not have anybody else's data and is not going to pretend otherwise.
    static func percentileScore(of value: Double, in values: [Double], higherIsFitter: Bool) -> Double {
        guard !values.isEmpty else { return 50 }
        let below = values.filter { $0 < value }.count
        let equal = values.filter { $0 == value }.count
        // Midpoint of the equal band, so a value tied with everything scores 50 rather than
        // 0 or 100 depending on comparison direction.
        let percentile = (Double(below) + Double(equal) / 2) / Double(values.count) * 100
        return higherIsFitter ? percentile : 100 - percentile
    }
}
