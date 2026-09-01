//
//  FatigueEngine.swift
//  Zenithium
//
//  16-muscle fatigue decay. Spec §5.4 in full.
//
//      sleepModifier = clamp(1.35 − 0.006 · SleepScore, 0.75, 1.35)
//      t½_m          = 24 h · sleepModifier · massClass_m
//      λ_m           = ln(2) / t½_m
//      Fatigue_m(t)  = min(100, Σ impact_{m,i} · e^(−λ_m·(t − t_i)))
//      Readiness_m   = clamp(100 − Fatigue_m, 0, 100)
//
//  Impacts superpose independently per muscle, so two sessions on the same day add rather
//  than replace (§5.6, "multiple workouts").
//

import Foundation

enum FatigueEngine {

    static func project(_ input: FatigueInput) -> [MuscleGroup: MuscleReadiness] {
        let modifier = sleepModifier(forSleepScore: input.sleepScore)
        let window = input.projectionWindow
            ?? Double(EngineConstants.Fatigue.projectionWindowDays) * TimeConversion.secondsPerDay
        let cutoff = input.now.addingTimeInterval(-abs(window))

        // Only sessions inside the window and not in the future contribute
        // (ASSUMPTION MUSCLE-3).
        let sessions = input.sessions.filter { $0.timestamp >= cutoff && $0.timestamp <= input.now }

        var result: [MuscleGroup: MuscleReadiness] = [:]
        result.reserveCapacity(MuscleGroup.allCases.count)

        for muscle in MuscleGroup.allCases {
            let halfLife = halfLifeHours(for: muscle, sleepModifier: modifier)
            let lambda = decayConstant(forHalfLifeHours: halfLife)

            var fatigue: Double = 0
            var contributingCount = 0
            var dominantValue: Double = 0
            var dominantSource: SessionSource?
            var dominantTimestamp: Date?

            for session in sessions {
                let impact = session.impact(on: muscle)
                guard impact > 0 else { continue }
                let elapsedHours = TimeConversion.hours(
                    fromSeconds: input.now.timeIntervalSince(session.timestamp)
                )
                guard elapsedHours >= 0 else { continue }
                let decayed = impact * exp(-lambda * elapsedHours)
                guard decayed.isFinite, decayed > 0 else { continue }

                fatigue += decayed
                if decayed >= EngineConstants.Fatigue.contributionEpsilon {
                    contributingCount += 1
                }
                if decayed > dominantValue {
                    dominantValue = decayed
                    dominantSource = session.source
                    dominantTimestamp = session.timestamp
                }
            }

            let cappedFatigue = min(fatigue, EngineConstants.Fatigue.fatigueCeiling)
            result[muscle] = MuscleReadiness(
                muscle: muscle,
                fatigue: cappedFatigue,
                readiness: MathSupport.clamp(100 - cappedFatigue, 0, 100),
                halfLifeHours: halfLife,
                decayConstant: lambda,
                dominantSource: dominantSource,
                dominantSourceTimestamp: dominantTimestamp,
                contributingSessionCount: contributingCount
            )
        }
        return result
    }

    /// §5.4 — `sleepModifier = clamp(1.35 − 0.006 · SleepScore, 0.75, 1.35)`.
    ///
    /// A better night shortens the half-life, so fatigue clears faster.
    static func sleepModifier(forSleepScore score: Double) -> Double {
        let raw = EngineConstants.Fatigue.sleepModifierIntercept
            - EngineConstants.Fatigue.sleepModifierSlope * score
        return MathSupport.clamp(raw, to: EngineConstants.Fatigue.sleepModifierRange)
    }

    /// §5.4 — `t½_m = 24 h · sleepModifier · massClass_m`.
    static func halfLifeHours(for muscle: MuscleGroup, sleepModifier: Double) -> Double {
        EngineConstants.Fatigue.baseHalfLifeHours
            * sleepModifier
            * EngineConstants.Fatigue.massClassMultiplier(for: muscle.massClass)
    }

    /// §5.4 — `λ = ln(2) / t½`. A non-positive half-life would divide by zero, so it is
    /// floored at one hour, which decays fast rather than instantaneously.
    static func decayConstant(forHalfLifeHours halfLife: Double) -> Double {
        let safeHalfLife = max(halfLife, 1.0)
        return log(2.0) / safeHalfLife
    }

    // MARK: - Session assembly

    /// Builds a session impact from a HealthKit workout (§5.4).
    ///
    /// `sessionLoad = 100 · (1 − e^(−k · sessionTRIMP))`, using the same `k` as daily strain.
    /// Strength activity types produce an empty involvement row, so their impact is zero even
    /// though their TRIMP still counts toward the day (ASSUMPTION MUSCLE-2).
    static func impact(
        forWorkout workout: WorkoutSummary,
        sessionTRIMP: Double
    ) -> MuscleSessionImpact {
        MuscleSessionImpact(
            timestamp: workout.end,
            source: .workout(id: workout.id, activity: workout.activity),
            sessionLoad: StrainEngine.sessionLoad(forTRIMP: sessionTRIMP),
            involvement: MuscleInvolvementMatrix.involvement(for: workout.activity)
        )
    }

    /// Builds a session impact from a logged strength session (§5.4).
    ///
    /// `sessionLoad = clamp(Σ(sets · reps · RPE) / 3.0, 0, 100)`.
    static func impact(
        forStrengthSession id: UUID,
        pattern: MovementPattern,
        performedAt: Date,
        entries: [StrengthEntry]
    ) -> MuscleSessionImpact {
        MuscleSessionImpact(
            timestamp: performedAt,
            source: .strengthLog(id: id, pattern: pattern),
            sessionLoad: StrainEngine.sessionLoad(forVolumeLoad: entries.totalVolumeLoad),
            involvement: MuscleInvolvementMatrix.involvement(for: pattern)
        )
    }

    /// Projected readiness for one muscle at a future instant, for the decay curve in the
    /// muscle detail view. Pure, so the view draws a curve it did not compute.
    static func projectedReadiness(
        for muscle: MuscleGroup,
        from readiness: MuscleReadiness,
        hoursAhead: Double
    ) -> Double {
        guard hoursAhead > 0 else { return readiness.readiness }
        let fatigue = readiness.fatigue * exp(-readiness.decayConstant * hoursAhead)
        return MathSupport.clamp(100 - fatigue, 0, 100)
    }
}
