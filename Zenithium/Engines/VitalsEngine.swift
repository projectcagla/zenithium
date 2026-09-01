//
//  VitalsEngine.swift
//  Zenithium
//
//  Baselines and deviation for the vital signs. Faz 11, Faz 28.
//
//  This engine deliberately does **not** reuse `BaselineEngine`. That one implements §4's
//  contract exactly — a 60-day EWMA, winsorized at 3σ, with a documented prior per metric
//  and a calibration gate. Those choices exist because a recovery score depends on them.
//  A vital sign has no prior, no spec weight and no calibration requirement; what it needs
//  is a plain window mean and deviation over its own horizon, which is what this does.
//
//  Mixing the two would mean either inventing priors for eighteen signals that have none,
//  or loosening the recovery baseline to accommodate signals that never feed it.
//
//  §12: nothing here decides whether a reading is good. It reports where a value sits
//  relative to that person's own recent range, and the copy layer keeps it descriptive.
//

import Foundation

enum VitalsEngine {

    /// Below this many samples there is no baseline, so no z-score.
    static let minimumSamplesForBaseline = 10

    /// The standard deviation floor, as a fraction of the mean.
    ///
    /// Without it, a signal that happens to sit still for a fortnight produces a near-zero
    /// divisor and the next ordinary reading looks like a five-sigma event. Two per cent of
    /// the mean is below the measurement noise of every signal here, so it never masks a
    /// real move — it only stops the arithmetic exploding.
    static let deviationFloorFraction = 0.02

    /// How many of the most recent days are excluded from the baseline when scoring.
    ///
    /// One: a value is scored against the baseline *as of yesterday*, the same rule §4.2.1
    /// sets for the recovery metrics. Folding today into its own comparison flattens exactly
    /// the deviation the score is looking for.
    static let scoringExclusionDays = 1

    // MARK: - Readings

    /// Turn a raw history into a reading with its baseline and z-score.
    static func reading(for sign: VitalSign, samples: [VitalSample]) -> VitalReading {
        let ordered = samples
            .filter { $0.sign == sign && $0.value.isFinite }
            .sorted { $0.dayStart < $1.dayStart }

        guard let latest = ordered.last else {
            return VitalReading(
                sign: sign,
                latest: nil,
                baselineMean: nil,
                baselineDeviation: nil,
                zScore: nil,
                history: []
            )
        }

        let baselineSource = ordered.dropLast(scoringExclusionDays).map(\.value)
        guard baselineSource.count >= minimumSamplesForBaseline,
              let mean = MathSupport.mean(baselineSource), mean != 0 else {
            return VitalReading(
                sign: sign,
                latest: latest,
                baselineMean: nil,
                baselineDeviation: nil,
                zScore: nil,
                history: ordered
            )
        }

        let variance = baselineSource.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(baselineSource.count)
        let deviation = max(variance.squareRoot(), abs(mean) * deviationFloorFraction)

        return VitalReading(
            sign: sign,
            latest: latest,
            baselineMean: mean,
            baselineDeviation: deviation,
            zScore: (latest.value - mean) / deviation,
            history: ordered
        )
    }

    /// Readings for every sign present in `samples`, in category then declaration order.
    static func readings(from samples: [VitalSample]) -> [VitalReading] {
        let grouped = Dictionary(grouping: samples, by: \.sign)
        return VitalSign.allCases
            .compactMap { sign in
                guard let signSamples = grouped[sign], !signSamples.isEmpty else { return nil }
                return reading(for: sign, samples: signSamples)
            }
            .sorted { lhs, rhs in
                if lhs.sign.category.order != rhs.sign.category.order {
                    return lhs.sign.category.order < rhs.sign.category.order
                }
                return lhs.sign.rawValue < rhs.sign.rawValue
            }
    }

    // MARK: - Deviation score

    /// How unusual this morning is across the signals that move together.
    ///
    /// The orientation step is what makes the combination legitimate. A drop in HRV and a
    /// rise in resting heart rate tell the same story with opposite signs, so summing the
    /// raw z-scores would cancel them out — precisely on the mornings the score exists to
    /// catch. Each z is therefore turned so positive always means "away from the fitter
    /// direction" before anything is combined.
    ///
    /// Magnitude is a root-mean-square rather than a mean, so one signal moving three
    /// deviations is not diluted by three signals sitting still.
    static func deviationScore(from readings: [VitalReading]) -> DeviationScore {
        var contributors: [DeviationScore.Contributor] = []

        for reading in readings where reading.sign.participatesInDeviationScore {
            guard let z = reading.zScore, z.isFinite else { continue }
            let oriented: Double
            switch reading.sign.polarity {
            case .higherIsFitter: oriented = -z
            case .lowerIsFitter: oriented = z
            case .neutral: oriented = abs(z)
            }
            contributors.append(
                DeviationScore.Contributor(sign: reading.sign, zScore: z, orientedZ: oriented)
            )
        }

        guard !contributors.isEmpty else { return .none }

        // Only the ones pointing away from the fitter direction raise the magnitude. A
        // morning where HRV is unusually *high* is not an anomaly to report.
        let adverse = contributors.map { max(0, $0.orientedZ) }
        let meanSquare = adverse.reduce(0) { $0 + $1 * $1 } / Double(adverse.count)

        return DeviationScore(
            contributors: contributors.sorted { $0.orientedZ > $1.orientedZ },
            magnitude: meanSquare.squareRoot(),
            availableSignals: contributors.count
        )
    }

    // MARK: - Copy

    /// One sentence about a morning that looks unusual, or `nil` when it does not.
    ///
    /// §12 in one function. It says what moved and by how much, and it routes symptoms to a
    /// clinician. It does not name a cause, and the words "illness", "infection" and every
    /// condition name are absent by construction — the sentence is assembled from signal
    /// names and numbers only.
    static func deviationSummary(for score: DeviationScore) -> String? {
        guard score.isWorthReporting else { return nil }
        let named = score.contributors
            .filter { $0.orientedZ >= 1.0 }
            .prefix(3)
            .map { $0.sign.displayName.lowercased() }
        guard !named.isEmpty else { return nil }

        let list = named.joined(separator: ", ")
        return "Bu sabah \(list) aynı anda son 60 gününün dışında. Bu bir teşhis değil, bir gözlem — kendini nasıl hissettiğine bak, bir şikâyetin varsa hekimine danış."
    }

    /// The trend direction over a window, as a per-day slope from an ordinary least-squares
    /// fit. `nil` when there are too few points for a line to mean anything.
    static func slopePerDay(of samples: [VitalSample]) -> Double? {
        guard samples.count >= 8 else { return nil }
        let ordered = samples.sorted { $0.dayStart < $1.dayStart }
        guard let origin = ordered.first?.dayStart else { return nil }

        return MathSupport.leastSquaresSlope(
            xs: ordered.map { $0.dayStart.timeIntervalSince(origin) / 86_400 },
            ys: ordered.map(\.value)
        )
    }
}
