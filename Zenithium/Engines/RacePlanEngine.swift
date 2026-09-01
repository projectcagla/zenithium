//
//  RacePlanEngine.swift
//  Zenithium
//
//  Turning a course and a target into kilometre splits. Yol haritası v4, C2.
//
//  ## The idea
//
//  A runner holds an effort, not a pace. On a course with hills, holding an even *pace* means
//  spending far more on the climbs than on the descents and arriving at the finish having run
//  the second half on nothing. Holding an even *effort* means the pace moves with the ground —
//  and the plan's job is to say by how much.
//
//  `EnduranceEngine.gradeCostRatio` already answers "how much does this gradient cost", from
//  the Minetti curve the endurance screen uses for grade-adjusted pace. This engine runs it in
//  the other direction: given a flat-equivalent pace `p`, the pace to hold on a gradient `g` is
//  `p · ratio(g)`.
//
//  That makes the finish time a closed form rather than a search:
//
//      T = Σ dᵢ · p · ratio(gᵢ)  =  p · Σ dᵢ · ratio(gᵢ)
//
//  so `p = T / Σ dᵢ · ratio(gᵢ)`. No iteration, no convergence criteria, and the split times
//  add up to the target exactly rather than approximately.
//
//  ## What it does not claim
//
//  It does not say whether a target is achievable — the endurance screen's critical-speed
//  model does that, and only for the runner's own recent efforts. It does not model heat,
//  altitude, wind, camber, surface, or the crowd on the first kilometre. It says what an even
//  effort looks like on this terrain, which is the part that can actually be computed.
//

import Foundation

enum RacePlanEngine {

    /// The nominal split length, metres.
    static let splitMetres: Double = 1_000

    /// A tail shorter than this is folded into the previous split rather than shown as its
    /// own line — a 40-metre "kilometre" at the end is noise, not a split.
    static let minimumTailMetres: Double = 100

    /// Build a plan for `course` at `target`.
    ///
    /// `nil` when the course has nothing to plan against, or when the target is not a
    /// positive time or pace.
    static func plan(course: CourseProfile, target: RaceTarget) -> RacePlan? {
        guard course.isPlannable else { return nil }

        let bounds = splitBounds(totalMetres: course.distance)
        guard !bounds.isEmpty else { return nil }

        // Each split's terrain cost, and its length in kilometres.
        var costs: [(length: Double, ratio: Double, gradient: Double, ascent: Double, descent: Double)] = []
        costs.reserveCapacity(bounds.count)

        for bound in bounds {
            guard let startElevation = course.elevation(atDistance: bound.start),
                  let endElevation = course.elevation(atDistance: bound.end) else { return nil }
            let run = bound.end - bound.start
            guard run > 0 else { continue }

            let gradient = (endElevation - startElevation) / run
            let (ascent, descent) = climb(in: course, from: bound.start, through: bound.end)

            // The cost is taken from the *sampled* profile rather than from the split's net
            // gradient: a kilometre that climbs fifty metres and drops fifty again is not a
            // flat kilometre, and averaging first would say that it is.
            costs.append((
                length: run / 1_000,
                ratio: sampledCostRatio(in: course, from: bound.start, through: bound.end),
                gradient: gradient,
                ascent: ascent,
                descent: descent
            ))
        }
        guard !costs.isEmpty else { return nil }

        let weightedKilometres = costs.reduce(0) { $0 + $1.length * $1.ratio }
        guard weightedKilometres > 0 else { return nil }

        let totalKilometres = costs.reduce(0) { $0 + $1.length }
        let flatPace: Double
        let finish: Double
        switch target {
        case .finishTime(let seconds):
            guard seconds > 0 else { return nil }
            flatPace = seconds / weightedKilometres
            finish = seconds
        case .flatPace(let pace):
            guard pace > 0 else { return nil }
            flatPace = pace
            finish = pace * weightedKilometres
        }

        var splits: [RaceSplit] = []
        var elapsed: Double = 0
        for (offset, cost) in costs.enumerated() {
            let pace = flatPace * cost.ratio
            elapsed += pace * cost.length
            splits.append(
                RaceSplit(
                    index: offset + 1,
                    startMetres: bounds[offset].start,
                    endMetres: bounds[offset].end,
                    gradient: cost.gradient,
                    ascent: cost.ascent,
                    descent: cost.descent,
                    targetPace: pace,
                    elapsedSeconds: elapsed
                )
            )
        }

        return RacePlan(
            course: course,
            targetFinishSeconds: finish,
            flatEquivalentPace: flatPace,
            splits: splits,
            terrainCostRatio: totalKilometres > 0 ? weightedKilometres / totalKilometres : 1
        )
    }

