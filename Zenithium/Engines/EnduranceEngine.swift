//
//  EnduranceEngine.swift
//  Zenithium
//
//  The endurance lens's mathematics. Faz 15.
//
//  Everything here hangs off one fit. Given a handful of best efforts, the critical-speed
//  model gives a sustainable speed and a finite distance above it; from those come pace
//  zones that are measured rather than assumed, and race predictions calibrated to this
//  runner rather than to a table.
//
//  The model's known weakness is stated rather than hidden: it has no term for the slow
//  component of oxygen uptake, so it over-predicts long-distance performance. That is why
//  `RacePrediction` carries an extrapolation factor and the marathon prediction says so out
//  loud instead of quietly being wrong.
//

import Foundation

enum EnduranceEngine {

    /// Efforts shorter than this are dominated by D′ and bend the fit.
    static let minimumEffortSeconds: Double = 120

    /// Efforts longer than this drift from the two-parameter model.
    static let maximumEffortSeconds: Double = 2_400

    /// How far back best efforts stay eligible.
    static let effortWindowDays: Int = 120

    /// Below this many efforts there is no fit.
    static let minimumEfforts: Int = 3

    // MARK: - Fitting

    /// Fit `d = CS·t + D′` by ordinary least squares.
    ///
    /// The distance–time form is linear, so the fit is exact and closed-form. The
    /// speed–time form `v = CS + D′/t` is the same model but non-linear in its parameters,
    /// and fitting it would mean iterating for no gain in accuracy.
    ///
    /// Returns `nil` when there are too few usable efforts, when they do not span enough
    /// time to define a slope, or when the fit produces a negative D′ — which means these
    /// efforts do not describe a critical-speed relationship and reporting a model anyway
    /// would be inventing one.
    static func fit(efforts: [BestEffort], now: Date = Date()) -> CriticalSpeedModel? {
        let cutoff = now.addingTimeInterval(-Double(effortWindowDays) * 86_400)
        let usable = efforts.filter {
            $0.date >= cutoff
                && $0.duration >= minimumEffortSeconds
                && $0.duration <= maximumEffortSeconds
                && $0.distance > 0
        }
        guard usable.count >= minimumEfforts else { return nil }

        // One effort per distance: the fastest. Two efforts at the same distance add no
        // information about the slope and let a single bad day drag the fit.
        var bestByDistance: [Int: BestEffort] = [:]
        for effort in usable {
            let key = Int(effort.distance.rounded())
            if let existing = bestByDistance[key], existing.duration <= effort.duration { continue }
            bestByDistance[key] = effort
        }
        let points = Array(bestByDistance.values)
        guard points.count >= minimumEfforts else { return nil }

        let times = points.map(\.duration)
        let distances = points.map(\.distance)
        guard let meanTime = MathSupport.mean(times), let meanDistance = MathSupport.mean(distances) else {
            return nil
        }

        var covariance = 0.0
        var variance = 0.0
        for (time, distance) in zip(times, distances) {
            covariance += (time - meanTime) * (distance - meanDistance)
            variance += (time - meanTime) * (time - meanTime)
        }
        guard variance > 0 else { return nil }

        let slope = covariance / variance
        let intercept = meanDistance - slope * meanTime
        guard slope > 0, intercept >= 0 else { return nil }

        // R² against the fitted line.
        var residual = 0.0
        var total = 0.0
        for (time, distance) in zip(times, distances) {
            let predicted = slope * time + intercept
            residual += (distance - predicted) * (distance - predicted)
            total += (distance - meanDistance) * (distance - meanDistance)
        }
        let rSquared = total > 0 ? max(0, 1 - residual / total) : 0

        return CriticalSpeedModel(
            criticalSpeed: slope,
            anaerobicDistance: intercept,
            effortCount: points.count,
            shortestDuration: times.min() ?? 0,
            longestDuration: times.max() ?? 0,
            rSquared: rSquared
        )
    }

    // MARK: - Predictions

    static func predictions(from model: CriticalSpeedModel) -> [RacePrediction] {
        RaceDistance.allCases.compactMap { distance in
            guard let seconds = model.predictedTime(forDistance: distance.metres), seconds > 0 else {
                return nil
            }
            return RacePrediction(
                distance: distance,
                seconds: seconds,
                pace: seconds / (distance.metres / 1000),
                extrapolationFactor: model.extrapolationFactor(forDistance: distance.metres)
            )
        }
    }

    // MARK: - Zones

