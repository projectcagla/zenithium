//
//  MuscleGroup.swift
//  Zenithium
//
//  The 16 muscle groups in fixed enum order. Spec §5.4.
//  The declaration order is load-bearing: `MuscleFatigueSnapshot` persists fatigue as a
//  positional `[Double]`, so cases must never be reordered without a schema migration.
//

import Foundation

/// How quickly a group recovers, as a multiplier on the 24 h base half-life (§5.4).
enum MassClass: String, Sendable, Codable, CaseIterable, Hashable {
    case large
    case medium
    case small

    var displayName: String {
        switch self {
        case .large: return "Büyük"
        case .medium: return "Orta"
        case .small: return "Küçük"
        }
    }
}

/// The 16 tracked groups, in the fixed order given in §5.4.
enum MuscleGroup: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case chest
    case upperBack
    case lats
    case shoulders
    case biceps
    case triceps
    case forearms
    case core
    case quads
    case hamstrings
    case glutes
    case calves
    case adductors
    case traps
    case lowerBack
    case neck

    var id: String { rawValue }

    /// Position in the fixed order — the index used by positional persistence.
    var storageIndex: Int {
        switch self {
        case .chest: return 0
        case .upperBack: return 1
        case .lats: return 2
        case .shoulders: return 3
        case .biceps: return 4
        case .triceps: return 5
        case .forearms: return 6
        case .core: return 7
        case .quads: return 8
        case .hamstrings: return 9
        case .glutes: return 10
        case .calves: return 11
        case .adductors: return 12
        case .traps: return 13
        case .lowerBack: return 14
        case .neck: return 15
        }
    }

    /// The inverse of `storageIndex`.
    static func group(atStorageIndex index: Int) -> MuscleGroup? {
        MuscleGroup.allCases.first { $0.storageIndex == index }
    }

    /// Spec §5.4 mass classes.
    ///
    /// large — Quads, Hamstrings, Glutes, Lats, Upper Back, Chest, Lower Back
    /// medium — Shoulders, Triceps, Core/Abs, Adductors, Traps
    /// small — Biceps, Forearms, Calves, Neck
    var massClass: MassClass {
        switch self {
        case .quads, .hamstrings, .glutes, .lats, .upperBack, .chest, .lowerBack:
            return .large
        case .shoulders, .triceps, .core, .adductors, .traps:
            return .medium
        case .biceps, .forearms, .calves, .neck:
            return .small
        }
    }

    var displayName: String {
        switch self {
        case .chest: return "Göğüs"
        case .upperBack: return "Üst sırt"
        case .lats: return "Latlar"
        case .shoulders: return "Omuzlar"
        case .biceps: return "Biseps"
        case .triceps: return "Triseps"
        case .forearms: return "Ön kollar"
        case .core: return "Karın / merkez"
        case .quads: return "Kuadriseps"
        case .hamstrings: return "Arka bacak"
        case .glutes: return "Kalça"
        case .calves: return "Baldırlar"
        case .adductors: return "İç bacak"
        case .traps: return "Trapez"
        case .lowerBack: return "Bel"
        case .neck: return "Boyun"
        }
    }

    /// Which side of the body map the group is drawn on.
    var bodySide: BodySide {
        switch self {
        case .chest, .biceps, .forearms, .core, .quads, .adductors, .shoulders, .neck:
            return .anterior
        case .upperBack, .lats, .triceps, .hamstrings, .glutes, .calves, .traps, .lowerBack:
            return .posterior
        }
    }
}

/// Which view of the body map a group belongs to.
enum BodySide: String, Sendable, Codable, CaseIterable, Hashable {
    case anterior
    case posterior

    var displayName: String {
        switch self {
        case .anterior: return "Ön"
        case .posterior: return "Arka"
        }
    }
}