    /// A finish time this runner's own recent efforts support on this course.
    ///
    /// The critical-speed model predicts a time for a flat distance; the terrain cost then
    /// stretches it. Returned alongside the model's own extrapolation factor so the screen can
    /// say how far outside its fitted range the prediction sits — the model is known to
    /// over-predict long distances, and a marathon estimate from a set of five-minute efforts
    /// should not be presented as if it were measured.
    static func suggestedFinish(
        course: CourseProfile,
        model: CriticalSpeedModel
    ) -> (seconds: Double, extrapolation: Double)? {
        guard course.isPlannable,
              let flat = model.predictedTime(forDistance: course.distance),
              let flatPlan = plan(course: course, target: .finishTime(flat)) else { return nil }
        return (
            flat * flatPlan.terrainCostRatio,
            model.extrapolationFactor(forDistance: course.distance)
        )
    }

    // MARK: - Internals

    /// The split boundaries, with any short tail folded into the last full split.
    static func splitBounds(totalMetres: Double) -> [(start: Double, end: Double)] {
        guard totalMetres > 0 else { return [] }
        var bounds: [(start: Double, end: Double)] = []
        var start: Double = 0
        while start < totalMetres {
            let end = min(start + splitMetres, totalMetres)
            bounds.append((start, end))
            start = end
        }
        if bounds.count >= 2, let last = bounds.last, last.end - last.start < minimumTailMetres {
            bounds.removeLast()
            bounds[bounds.count - 1].end = last.end
        }
        return bounds
    }

    /// The average cost ratio across a span, sampled along the profile.
    ///
    /// Averaging the *cost* rather than the gradient is what makes rolling ground cost more
    /// than flat ground: the Minetti curve is convex, so a kilometre that goes up and back
    /// down is more expensive than one that stays level, and taking the mean gradient first
    /// would erase exactly that.
    private static func sampledCostRatio(
        in course: CourseProfile,
        from start: Double,
        through end: Double
    ) -> Double {
        let span = end - start
        guard span > 0 else { return 1 }
        let steps = max(1, Int((span / GPXReader.minimumSpacingMetres).rounded(.up)))
        let step = span / Double(steps)

        var total: Double = 0
        var previous = course.elevation(atDistance: start) ?? 0
        for index in 1...steps {
            let position = start + step * Double(index)
            let elevation = course.elevation(atDistance: position) ?? previous
            total += EnduranceEngine.gradeCostRatio(gradient: (elevation - previous) / step)
            previous = elevation
        }
        return total / Double(steps)
    }

    /// Climb and drop inside a span, metres.
    private static func climb(
        in course: CourseProfile,
        from start: Double,
        through end: Double
    ) -> (ascent: Double, descent: Double) {
        let inside = course.points.filter { $0.distance >= start && $0.distance <= end }
        guard inside.count >= 2 else { return (0, 0) }
        var ascent: Double = 0
        var descent: Double = 0
        for (lower, upper) in zip(inside, inside.dropFirst()) {
            let delta = upper.elevation - lower.elevation
            if delta > 0 { ascent += delta } else { descent -= delta }
        }
        return (ascent, descent)
    }
}