    /// Pace bands from the model.
    ///
    /// A faster speed is a *smaller* pace, so the band's fast end comes from its upper speed
    /// fraction. Getting that backwards is the easiest mistake in this file and the reason
    /// the two are named rather than indexed.
    static func paceZones(from model: CriticalSpeedModel) -> [PaceZoneBand] {
        guard model.criticalSpeed > 0 else { return [] }
        return PaceZone.allCases.map { zone in
            let fastSpeed = model.criticalSpeed * zone.speedFraction.upperBound
            let slowSpeed = model.criticalSpeed * zone.speedFraction.lowerBound
            return PaceZoneBand(
                zone: zone,
                fastPace: 1000 / fastSpeed,
                slowPace: 1000 / slowSpeed
            )
        }
    }

    /// Which zone a pace falls in.
    static func zone(forPace pace: Double, model: CriticalSpeedModel) -> PaceZone? {
        guard pace > 0, model.criticalSpeed > 0 else { return nil }
        let fraction = (1000 / pace) / model.criticalSpeed
        return PaceZone.allCases.first { $0.speedFraction.contains(fraction) }
    }

    // MARK: - Decoupling

    /// Compare a run's two halves.
    ///
    /// Efficiency is speed per heartbeat. Splitting by elapsed time rather than by distance
    /// is deliberate: a run that slowed down covers less ground in its second half, and
    /// splitting by distance would put more of the tired portion into the "first" half and
    /// mask the very drift being measured.
    static func decoupling(
        firstHalfSpeed: Double,
        firstHalfHeartRate: Double,
        secondHalfSpeed: Double,
        secondHalfHeartRate: Double
    ) -> AerobicDecoupling? {
        guard firstHalfHeartRate > 0, secondHalfHeartRate > 0,
              firstHalfSpeed > 0, secondHalfSpeed > 0 else { return nil }

        let first = firstHalfSpeed / firstHalfHeartRate
        let second = secondHalfSpeed / secondHalfHeartRate
        guard first > 0 else { return nil }

        return AerobicDecoupling(
            firstHalfEfficiency: first,
            secondHalfEfficiency: second,
            drift: (first - second) / first
        )
    }

    // MARK: - Grade adjustment

    /// Pace adjusted for gradient, seconds per kilometre.
    ///
    /// Uses the Minetti energy-cost curve, normalised so level ground costs 1. Running
    /// uphill costs more than downhill saves, and below about −18% the cost starts rising
    /// again as braking takes over — which the fitted curve captures and a linear "add 15
    /// seconds per percent" rule does not.
    ///
    /// The gradient is clamped to ±30%, beyond which the fitted curve is extrapolation.
    static func gradeAdjustedPace(pace: Double, gradient: Double) -> Double {
        guard pace > 0 else { return pace }
        let ratio = gradeCostRatio(gradient: gradient)
        guard ratio > 0 else { return pace }
        return pace / ratio
    }

    /// The pace to actually run on `gradient` to spend the same energy as `pace` on the flat.
    ///
    /// The inverse of `gradeAdjustedPace`, and what a race plan needs: the runner has a flat
    /// effort in mind and wants to know what the watch should read going up the hill.
    /// Yol haritası v4, C2.
    static func pace(forFlatEquivalent pace: Double, gradient: Double) -> Double {
        guard pace > 0 else { return pace }
        return pace * gradeCostRatio(gradient: gradient)
    }

    /// How much a gradient costs relative to level ground. 1 is flat.
    ///
    /// Minetti et al. (2002), cost of running in J/kg/m, reduced to a quintic that matches
    /// the published curve closely over ±30%. Running uphill costs more than downhill saves,
    /// and below the curve's minimum the cost starts rising again as braking takes over —
    /// which the fitted curve captures and a linear "add fifteen seconds per percent" rule
    /// does not.
    ///
    /// That minimum is at −18.1%, not the −10% two comments here used to claim. Measured off
    /// the coefficients below and pinned by `MinettiCurveTests`, because "about −10%" sent a
    /// reader looking for a turning point eight percent away from where it is.
    ///
    /// The gradient is clamped to ±30%, beyond which the curve is extrapolation.
    static func gradeCostRatio(gradient: Double) -> Double {
        let g = MathSupport.clamp(gradient, -0.30, 0.30)
        let cost = 155.4 * pow(g, 5) - 30.4 * pow(g, 4) - 43.3 * pow(g, 3)
            + 46.3 * g * g + 19.5 * g + 3.6
        let levelCost = 3.6
        return cost / levelCost
    }

    // MARK: - Copy

    static func summary(for model: CriticalSpeedModel) -> String {
        let pace = ZenithiumFormat.pace(secondsPerKilometre: model.criticalPace)
        let base = "Kritik hızın \(pace) — bir saat boyunca sürdürebileceğin tempo civarı."
        guard !model.isWellConditioned else { return base }
        return base + " Model \(model.effortCount) efordan kuruldu; daha geniş aralıkta eforlar biriktikçe keskinleşecek."
    }
}
