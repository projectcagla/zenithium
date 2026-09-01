//
//  PlanEngine.swift
//  Zenithium
//
//  Where today sits on the way to a goal. Faz 20.
//
//  Deliberately small. The phase boundaries are counted back from the event date, and the
//  taper's effect on form is computed with the same fitness / fatigue model the load engine
//  already runs — no second theory of training, and nothing that pretends to be a programme.
//

import Foundation

enum PlanEngine {

    /// How long each pre-taper phase runs, as a fraction of the run-up before the taper.
    ///
    /// Base is longest because it is the part that can absorb interruption; sharpening is
    /// shortest because its adaptations arrive fast and fade fast.
    static let basePortion = 0.50
    static let buildPortion = 0.32

    /// Days after an event spent in recovery before planning resumes.
    static let recoveryDays = 7

    // MARK: - Position

    /// Where a day sits relative to an event.
    static func position(
        on day: Date,
        event: GoalEvent,
        planStart: Date? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> PlanPosition {
        let today = calendar.startOfDay(for: day)
        let eventDay = calendar.startOfDay(for: event.date)
        let remaining = calendar.dateComponents([.day], from: today, to: eventDay).day ?? 0

        // The run-up defaults to twelve weeks when the user has not said when they started.
        // Long enough to hold all four phases, short enough that somebody entering a race
        // six weeks out is not told they are still in base.
        let start = planStart.map { calendar.startOfDay(for: $0) }
            ?? calendar.date(byAdding: .day, value: -84, to: eventDay)
            ?? today
        let totalDays = max(1, calendar.dateComponents([.day], from: start, to: eventDay).day ?? 84)

        let phase = self.phase(
            daysRemaining: remaining,
            totalDays: totalDays,
            taperDays: event.kind.taperDays
        )

        return PlanPosition(
            event: event,
            phase: phase,
            daysRemaining: remaining,
            totalWeeks: Int((Double(totalDays) / 7).rounded())
        )
    }

    /// Which phase a number of days out falls in.
    static func phase(daysRemaining: Int, totalDays: Int, taperDays: Int) -> PlanPhase {
        if daysRemaining == 0 { return .event }
        if daysRemaining < 0 {
            return -daysRemaining <= recoveryDays ? .recovery : .base
        }
        if daysRemaining <= taperDays { return .taper }

        let preTaper = max(1, totalDays - taperDays)
        let elapsed = preTaper - (daysRemaining - taperDays)
        let progress = MathSupport.clamp(Double(elapsed) / Double(preTaper), 0, 1)

        if progress < basePortion { return .base }
        if progress < basePortion + buildPortion { return .build }
        return .sharpen
    }

    // MARK: - Taper

    /// What form looks like on event day if load is reduced by `reduction` for the taper.
    ///
    /// Runs the same two-component model as `TrainingLoadEngine`: fitness on a forty-two-day
    /// constant, fatigue on a seven-day one. The whole point of a taper falls out of the
    /// gap between those two — fatigue sheds roughly six times faster, so form rises even
    /// as fitness edges down.
    ///
    /// - Parameter reduction: fraction of usual daily load removed, 0…1.
    static func projectedForm(
        currentFitness: Double,
        currentFatigue: Double,
        usualDailyLoad: Double,
        reduction: Double,
        days: Int
    ) -> FitnessFatigue {
        let constants = EngineConstants.TrainingLoad.self
        let fitnessDecay = exp(-1.0 / constants.fitnessTimeConstantDays)
        let fatigueDecay = exp(-1.0 / constants.fatigueTimeConstantDays)
        let load = usualDailyLoad * (1 - MathSupport.clamp(reduction, 0, 1))

        var fitness = currentFitness
        var fatigue = currentFatigue
        for _ in 0..<max(0, days) {
            fitness = fitness * fitnessDecay + load * (1 - fitnessDecay)
            fatigue = fatigue * fatigueDecay + load * (1 - fatigueDecay)
        }
        return FitnessFatigue(fitness: fitness, fatigue: fatigue, form: fitness - fatigue)
    }

    /// The volume reduction a taper uses.
    ///
    /// ## Why this is a constant and not an optimisation
    ///
    /// The obvious move is to search reductions and return whichever puts projected form
    /// highest. That was written, measured, and thrown away: over a two-week horizon the
    /// answer is always the top of the range, for any weighting of fatigue against fitness.
    /// The reason is structural — fitness decays on a forty-two-day constant and fatigue on
    /// a seven-day one, so cutting load always sheds far more fatigue than fitness, and the
    /// two-component model has no detraining term to push back. A "search" whose answer is
    /// its own upper bound is a constant wearing a costume.
    ///
    /// So the number comes from the literature instead. Meta-analyses of taper studies put
    /// the productive range at a 40–60% reduction in volume held over one to two weeks, with
    /// **intensity maintained** — which is the part people get wrong, and the part the model
    /// cannot tell them because it has no intensity term at all.
    static let taperVolumeReduction = 0.50

    /// What the recommended taper does to form, for the user to see rather than to derive.
    ///
    /// The model illustrates the recommendation; it does not produce it. That distinction is
    /// the honest one, and it is why this returns a projection instead of a decision.
    static func taperProjection(
        currentFitness: Double,
        currentFatigue: Double,
        usualDailyLoad: Double,
        days: Int
    ) -> FitnessFatigue {
        projectedForm(
            currentFitness: currentFitness,
            currentFatigue: currentFatigue,
            usualDailyLoad: usualDailyLoad,
            reduction: taperVolumeReduction,
            days: days
        )
    }

    // MARK: - Copy

    static func summary(for position: PlanPosition) -> String {
        var sentence = position.summary
        if !position.isPast {
            sentence += " \(position.phase.purpose)"
        }
        return sentence
    }

    /// The taper sentence, when the plan is in one.
    static func taperSummary(for position: PlanPosition, projection: FitnessFatigue?) -> String? {
        guard position.phase == .taper else { return nil }
        var sentence = "Hacmi yaklaşık \(ZenithiumFormat.percentTR(taperVolumeReduction)) düşür, şiddeti koru — literatürde en tutarlı sonuç veren aralık bu."
        if let projection {
            sentence += " Bu gidişle etkinlik günü formun \(ZenithiumFormat.signed(projection.form, digits: 1)) civarında olur."
        }
        return sentence
    }
}
