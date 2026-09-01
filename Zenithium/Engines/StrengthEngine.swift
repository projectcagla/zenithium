//
//  StrengthEngine.swift
//  Zenithium
//
//  The strength lens's mathematics. Faz 17.
//
//  Three questions a lifter actually asks: is the bar going up, is each muscle getting
//  enough work, and is anything lopsided. All three run off the sessions the logger already
//  records, plus the sixteen-muscle involvement matrix the fatigue engine already uses — so
//  this engine adds arithmetic, not a second source of truth about anatomy.
//

import Foundation

enum StrengthEngine {

    /// Below this share, a movement pattern is not really training that muscle, and counting
    /// it as a working set would inflate every number on the screen.
    static let setCountingThreshold = 0.25

    /// How far back the volume window reaches.
    static let volumeWindowDays = 7

    /// How far back one-rep-max history is searched for a previous best.
    static let progressionWindowDays = 180

    // MARK: - One-rep maximum

    /// Estimate a one-rep maximum from a working set.
    ///
    /// The mean of Epley and Brzycki. They disagree in opposite directions — Epley runs high
    /// at low reps and Brzycki runs low at high ones — so averaging them is closer across
    /// the useful range than either alone, and cheaper than fitting a third formula nobody
    /// would be able to check.
    ///
    ///     Epley:   1RM = w · (1 + reps/30)
    ///     Brzycki: 1RM = w · 36 / (37 − reps)
    ///
    /// Returns `nil` above 36 reps, where Brzycki's denominator collapses, and for
    /// non-positive weight.
    static func estimateOneRepMax(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps >= 1, reps < 36 else { return nil }
        if reps == 1 { return weight }
        let epley = weight * (1 + Double(reps) / 30)
        let brzycki = weight * 36 / (37 - Double(reps))
        return (epley + brzycki) / 2
    }

    /// One record of a scored set.
    private struct ScoredSet {
        let estimate: Double
        let weight: Double
        let reps: Int
        let date: Date
        /// The spelling the user typed, kept so the screen shows their name and not a
        /// normalised key.
        let displayName: String
    }

    /// The best estimate for every exercise that carried a weight, heaviest first.
    static func oneRepMaxes(
        from sessions: [StrengthSessionSnapshot],
        now: Date = Date()
    ) -> [OneRepMaxEstimate] {
        let cutoff = now.addingTimeInterval(-Double(progressionWindowDays) * 86_400)

        var byExercise: [String: [ScoredSet]] = [:]
        for session in sessions where session.performedAt >= cutoff {
            for entry in session.entries {
                guard let weight = entry.weightKilograms,
                      let estimate = estimateOneRepMax(weight: weight, reps: entry.reps) else { continue }
                let key = normalizedName(entry.exerciseName)
                guard !key.isEmpty else { continue }
                byExercise[key, default: []].append(
                    ScoredSet(
                        estimate: estimate,
                        weight: weight,
                        reps: entry.reps,
                        date: session.performedAt,
                        displayName: entry.exerciseName
                    )
                )
            }
        }

        return byExercise.compactMap { _, records -> OneRepMaxEstimate? in
            guard let best = records.max(by: { $0.estimate < $1.estimate }) else { return nil }

            // The previous best is the best of everything strictly *earlier* than the best
            // set's day — not the second-highest overall, which could be another set from the
            // same session and would report progress against yourself an hour ago.
            let previous = records
                .filter { $0.date < best.date }
                .map(\.estimate)
                .max()

            return OneRepMaxEstimate(
                exerciseName: best.displayName,
                estimate: best.estimate,
                weight: best.weight,
                reps: best.reps,
                date: best.date,
                previousEstimate: previous
            )
        }
        .sorted { $0.estimate > $1.estimate }
    }

    /// Fold spelling differences together so "Bench Press" and "bench press" are one exercise.
    static func normalizedName(_ name: String) -> String {
        BiomarkerCatalog.normalize(name)
    }

    // MARK: - Volume

