//
//  MuscleInvolvementMatrix.swift
//  Zenithium
//
//  Activity → muscle involvement. Spec §5.4.
//
//  The seven rows the specification gives are normative and reproduced exactly. The
//  remaining twenty-three are derived by the same logic (ASSUMPTION MUSCLE-1): the primary
//  movers of the activity, weighted by how much of the session's load each carries, on the
//  same 0…1 scale.
//
//  ASSUMPTION MUSCLE-2: the two strength activity types return an empty row. HealthKit knows
//  a strength session happened but not what was trained, and §5.4 forbids fabricating it —
//  their cardiovascular cost still counts toward daily strain.
//

import Foundation

enum MuscleInvolvementMatrix {

    /// The involvement row for a HealthKit activity.
    static func involvement(for activity: WorkoutActivity) -> [MuscleGroup: Double] {
        switch activity {

        // MARK: Normative rows (§5.4)

        case .running:
            return [.quads: 0.55, .hamstrings: 0.50, .calves: 0.70, .glutes: 0.45,
                    .core: 0.25, .lowerBack: 0.20]

        case .cycling:
            return [.quads: 0.75, .glutes: 0.50, .calves: 0.35, .hamstrings: 0.30,
                    .lowerBack: 0.25]

        case .swimming:
            return [.lats: 0.70, .shoulders: 0.65, .upperBack: 0.50, .triceps: 0.40,
                    .core: 0.45]

        case .rowing:
            return [.lats: 0.70, .upperBack: 0.65, .quads: 0.50, .biceps: 0.40,
                    .lowerBack: 0.45, .core: 0.35]

        case .hiking:
            return [.quads: 0.55, .glutes: 0.55, .calves: 0.50, .hamstrings: 0.40,
                    .core: 0.20]

        case .walking:
            return [.calves: 0.25, .quads: 0.20, .glutes: 0.20]

        case .traditionalStrengthTraining, .functionalStrengthTraining:
            // ASSUMPTION MUSCLE-2 — muscle impact comes only from a logged session.
            return [:]

        // MARK: Derived rows (ASSUMPTION MUSCLE-1)

        case .elliptical:
            // Cycling's lower body with a light upper-body pull from the handles.
            return [.quads: 0.50, .glutes: 0.45, .hamstrings: 0.35, .calves: 0.30,
                    .core: 0.20, .upperBack: 0.20, .triceps: 0.15]

        case .stairClimbing:
            // Hiking's pattern, steeper: more glute and quad, less calf travel.
            return [.quads: 0.65, .glutes: 0.65, .calves: 0.45, .hamstrings: 0.40,
                    .core: 0.20, .lowerBack: 0.20]

        case .highIntensityIntervalTraining:
            // Whole-body by construction, at moderate involvement everywhere.
            return [.quads: 0.50, .glutes: 0.45, .hamstrings: 0.40, .calves: 0.35,
                    .core: 0.45, .shoulders: 0.35, .chest: 0.30, .triceps: 0.30,
                    .upperBack: 0.30, .lats: 0.25, .lowerBack: 0.25]

        case .coreTraining:
            return [.core: 0.85, .lowerBack: 0.40, .glutes: 0.25, .shoulders: 0.20]

        case .yoga:
            return [.core: 0.45, .shoulders: 0.40, .quads: 0.35, .hamstrings: 0.35,
                    .lowerBack: 0.30, .glutes: 0.25, .triceps: 0.20]

        case .pilates:
            return [.core: 0.70, .glutes: 0.35, .adductors: 0.30, .lowerBack: 0.30,
                    .quads: 0.25, .shoulders: 0.20]

        case .flexibility:
            // Mobility work loads tissue lightly and broadly; it should register, not vanish.
            return [.hamstrings: 0.20, .quads: 0.15, .lowerBack: 0.15, .shoulders: 0.15,
                    .adductors: 0.15, .core: 0.10]

        case .cardioDance:
            return [.quads: 0.45, .calves: 0.45, .glutes: 0.40, .core: 0.35,
                    .hamstrings: 0.30, .shoulders: 0.25, .adductors: 0.25]

        case .boxing:
            return [.shoulders: 0.65, .core: 0.55, .chest: 0.40, .triceps: 0.40,
                    .lats: 0.35, .calves: 0.35, .upperBack: 0.30, .forearms: 0.30]

        case .martialArts:
            return [.core: 0.55, .quads: 0.50, .shoulders: 0.45, .glutes: 0.40,
                    .hamstrings: 0.35, .calves: 0.35, .adductors: 0.35, .lowerBack: 0.25]

        case .tennis:
            return [.quads: 0.50, .shoulders: 0.50, .core: 0.45, .calves: 0.45,
                    .forearms: 0.40, .glutes: 0.35, .lats: 0.30, .adductors: 0.30]

        case .basketball:
            return [.quads: 0.60, .calves: 0.55, .glutes: 0.50, .hamstrings: 0.40,
                    .core: 0.30, .shoulders: 0.25, .adductors: 0.25]

        case .soccer:
            return [.quads: 0.60, .hamstrings: 0.55, .calves: 0.55, .glutes: 0.50,
                    .adductors: 0.45, .core: 0.30, .lowerBack: 0.20]

        case .golf:
            return [.core: 0.40, .lats: 0.30, .forearms: 0.30, .shoulders: 0.25,
                    .lowerBack: 0.25, .glutes: 0.20]

        case .jumpRope:
            return [.calves: 0.75, .quads: 0.40, .shoulders: 0.30, .forearms: 0.25,
                    .core: 0.25, .hamstrings: 0.20]

        case .crossTraining:
            return [.quads: 0.50, .glutes: 0.45, .core: 0.40, .shoulders: 0.40,
                    .lats: 0.35, .triceps: 0.30, .hamstrings: 0.30, .calves: 0.25,
                    .lowerBack: 0.25]

        case .mixedCardio:
            return [.quads: 0.45, .calves: 0.40, .glutes: 0.35, .hamstrings: 0.30,
                    .core: 0.25]

        case .climbing:
            return [.forearms: 0.75, .lats: 0.65, .biceps: 0.55, .upperBack: 0.50,
                    .core: 0.45, .shoulders: 0.40, .quads: 0.30, .calves: 0.25]

        case .paddleSports:
            return [.lats: 0.60, .shoulders: 0.55, .core: 0.50, .upperBack: 0.45,
                    .triceps: 0.35, .biceps: 0.30, .lowerBack: 0.30]

        case .skatingSports:
            return [.quads: 0.60, .glutes: 0.55, .adductors: 0.50, .hamstrings: 0.40,
                    .calves: 0.35, .core: 0.30, .lowerBack: 0.25]

        case .downhillSkiing:
            return [.quads: 0.70, .glutes: 0.50, .adductors: 0.40, .core: 0.35,
                    .calves: 0.30, .hamstrings: 0.30, .lowerBack: 0.25]

        case .other:
            return fallbackRow
        }
    }

