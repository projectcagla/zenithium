//
//  UserCharacteristics.swift
//  Zenithium
//
//  The Sendable projection of HealthKit characteristic types. Spec §8
//  (`fetchCharacteristics()`), §5.3 (age feeds the Tanaka HRmax estimate).
//

import Foundation

/// Immutable facts about the user, read once from HealthKit and overridable in Settings.
struct UserCharacteristics: Sendable, Equatable, Hashable {

    /// Date of birth, if HealthKit has one and access was granted.
    let dateOfBirth: Date?

    /// Biological sex, defaulting to `.notSet` when unavailable.
    let biologicalSex: BiologicalSexValue

    /// A user-entered override for maximum heart rate, in bpm (§5.3).
    let maxHeartRateOverride: Double?

    init(
        dateOfBirth: Date?,
        biologicalSex: BiologicalSexValue,
        maxHeartRateOverride: Double?
    ) {
        self.dateOfBirth = dateOfBirth
        self.biologicalSex = biologicalSex
        self.maxHeartRateOverride = maxHeartRateOverride
    }

    /// The value used when nothing is known.
    static let unknown = UserCharacteristics(
        dateOfBirth: nil,
        biologicalSex: .notSet,
        maxHeartRateOverride: nil
    )

    /// Age in whole years at `now`, in the supplied calendar.
    ///
    /// Returns `nil` when the date of birth is unknown or in the future. Callers must not
    /// substitute a default here — the `35` fallback belongs to the strain engine so it can
    /// be logged once as `ASSUMPTION HRMAX-1` (§5.3).
    func age(at now: Date, calendar: Calendar) -> Int? {
        guard let dateOfBirth else { return nil }
        guard dateOfBirth <= now else { return nil }
        let components = calendar.dateComponents([.year], from: dateOfBirth, to: now)
        guard let years = components.year, years >= 0, years < 130 else { return nil }
        return years
    }
}
