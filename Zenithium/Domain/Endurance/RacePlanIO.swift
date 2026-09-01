//
//  RacePlanIO.swift
//  Zenithium
//
//  The pacing plan's vocabulary. Yol haritası v4, C2.
//

import Foundation

/// One kilometre of the plan.
struct RaceSplit: Sendable, Equatable, Hashable, Identifiable {

    /// 1 for the first kilometre.
    let index: Int

    /// Where the split starts and ends, metres from the start.
    let startMetres: Double
    let endMetres: Double

    /// Average gradient across the split, as a fraction. 0.02 is 2% up.
    let gradient: Double

    /// Climb and drop inside the split, metres.
    let ascent: Double
    let descent: Double

    /// What to actually run here, seconds per kilometre.
    let targetPace: Double

    /// Clock time at the end of this split, seconds from the gun.
    let elapsedSeconds: Double

    var id: Int { index }

    /// The split's own length in kilometres — the last one is usually short.
    var lengthKilometres: Double { (endMetres - startMetres) / 1_000 }

    /// How much slower or faster than the flat-equivalent pace, in seconds per kilometre.
    func deltaFromFlat(_ flatPace: Double) -> Double { targetPace - flatPace }
}

/// A pacing plan for one course at one target.
struct RacePlan: Sendable, Equatable {

    let course: CourseProfile

    /// The finish time the plan is built for, seconds.
    let targetFinishSeconds: Double

    /// The even effort the plan spends, expressed as a pace on flat ground, seconds per
    /// kilometre. Nobody runs this pace anywhere on a hilly course — it is the constant the
    /// splits are derived from.
    let flatEquivalentPace: Double

    /// Kilometre by kilometre.
    let splits: [RaceSplit]

    /// What the terrain costs relative to a flat course of the same length. 1.04 means the
    /// course is 4% more expensive than a track.
    let terrainCostRatio: Double

    /// The average pace the clock will show, seconds per kilometre.
    var averagePace: Double {
        course.distance > 0 ? targetFinishSeconds / (course.distance / 1_000) : 0
    }

    /// The steepest climb and the steepest descent, for the summary line.
    var hardestClimb: RaceSplit? { splits.max { $0.gradient < $1.gradient } }
    var steepestDescent: RaceSplit? { splits.min { $0.gradient < $1.gradient } }
}

/// How the runner stated their target.
enum RaceTarget: Sendable, Equatable, Hashable {

    /// A finish time, in seconds.
    case finishTime(Double)

    /// An even effort expressed as a flat pace, seconds per kilometre.
    case flatPace(Double)
}
