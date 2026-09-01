//
//  MovementPattern.swift
//  Zenithium
//
//  Strength movement patterns. Spec §5.4: strength sessions require a manual logger
//  (movement pattern → muscle preset: Push / Pull / Squat / Hinge / Carry / Isolation-by-muscle).
//  Zenithium never fabricates strength muscle data from HealthKit (ASSUMPTION MUSCLE-2).
//

import Foundation

/// The movement pattern a logged strength session followed.
///
/// The pattern selects an involvement row; the row itself lives in
/// `Engines/MuscleInvolvementMatrix.swift` so that the numbers stay in the engine layer.
enum MovementPattern: Sendable, Equatable, Hashable, Codable {
    case push
    case pull
    case squat
    case hinge
    case carry
    case isolation(MuscleGroup)

    /// The patterns offered without a muscle picker.
    static let compoundCases: [MovementPattern] = [.push, .pull, .squat, .hinge, .carry]

    /// The stable string persisted on `StrengthSessionLog`.
    var storageKey: String {
        switch self {
        case .push: return "push"
        case .pull: return "pull"
        case .squat: return "squat"
        case .hinge: return "hinge"
        case .carry: return "carry"
        case .isolation(let muscle): return "isolation:\(muscle.rawValue)"
        }
    }

    /// The inverse of `storageKey`.
    static func pattern(forStorageKey key: String) -> MovementPattern? {
        switch key {
        case "push": return .push
        case "pull": return .pull
        case "squat": return .squat
        case "hinge": return .hinge
        case "carry": return .carry
        default:
            let prefix = "isolation:"
            guard key.hasPrefix(prefix) else { return nil }
            let raw = String(key.dropFirst(prefix.count))
            guard let muscle = MuscleGroup(rawValue: raw) else { return nil }
            return .isolation(muscle)
        }
    }

    var displayName: String {
        switch self {
        case .push: return "İtme"
        case .pull: return "Çekme"
        case .squat: return "Squat"
        case .hinge: return "Kalça menteşesi"
        case .carry: return "Taşıma"
        case .isolation(let muscle): return muscle.displayName
        }
    }

    var subtitle: String {
        switch self {
        case .push: return "Bench, omuz press, dips"
        case .pull: return "Row, barfiks, curl"
        case .squat: return "Back squat, front squat, lunge"
        case .hinge: return "Deadlift, RDL, hip thrust"
        case .carry: return "Farmer's walk, suitcase carry"
        case .isolation: return "Tek kas çalışması"
        }
    }

    var symbolName: String {
        switch self {
        case .push: return "arrow.up.forward"
        case .pull: return "arrow.down.backward"
        case .squat: return "arrow.down.to.line"
        case .hinge: return "arrow.turn.up.forward.iphone"
        case .carry: return "bag.fill"
        case .isolation: return "scope"
        }
    }

    /// The muscle a session isolates, when it isolates one.
    var isolatedMuscle: MuscleGroup? {
        switch self {
        case .isolation(let muscle): return muscle
        case .push, .pull, .squat, .hinge, .carry: return nil
        }
    }
}
