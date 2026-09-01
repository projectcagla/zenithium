//
//  FatigueIO.swift
//  Zenithium
//
//  Muscle fatigue engine input and output. Spec §5.4 in full.
//  ASSUMPTION MUSCLE-2 (strength types carry no HealthKit muscle impact), MUSCLE-3
//  (14-day projection window), RPE-1 (per-exercise RPE).
//

import Foundation

/// Where a session's load came from, so the detail view can attribute fatigue.
enum SessionSource: Sendable, Equatable, Hashable {

    /// A HealthKit workout, identified by its sample UUID.
    case workout(id: UUID, activity: WorkoutActivity)

    /// A manually logged strength session.
    case strengthLog(id: UUID, pattern: MovementPattern)

    /// Bir hibrit seansın tek bir istasyonu. Her istasyon kendi yükünü taşır, çünkü
    /// sled push ile wall balls aynı kasları yormaz.
    case hybridStation(id: UUID, station: HyroxStation)

    var displayName: String {
        switch self {
        case .workout(_, let activity): return activity.displayName
        case .strengthLog(_, let pattern): return pattern.displayName
        case .hybridStation(_, let station): return station.displayName
        }
    }

    var symbolName: String {
        switch self {
        case .workout(_, let activity): return activity.symbolName
        case .strengthLog(_, let pattern): return pattern.symbolName
        case .hybridStation(_, let station): return station.symbolName
        }
    }

    var identifier: UUID {
        switch self {
        case .workout(let id, _): return id
        case .strengthLog(let id, _): return id
        case .hybridStation(let id, _): return id
        }
    }
}

/// One session's contribution, already reduced to a load and an involvement row (§5.4).
///
/// The engine never sees a workout or a log — only this. That keeps it pure and lets the
/// same code path serve cardio and logged strength.
struct MuscleSessionImpact: Sendable, Equatable {

    /// When the session ended. Decay is measured from here.
    let timestamp: Date

    /// Where it came from.
    let source: SessionSource

    /// `sessionLoad ∈ [0, 100]` (§5.4).
    let sessionLoad: Double

    /// `involvement_m ∈ [0, 1]` per muscle. Muscles absent from the dictionary are not
    /// involved — which is different from being involved at zero only in that it keeps the
    /// dictionary small.
    let involvement: [MuscleGroup: Double]

    init(
        timestamp: Date,
        source: SessionSource,
        sessionLoad: Double,
        involvement: [MuscleGroup: Double]
    ) {
        self.timestamp = timestamp
        self.source = source
        self.sessionLoad = sessionLoad
        self.involvement = involvement
    }

    /// `impact_m = sessionLoad · involvement_m` (§5.4).
    func impact(on muscle: MuscleGroup) -> Double {
        sessionLoad * (involvement[muscle] ?? 0)
    }
}

/// Everything the fatigue engine needs.
struct FatigueInput: Sendable, Equatable {

    /// Sessions inside the projection window, in any order.
    let sessions: [MuscleSessionImpact]

    /// Last night's sleep score, 0…100, driving `sleepModifier` (§5.4). When sleep could not
    /// be scored, callers pass the neutral value that yields a 1.0× modifier so fatigue does
    /// not silently accelerate or stall.
    let sleepScore: Double

    /// The instant to project fatigue to. Engines never call `Date()` (§2.7).
    let now: Date

    /// How far back sessions are considered. `nil` uses the engine default of 14 days
    /// (ASSUMPTION MUSCLE-3).
    let projectionWindow: TimeInterval?

    init(
        sessions: [MuscleSessionImpact],
        sleepScore: Double,
        now: Date,
        projectionWindow: TimeInterval?
    ) {
        self.sessions = sessions
        self.sleepScore = sleepScore
        self.now = now
        self.projectionWindow = projectionWindow
    }
}

/// One muscle's projected state.
struct MuscleReadiness: Sendable, Equatable, Hashable, Identifiable {

    let muscle: MuscleGroup

    /// `Fatigue_m(t) = min(100, Σ impact · e^(−λ·Δt))` (§5.4).
    let fatigue: Double

    /// `Readiness_m(t) = clamp(100 − Fatigue_m(t), 0, 100)` (§5.4).
    let readiness: Double

    /// `t½_m = 24 h · sleepModifier · massClass_m` (§5.4).
    let halfLifeHours: Double

    /// `λ_m = ln(2) / t½_m` (§5.4).
    let decayConstant: Double

    /// The session contributing the largest remaining fatigue, when any does.
    let dominantSource: SessionSource?

    /// When that session was.
    let dominantSourceTimestamp: Date?

    /// How many sessions still contribute a non-negligible amount.
    let contributingSessionCount: Int

    init(
        muscle: MuscleGroup,
        fatigue: Double,
        readiness: Double,
        halfLifeHours: Double,
        decayConstant: Double,
        dominantSource: SessionSource?,
        dominantSourceTimestamp: Date?,
        contributingSessionCount: Int
    ) {
        self.muscle = muscle
        self.fatigue = fatigue
        self.readiness = readiness
        self.halfLifeHours = halfLifeHours
        self.decayConstant = decayConstant
        self.dominantSource = dominantSource
        self.dominantSourceTimestamp = dominantSourceTimestamp
        self.contributingSessionCount = contributingSessionCount
    }

    var id: MuscleGroup { muscle }

    /// A training-directive band for the map's fill and its text label.
    ///
    /// §12: this describes what to train, never a health status.
    var trainingLabel: String {
        switch readiness {
        case ..<34: return "Toparlanıyor"
        case ..<67: return "Orta"
        default: return "Hazır"
        }
    }

    /// The band the readiness maps onto, reusing the recovery palette so one colour language
    /// runs through the whole app.
    var band: RecoveryBand {
        RecoveryBand.band(forScore: readiness)
    }

    /// Hours until readiness reaches `target`, or `nil` when it is already there or when the
    /// decay constant is degenerate.
    func hoursUntilReadiness(_ target: Double) -> Double? {
        guard readiness < target, target < 100, decayConstant > 0 else { return nil }
        let currentFatigue = 100 - readiness
        let targetFatigue = 100 - target
        guard currentFatigue > 0, targetFatigue > 0, currentFatigue > targetFatigue else { return nil }
        return log(currentFatigue / targetFatigue) / decayConstant
    }
}