    /// Effective weekly sets per muscle group.
    ///
    /// A set is not one set for every muscle it touches. A back squat is a full set for the
    /// quadriceps and a fraction of one for the calves, so each set is weighted by the
    /// involvement matrix — the same table the fatigue engine uses, which keeps the two
    /// screens from disagreeing about what a squat trains.
    static func weeklyVolume(
        from sessions: [StrengthSessionSnapshot],
        now: Date = Date()
    ) -> [WeeklyVolume] {
        let cutoff = now.addingTimeInterval(-Double(volumeWindowDays) * 86_400)
        var totals: [MuscleGroup: Double] = [:]

        for session in sessions where session.performedAt >= cutoff {
            let involvement = MuscleInvolvementMatrix.involvement(for: session.pattern)
            let sets = session.entries.reduce(0) { $0 + Double($1.sets) }
            for (muscle, share) in involvement where share >= setCountingThreshold {
                totals[muscle, default: 0] += sets * share
            }
        }

        return MuscleGroup.allCases
            .compactMap { muscle in
                guard let sets = totals[muscle], sets > 0 else { return nil }
                return WeeklyVolume(muscle: muscle, sets: sets)
            }
            .sorted { $0.sets > $1.sets }
    }

    // MARK: - Balance

    /// Push versus pull, and front chain versus back.
    static func balance(from sessions: [StrengthSessionSnapshot], now: Date = Date()) -> StrengthBalance {
        let cutoff = now.addingTimeInterval(-Double(volumeWindowDays) * 86_400)

        var push = 0.0
        var pull = 0.0
        for session in sessions where session.performedAt >= cutoff {
            let sets = session.entries.reduce(0) { $0 + Double($1.sets) }
            switch session.pattern {
            case .push: push += sets
            case .pull: pull += sets
            case .squat, .hinge, .carry, .isolation: break
            }
        }

        let volume = weeklyVolume(from: sessions, now: now)
        let anterior = volume.filter { Self.anteriorGroups.contains($0.muscle) }.reduce(0) { $0 + $1.sets }
        let posterior = volume.filter { Self.posteriorGroups.contains($0.muscle) }.reduce(0) { $0 + $1.sets }

        return StrengthBalance(
            pushSets: push,
            pullSets: pull,
            anteriorSets: anterior,
            posteriorSets: posterior
        )
    }

    /// The front of the body, for the chain ratio.
    static let anteriorGroups: Set<MuscleGroup> = [.chest, .quads, .biceps, .core, .shoulders]

    /// The back of the body.
    static let posteriorGroups: Set<MuscleGroup> = [.upperBack, .lats, .hamstrings, .glutes, .lowerBack, .traps, .triceps]

    // MARK: - Deload

    /// Whether several signals agree that the week is asking for a lighter one.
    /// - Parameter muscleReadiness: readiness values, 0…100. Taken as plain numbers rather
    ///   than as `MuscleReadiness` so the caller can pass whatever it has — the cached
    ///   snapshot stores values, not projections.
    static func deloadSignal(
        volume: [WeeklyVolume],
        recoveryScores: [Double],
        muscleReadiness: [Double],
        loadRatio: Double?
    ) -> DeloadSignal {
        var reasons: [DeloadSignal.Reason] = []

        // Three or more groups above the high band.
        if volume.filter({ $0.band == .high }).count >= 3 {
            reasons.append(.highVolume)
        }

        // Recovery has sat below the yellow boundary for most of the last week.
        let low = recoveryScores.filter { $0 <= RecoveryBand.yellowUpperBound }
        if recoveryScores.count >= 5, Double(low.count) / Double(recoveryScores.count) >= 0.6 {
            reasons.append(.lowRecovery)
        }

        // Three or more groups still under half recovered.
        if muscleReadiness.filter({ $0 < 50 }).count >= 3 {
            reasons.append(.persistentMuscleFatigue)
        }

        if let loadRatio, loadRatio >= 1.30 {
            reasons.append(.risingLoadRatio)
        }

        return DeloadSignal(reasons: reasons)
    }

    // MARK: - Copy

    static func progressionSummary(for estimate: OneRepMaxEstimate) -> String {
        let value = ZenithiumFormat.metric(estimate.estimate, digits: 1)
        guard let change = estimate.change, abs(change) >= 0.01 else {
            return "\(estimate.exerciseName): tahmini 1TM \(value) kg."
        }
        let direction = change > 0 ? "yukarıda" : "aşağıda"
        return "\(estimate.exerciseName): tahmini 1TM \(value) kg — önceki en iyisinin \(ZenithiumFormat.percentTR(change)) \(direction)."
    }
}
