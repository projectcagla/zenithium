//
//  WorkoutActivity.swift
//  Zenithium
//
//  Sendable projection of `HKWorkoutActivityType`. Spec §5.4 requires the involvement matrix
//  to cover every activity type the app supports; declaring the set here keeps
//  `Engines/MuscleInvolvementMatrix.swift` free of any HealthKit import.
//  ASSUMPTION MUSCLE-1: 30 cases — the 7 normative rows plus 23 derived by the same logic;
//  anything HealthKit reports outside this set maps to `.other`.
//

import Foundation

/// A workout activity, named in domain terms.
///
/// `Health/HealthKitTypeCatalog.swift` owns the one-way mapping from `HKWorkoutActivityType`.
enum WorkoutActivity: String, Sendable, Codable, CaseIterable, Hashable {
    case running
    case walking
    case hiking
    case cycling
    case swimming
    case rowing
    case elliptical
    case stairClimbing
    case highIntensityIntervalTraining
    case traditionalStrengthTraining
    case functionalStrengthTraining
    case coreTraining
    case yoga
    case pilates
    case flexibility
    case cardioDance
    case boxing
    case martialArts
    case tennis
    case basketball
    case soccer
    case golf
    case jumpRope
    case crossTraining
    case mixedCardio
    case climbing
    case paddleSports
    case skatingSports
    case downhillSkiing
    case other

    var displayName: String {
        switch self {
        case .running: return "Koşu"
        case .walking: return "Yürüyüş"
        case .hiking: return "Doğa yürüyüşü"
        case .cycling: return "Bisiklet"
        case .swimming: return "Yüzme"
        case .rowing: return "Kürek"
        case .elliptical: return "Eliptik"
        case .stairClimbing: return "Merdiven"
        case .highIntensityIntervalTraining: return "HIIT"
        case .traditionalStrengthTraining: return "Kuvvet antrenmanı"
        case .functionalStrengthTraining: return "Fonksiyonel kuvvet"
        case .coreTraining: return "Merkez çalışması"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .flexibility: return "Esneklik"
        case .cardioDance: return "Dans"
        case .boxing: return "Boks"
        case .martialArts: return "Dövüş sanatları"
        case .tennis: return "Tenis"
        case .basketball: return "Basketbol"
        case .soccer: return "Futbol"
        case .golf: return "Golf"
        case .jumpRope: return "İp atlama"
        case .crossTraining: return "Çapraz antrenman"
        case .mixedCardio: return "Karma kardiyo"
        case .climbing: return "Tırmanış"
        case .paddleSports: return "Kürek sporları"
        case .skatingSports: return "Paten"
        case .downhillSkiing: return "Kayak"
        case .other: return "Antrenman"
        }
    }

    var symbolName: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .rowing: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .stairClimbing: return "figure.stair.stepper"
        case .highIntensityIntervalTraining: return "figure.highintensity.intervaltraining"
        case .traditionalStrengthTraining: return "figure.strengthtraining.traditional"
        case .functionalStrengthTraining: return "figure.strengthtraining.functional"
        case .coreTraining: return "figure.core.training"
        case .yoga: return "figure.yoga"
        case .pilates: return "figure.pilates"
        case .flexibility: return "figure.flexibility"
        case .cardioDance: return "figure.dance"
        case .boxing: return "figure.boxing"
        case .martialArts: return "figure.martial.arts"
        case .tennis: return "figure.tennis"
        case .basketball: return "figure.basketball"
        case .soccer: return "figure.soccer"
        case .golf: return "figure.golf"
        case .jumpRope: return "figure.jumprope"
        case .crossTraining: return "figure.cross.training"
        case .mixedCardio: return "figure.mixed.cardio"
        case .climbing: return "figure.climbing"
        case .paddleSports: return "figure.rower"
        case .skatingSports: return "figure.skating"
        case .downhillSkiing: return "figure.skiing.downhill"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Whether HealthKit is allowed to contribute muscle impact for this activity.
    ///
    /// ASSUMPTION MUSCLE-2: strength types contribute zero muscle impact from HealthKit —
    /// only a logged `StrengthSessionLog` produces their impacts — but their TRIMP still
    /// counts toward daily strain (§5.4).
    var contributesMuscleImpactFromHealthKit: Bool {
        switch self {
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return false
        default:
            return true
        }
    }

    /// Whether the activity should prompt the user to log a strength session.
    var invitesStrengthLogging: Bool {
        !contributesMuscleImpactFromHealthKit
    }
}
