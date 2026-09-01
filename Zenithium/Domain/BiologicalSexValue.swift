//
//  BiologicalSexValue.swift
//  Zenithium
//
//  Sendable projection of `HKCharacteristicTypeIdentifier.biologicalSex`, plus the
//  sex-specific Banister TRIMP constants. Spec §5.3, ASSUMPTION API-2.
//

import Foundation

/// The Banister TRIMP shape constants, `b` and `c` (§5.3).
struct TRIMPConstants: Sendable, Equatable, Hashable {

    /// Linear coefficient `b`.
    let b: Double

    /// Exponential coefficient `c`.
    let c: Double
}

/// Biological sex as HealthKit reports it, with `.notSet` and `.other` kept distinct from
/// `.female` so the UI can say the value is unknown even though both share TRIMP constants.
enum BiologicalSexValue: String, Sendable, Codable, CaseIterable, Hashable {
    case female
    case male
    case other
    case notSet

    /// Spec §5.3 — `male → b 0.64, c 1.92`; `female / unspecified → b 0.86, c 1.67`.
    ///
    /// ASSUMPTION API-2: `.other` and `.notSet` take the female/unspecified constants, which
    /// avoids under-reporting strain for users who did not disclose sex.
    var trimpConstants: TRIMPConstants {
        switch self {
        case .male:
            return TRIMPConstants(b: 0.64, c: 1.92)
        case .female, .other, .notSet:
            return TRIMPConstants(b: 0.86, c: 1.67)
        }
    }

    /// Whether the value was actually supplied, for UI that offers to fill the gap.
    var isSpecified: Bool {
        switch self {
        case .female, .male, .other: return true
        case .notSet: return false
        }
    }

    var displayName: String {
        switch self {
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        case .notSet: return "Not set"
        }
    }
}
