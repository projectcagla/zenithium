//
//  MuscleFatigueSnapshot.swift
//  Zenithium
//
//  A cached projection of the 16-muscle fatigue state. Spec §7.
//  ASSUMPTION MUSCLE-3: this is a cache, never the source of truth — fatigue is always
//  re-projectable from the trailing sessions, which is what makes an engine-version backfill
//  possible.
//  ASSUMPTION STORE-4: the natural key is a derived string rather than a compound unique
//  constraint, so the schema needs no macro beyond `@Attribute(.unique)`.
//

import Foundation
import SwiftData

@Model
final class MuscleFatigueSnapshot {

    /// `"\(computedAt epoch seconds)-\(engineVersion)"`. Unique (ASSUMPTION STORE-4).
    @Attribute(.unique) var snapshotKey: String

    /// The instant fatigue was projected to.
    var computedAt: Date

    /// Fatigue per muscle, 0…100, positionally by `MuscleGroup.storageIndex`.
    ///
    /// Positional storage is why `MuscleGroup`'s case order may never change without a
    /// migration (§5.4 fixed enum order).
    var fatigueValues: [Double]

    /// Half-life per muscle, hours, positionally. Stored so the detail view can draw the
    /// decay curve without re-deriving the sleep modifier.
    var halfLifeHours: [Double]

    /// The sleep score that produced the half-lives (§5.4).
    var sleepScoreUsed: Double

    /// Stamped so a formula change can trigger a rebuild (§7).
    var engineVersion: Int

    init(
        computedAt: Date,
        fatigueValues: [Double],
        halfLifeHours: [Double],
        sleepScoreUsed: Double,
        engineVersion: Int
    ) {
        self.snapshotKey = MuscleFatigueSnapshot.key(computedAt: computedAt, engineVersion: engineVersion)
        self.computedAt = computedAt
        self.fatigueValues = fatigueValues
        self.halfLifeHours = halfLifeHours
        self.sleepScoreUsed = sleepScoreUsed
        self.engineVersion = engineVersion
    }

    /// The natural key, derived from the two fields that identify a projection.
    static func key(computedAt: Date, engineVersion: Int) -> String {
        "\(Int(computedAt.timeIntervalSince1970))-\(engineVersion)"
    }

    /// Fatigue for one muscle, 0…100.
    func fatigue(for muscle: MuscleGroup) -> Double {
        guard muscle.storageIndex < fatigueValues.count else { return 0 }
        return fatigueValues[muscle.storageIndex]
    }

    /// Readiness for one muscle, 0…100 (§5.4).
    func readiness(for muscle: MuscleGroup) -> Double {
        min(max(100 - fatigue(for: muscle), 0), 100)
    }

    /// Half-life for one muscle, hours.
    func halfLife(for muscle: MuscleGroup) -> Double? {
        guard muscle.storageIndex < halfLifeHours.count else { return nil }
        return halfLifeHours[muscle.storageIndex]
    }

    /// Builds the positional arrays from an engine result.
    static func arrays(
        from readiness: [MuscleGroup: MuscleReadiness]
    ) -> (fatigue: [Double], halfLife: [Double]) {
        var fatigue = Array(repeating: 0.0, count: MuscleGroup.allCases.count)
        var halfLife = Array(repeating: 0.0, count: MuscleGroup.allCases.count)
        for muscle in MuscleGroup.allCases {
            guard let value = readiness[muscle] else { continue }
            fatigue[muscle.storageIndex] = value.fatigue
            halfLife[muscle.storageIndex] = value.halfLifeHours
        }
        return (fatigue, halfLife)
    }
}