    /// ASSUMPTION MUSCLE-1 — the row for an activity type this build does not recognise.
    ///
    /// A low, broad whole-body row rather than an empty one: an unrecognised workout is still
    /// training that happened, and zeroing it would silently discard real load.
    static let fallbackRow: [MuscleGroup: Double] = [
        .quads: 0.25, .glutes: 0.25, .core: 0.25, .shoulders: 0.20,
        .hamstrings: 0.20, .upperBack: 0.20, .calves: 0.15, .chest: 0.15
    ]

    /// §5.4 — the involvement row for a logged strength session's movement pattern.
    static func involvement(for pattern: MovementPattern) -> [MuscleGroup: Double] {
        switch pattern {
        case .push:
            return [.chest: 0.70, .shoulders: 0.65, .triceps: 0.60, .core: 0.30,
                    .upperBack: 0.20]

        case .pull:
            return [.lats: 0.70, .upperBack: 0.65, .biceps: 0.60, .forearms: 0.40,
                    .traps: 0.35, .core: 0.25]

        case .squat:
            return [.quads: 0.80, .glutes: 0.65, .hamstrings: 0.40, .adductors: 0.35,
                    .core: 0.35, .lowerBack: 0.30, .calves: 0.20]

        case .hinge:
            return [.hamstrings: 0.75, .glutes: 0.75, .lowerBack: 0.55, .core: 0.35,
                    .traps: 0.30, .forearms: 0.30, .quads: 0.25]

        case .carry:
            return [.forearms: 0.70, .traps: 0.65, .core: 0.55, .shoulders: 0.35,
                    .lowerBack: 0.30, .glutes: 0.25, .calves: 0.20]

        case .isolation(let muscle):
            return [muscle: 1.0]
        }
    }

    /// §5.4 mantığıyla türetilmiş Hyrox istasyon satırları (ASSUMPTION HYROX-2).
    ///
    /// Kaydedilen kuvvet seansları gibi bunlar da manuel bir kayıttan gelir — HealthKit bir
    /// sled push'un ne olduğunu bilmez. Fark şu ki istasyonlar standarttır, o yüzden hareket
    /// kalıbı sormaya gerek yok: istasyonun adı zaten hangi kasları yüklediğini söyler.
    static func involvement(for station: HyroxStation) -> [MuscleGroup: Double] {
        switch station {
        case .skiErg:
            return [.lats: 0.70, .triceps: 0.55, .core: 0.60, .shoulders: 0.45, .upperBack: 0.40]

        case .sledPush:
            return [.quads: 0.80, .glutes: 0.70, .calves: 0.55, .core: 0.45,
                    .shoulders: 0.35, .lowerBack: 0.30]

        case .sledPull:
            return [.lats: 0.75, .upperBack: 0.65, .forearms: 0.60, .biceps: 0.55,
                    .core: 0.45, .hamstrings: 0.40]

        case .burpeeBroadJump:
            return [.quads: 0.70, .core: 0.60, .chest: 0.55, .triceps: 0.50,
                    .shoulders: 0.50, .calves: 0.45, .hamstrings: 0.40]

        case .rowing:
            return [.lats: 0.70, .upperBack: 0.65, .quads: 0.55, .lowerBack: 0.50,
                    .biceps: 0.40, .core: 0.40]

        case .farmersCarry:
            return [.forearms: 0.85, .traps: 0.75, .core: 0.60, .shoulders: 0.40,
                    .lowerBack: 0.35, .glutes: 0.30]

        case .sandbagLunges:
            return [.quads: 0.80, .glutes: 0.75, .hamstrings: 0.55, .core: 0.50,
                    .adductors: 0.45, .lowerBack: 0.40, .traps: 0.30]

        case .wallBalls:
            return [.quads: 0.75, .shoulders: 0.70, .glutes: 0.60, .triceps: 0.50,
                    .core: 0.45, .chest: 0.35]
        }
    }

    /// Whether an activity may contribute muscle impact from HealthKit alone
    /// (ASSUMPTION MUSCLE-2).
    static func contributesMuscleImpact(_ activity: WorkoutActivity) -> Bool {
        !involvement(for: activity).isEmpty
    }
}
