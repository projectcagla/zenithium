//
//  StrengthEntry.swift
//  Zenithium
//
//  One exercise inside a logged strength session. Spec §5.4:
//  `sessionLoad = clamp(Σ(sets · reps · RPE) / 3.0, 0, 100)`.
//  ASSUMPTION RPE-1: RPE is per exercise, not per set, which keeps the logger to three fields.
//

import Foundation

/// One exercise's completed volume and effort.
struct StrengthEntry: Sendable, Equatable, Hashable, Codable, Identifiable {

    /// Stable identity so the logger can edit and reorder rows.
    let id: UUID

    /// Free-text exercise name. Never parsed — it is a label, not a muscle source.
    var exerciseName: String

    /// Completed sets.
    var sets: Int

    /// Reps per set.
    var reps: Int

    /// Rate of perceived exertion, 1…10 (ASSUMPTION RPE-1).
    var rpe: Double

    /// Working weight in kilograms, when the user recorded one.
    ///
    /// Optional because the field arrived in Faz 17 and every session logged before it has
    /// none — and because plenty of strength work has no weight at all. Swift's synthesized
    /// `Codable` uses `decodeIfPresent` for optionals, so records written by earlier builds
    /// decode to `nil` rather than failing.
    ///
    /// Session load deliberately does **not** use it: `volumeLoad` is sets × reps × RPE, a
    /// scale that works for bodyweight and barbell work alike. Weight feeds the one-rep-max
    /// estimate and nothing else.
    var weightKilograms: Double?

    init(
        id: UUID,
        exerciseName: String,
        sets: Int,
        reps: Int,
        rpe: Double,
        weightKilograms: Double? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.sets = sets
        self.reps = reps
        self.rpe = rpe
        self.weightKilograms = weightKilograms
    }

    /// The valid RPE range. The logger clamps to it; the engine assumes it.
    static let rpeRange: ClosedRange<Double> = 1...10

    /// The maximum sets and reps the logger accepts, so a typo cannot dominate a session.
    static let setsRange: ClosedRange<Int> = 1...30
    static let repsRange: ClosedRange<Int> = 1...100

    /// `sets · reps · RPE` — this entry's share of the session's raw volume-load (§5.4).
    var volumeLoad: Double {
        let clampedSets = min(max(sets, StrengthEntry.setsRange.lowerBound), StrengthEntry.setsRange.upperBound)
        let clampedReps = min(max(reps, StrengthEntry.repsRange.lowerBound), StrengthEntry.repsRange.upperBound)
        let clampedRPE = min(max(rpe, StrengthEntry.rpeRange.lowerBound), StrengthEntry.rpeRange.upperBound)
        return Double(clampedSets) * Double(clampedReps) * clampedRPE
    }

    /// Whether the entry is complete enough to contribute.
    var isValid: Bool {
        !exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && StrengthEntry.setsRange.contains(sets)
            && StrengthEntry.repsRange.contains(reps)
            && StrengthEntry.rpeRange.contains(rpe)
    }
}

extension Array where Element == StrengthEntry {

    /// `Σ(sets · reps · RPE)` across the valid entries (§5.4).
    var totalVolumeLoad: Double {
        reduce(into: 0) { total, entry in
            if entry.isValid { total += entry.volumeLoad }
        }
    }
}
