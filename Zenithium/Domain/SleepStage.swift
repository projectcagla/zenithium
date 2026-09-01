//
//  SleepStage.swift
//  Zenithium
//
//  Sleep stages. Spec §3: asleep = core + deep + REM; `.inBed` is never counted as asleep.
//  Raw values mirror `HKCategoryValueSleepAnalysis` but are declared here so `Domain` and
//  `Engines` never import HealthKit.
//

import Foundation

/// One sleep stage as recorded by `HKCategoryTypeIdentifier.sleepAnalysis`.
enum SleepStage: String, Sendable, Codable, CaseIterable, Hashable {

    /// `HKCategoryValueSleepAnalysis.inBed` — time in bed, never counted as asleep (§3).
    case inBed

    /// `HKCategoryValueSleepAnalysis.awake` — awake during the sleep opportunity.
    case awake

    /// `HKCategoryValueSleepAnalysis.asleepCore`.
    case asleepCore

    /// `HKCategoryValueSleepAnalysis.asleepDeep`.
    case asleepDeep

    /// `HKCategoryValueSleepAnalysis.asleepREM`.
    case asleepREM

    /// `HKCategoryValueSleepAnalysis.asleepUnspecified` — asleep, but the source did not stage it.
    case asleepUnspecified

    /// The raw integer `HKCategoryValueSleepAnalysis` uses. Declared here so the mapping is
    /// reviewable in one place; `Health/HealthKitMapping.swift` converts using these values
    /// rather than hard-coding integers at the call site.
    var healthKitRawValue: Int {
        switch self {
        case .inBed: return 0
        case .asleepUnspecified: return 1
        case .awake: return 2
        case .asleepCore: return 3
        case .asleepDeep: return 4
        case .asleepREM: return 5
        }
    }

    /// The inverse mapping. Unknown raw values return `nil` rather than defaulting to a stage.
    static func stage(forHealthKitRawValue rawValue: Int) -> SleepStage? {
        SleepStage.allCases.first { $0.healthKitRawValue == rawValue }
    }

    /// Spec §3 — asleep is core + deep + REM. Unspecified counts as asleep but not as staged.
    var isAsleep: Bool {
        switch self {
        case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified:
            return true
        case .inBed, .awake:
            return false
        }
    }

    /// Whether the stage carries stage detail. Used to decide whether `Restorative` can be
    /// scored or must be dropped and the remaining weights renormalized (§5.2).
    var isStaged: Bool {
        switch self {
        case .asleepCore, .asleepDeep, .asleepREM:
            return true
        case .asleepUnspecified, .inBed, .awake:
            return false
        }
    }

    /// Whether the stage contributes to the restorative fraction, `(deep + REM) / asleep` (§5.2).
    var isRestorative: Bool {
        switch self {
        case .asleepDeep, .asleepREM:
            return true
        case .asleepCore, .asleepUnspecified, .inBed, .awake:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .inBed: return "Yatakta"
        case .awake: return "Uyanık"
        case .asleepCore: return "Hafif"
        case .asleepDeep: return "Derin"
        case .asleepREM: return "REM"
        case .asleepUnspecified: return "Uykuda"
        }
    }
}
