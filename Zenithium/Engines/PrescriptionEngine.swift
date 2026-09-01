//
//  PrescriptionEngine.swift
//  Zenithium
//
//  Where every engine's answer meets. Faz 19.
//
//  The decision runs in one direction and each step narrows the last:
//
//  1. **Recovery** sets the intent — push, hold, or back off.
//  2. **The load ratio** adjusts it. A green morning at the top of a spike is not a licence
//     to add more; a yellow morning after two easy weeks often is.
//  3. **Muscle readiness** removes options. There is no point prescribing lower-body work
//     to legs at 40%.
//  4. **The lens** turns what is left into a session somebody recognises. The same inputs
//     become "55 minutes easy" for a runner and "40 dakika tempolu yürüyüş" for someone
//     tracking health.
//  5. **The strain ceiling** trims the duration, using `StrainEngine`'s integral run
//     backwards so the forecast is on the same scale as tonight's number.
//
//  Nothing here is graded on being right — it is graded on being *arguable*. Every
//  prescription carries the reasons that produced it, and the alternatives it was chosen
//  over, because a suggestion the user cannot interrogate is a horoscope.
//

import Foundation

enum PrescriptionEngine {

    /// How much of the remaining daily ceiling one prescribed session may claim.
    ///
    /// Two thirds. The ceiling is a whole-day figure and life adds load after training —
    /// a commute, a stressful afternoon — so handing all of it to one session would put
    /// most users over by bedtime.
    static let sessionShareOfCeiling = 0.66

    /// Below this readiness a muscle group is treated as unavailable.
    static let muscleConstraintThreshold: Double = 55

    /// Ratio above which the engine stops adding load regardless of how good the morning was.
    static let spikeGuardRatio = 1.45

    // MARK: - Entry point

    static func prescribe(
        recovery: RecoveryOutput,
        lens: TrainingLens,
        load: TrainingLoadOutput?,
        muscles: [MuscleReadiness],
        strainSoFar: Double,
        biologicalSex: BiologicalSexValue,
        criticalSpeed: CriticalSpeedModel?,
        circadian: CircadianArc?,
        cycle: CycleContext? = nil
    ) -> Prescription? {
        guard lens.expectsPrescription || lens == .health else { return nil }
        guard recovery.availability.isScored, let score = recovery.score else { return nil }

        var rationale: [String] = []
        let band = recovery.band ?? .yellow

        var intent = Intent(band: band)
        rationale.append("Toparlanma \(ZenithiumFormat.score(score)) — \(band.displayName.lowercased()) bant.")

        // Step 2 — the ratio can only ever move the intent *down*. A good morning is not
        // evidence that a spike was fine; it is evidence that the body handled yesterday.
        if let load, let ratio = load.ratio {
            if ratio >= spikeGuardRatio {
                intent = intent.softened()
                rationale.append("Yük oranın \(ZenithiumFormat.metric(ratio, digits: 2)) — son haftan son ayının belirgin üstünde, bugün eklemiyorum.")
            } else if ratio < 0.80, band != .red {
                intent = intent.raised()
                rationale.append("Yük oranın \(ZenithiumFormat.metric(ratio, digits: 2)) — son haftan hafif geçmiş, alan var.")
            }
        }

        let constrained = muscles
            .filter { $0.readiness < muscleConstraintThreshold }
            .sorted { $0.readiness < $1.readiness }
        if !constrained.isEmpty {
            let names = constrained.prefix(3).map { $0.muscle.displayName.lowercased() }
            rationale.append("\(names.joined(separator: ", ")) hâlâ toparlanıyor.")
        }
        let constrainedGroups = Set(constrained.map(\.muscle))

        let candidates = sessionKinds(for: lens, intent: intent, constrained: constrainedGroups)
        guard !candidates.isEmpty else { return nil }

        let ceiling = recovery.targetStrainCeiling
        let sessions = candidates.prefix(3).enumerated().map { index, kind in
            session(
                kind: kind,
                intent: intent,
                ceiling: ceiling,
                strainSoFar: strainSoFar,
                biologicalSex: biologicalSex,
                criticalSpeed: criticalSpeed,
                isPrimary: index == 0
            )
        }
        guard let primary = sessions.first else { return nil }

        if let ceiling {
            rationale.append("Bugünün tavanı \(ZenithiumFormat.strain(ceiling)); bu seans \(ZenithiumFormat.strain(primary.forecastStrain)) civarı.")
        }

        let window = trainingWindow(from: circadian)
        if window != nil {
            rationale.append("Sirkadiyen eğrine göre günün en keskin aralığı bu.")
        }

        // Cycle context, and only context. See `cycleContextLine`.
        if let line = cycleContextLine(cycle: cycle, band: band) {
            rationale.append(line)
        }

        return Prescription(
            primary: primary,
            alternatives: Array(sessions.dropFirst()),
            rationale: rationale,
            suggestedWindow: window,
            ceiling: ceiling,
            projectedRatio: load.flatMap {
                TrainingLoadEngine.projectedRatio(after: primary.forecastStrain, from: $0)
            },
            constrainedMuscles: constrained.map(\.muscle),
            cyclePhase: cycle?.estimate
        )
    }

    // MARK: - Cycle

    /// How far from the phase mean still counts as an ordinary day in that phase.
    ///
    /// Ten per cent of the phase's own mean. Wide, because the baseline is a mean without a
    /// variance and a tight band would claim precision the data does not have.
    static let phaseTypicalFraction: Double = 0.10

    /// What the cycle adds to the rationale — and nothing else.
    ///
    /// ## Why the phase does not change the session
    ///
    /// The obvious implementation is to soften the luteal phase. It is also wrong. The
    /// largest review of the question (McNulty et al., 2020) found the effect of cycle phase
    /// on performance to be trivial on average and enormously variable between people —
    /// which is not a foundation for telling somebody to train less on a schedule. §1 also
    /// rules it out directly: an app that quietly prescribes an easier month every month is
    /// a restriction prompt with a calendar attached.
    ///
    /// ## What the phase genuinely explains
    ///
    /// The *signals* shift, and that is well established: resting heart rate typically sits
    /// two to five beats higher in the luteal phase and heart-rate variability lower. A
    /// recovery score built from those inputs therefore reads low for a reason that is
    /// ordinary physiology rather than a bad night. Somebody seeing an amber morning every
    /// luteal phase, with no explanation, reasonably concludes they are under-recovered.
    ///
    /// So this says what the reading means, on the days when the phase explains it. The
    /// intent, the session and the ceiling are untouched — a test asserts that.
    static func cycleContextLine(cycle: CycleContext?, band: RecoveryBand) -> String? {
        guard let cycle, cycle.estimate.isConfident else { return nil }
        let phase = cycle.estimate.phase

        // Only worth saying when the score is the thing being explained.
        guard band != .green else { return nil }

        guard let deviation = cycle.deviationFromPhaseMean else {
            // No phase history yet, so nothing can be said about whether today is typical.
            // The phase itself is still worth naming, without a claim attached.
            return "\(cycle.estimate.qualifier). Bu fazın kendi ortalaman için henüz yeterli geçmiş yok."
        }

        guard abs(deviation) <= phaseTypicalFraction else {
            // Today is genuinely away from where this person normally sits in this phase, so
            // the phase does not explain it and pretending otherwise would explain away a
            // real signal.
            return "\(cycle.estimate.qualifier). HRV'n bu fazdaki kendi ortalamandan belirgin farklı, yani bunu faz açıklamıyor."
        }

        return "\(cycle.estimate.qualifier). HRV'n \(phase.baselineGroup.displayName.lowercased()) ortalamanın civarında — bu faz için olağan bir sabah."
    }

    // MARK: - Intent

    /// How hard today should be, before the lens turns it into a session.
    enum Intent: Int, Sendable, Comparable {
        case recover = 0
        case easy = 1
        case moderate = 2
        case hard = 3

        init(band: RecoveryBand) {
            switch band {
            case .red: self = .recover
            case .yellow: self = .moderate
            case .green: self = .hard
            }
        }

        func softened() -> Intent { Intent(rawValue: max(0, rawValue - 1)) ?? .recover }
        func raised() -> Intent { Intent(rawValue: min(3, rawValue + 1)) ?? .hard }

        static func < (lhs: Intent, rhs: Intent) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // MARK: - Lens

    /// The sessions a lens offers at an intent, strongest candidate first.
    ///
    /// The lens is the only place the app decides what a session *looks like*. Everything
    /// upstream is discipline-agnostic, which is what lets a Hyrox athlete and someone who
    /// has never trained share four engines and still get answers in their own vocabulary.
    static func sessionKinds(
        for lens: TrainingLens,
        intent: Intent,
        constrained: Set<MuscleGroup>
    ) -> [SessionKind] {
        let legsTired = constrained.contains(.quads) || constrained.contains(.hamstrings)
            || constrained.contains(.calves) || constrained.contains(.glutes)

        switch lens {
        case .endurance:
            switch intent {
            case .recover: return [.rest, .easyMovement]
            case .easy: return [.easyAerobic, .easyMovement, .rest]
            case .moderate: return legsTired
                ? [.easyAerobic, .steadyAerobic, .easyMovement]
                : [.steadyAerobic, .easyAerobic, .tempo]
            case .hard: return legsTired
                ? [.steadyAerobic, .easyAerobic, .tempo]
                : [.intervals, .tempo, .steadyAerobic]
            }

        case .hybrid:
            switch intent {
            case .recover: return [.rest, .easyMovement]
            case .easy: return [.easyAerobic, .easyMovement, .rest]
            case .moderate: return legsTired
                ? [.easyAerobic, .strengthUpper, .steadyAerobic]
                : [.compromisedRunning, .steadyAerobic, .strengthUpper]
            case .hard: return legsTired
                ? [.strengthUpper, .steadyAerobic, .easyAerobic]
                : [.stationWork, .compromisedRunning, .intervals]
            }

        case .strength:
            switch intent {
            case .recover: return [.rest, .easyMovement]
            case .easy: return [.easyMovement, .strengthUpper, .rest]
            case .moderate: return legsTired
                ? [.strengthUpper, .easyAerobic, .easyMovement]
                : [.strengthFull, .strengthUpper, .easyAerobic]
            case .hard: return legsTired
                ? [.strengthUpper, .strengthFull, .easyAerobic]
                : [.strengthLower, .strengthFull, .strengthUpper]
            }

        case .health:
            // No ceiling, no intervals, no "push". The question this person is answering is
            // whether the day held some movement, not how hard it was.
            switch intent {
            case .recover: return [.rest, .easyMovement]
            case .easy, .moderate: return [.walk, .easyMovement]
            case .hard: return [.walk, .easyAerobic]
            }
        }
    }

    // MARK: - Session

    /// Turn a kind into a duration and a forecast.
    static func session(
        kind: SessionKind,
        intent: Intent,
        ceiling: Double?,
        strainSoFar: Double,
        biologicalSex: BiologicalSexValue,
        criticalSpeed: CriticalSpeedModel?,
        isPrimary: Bool
    ) -> PrescribedSession {
        guard kind != .rest else {
            return PrescribedSession(
                kind: .rest,
                minutes: 0,
                forecastStrain: 0,
                paceBand: nil,
                isPrimary: isPrimary
            )
        }

        let intensity = MathSupport.mean([kind.reserveFraction.lowerBound, kind.reserveFraction.upperBound]) ?? 0.5
        var minutes = Double(defaultMinutes(for: kind, intent: intent))

        // Trim to fit what is left of the day's ceiling.
        if let ceiling, ceiling > strainSoFar,
           let remainingTRIMP = StrainEngine.trimp(forStrain: ceiling - strainSoFar),
           let allowed = StrainEngine.minutes(
               forTRIMP: remainingTRIMP * sessionShareOfCeiling,
               reserveFraction: intensity,
               biologicalSex: biologicalSex
           ) {
            minutes = min(minutes, allowed)
        }

        // Round to five minutes. Nobody trains to the minute, and a prescription that says
        // "43 dakika" claims a precision the model does not have.
        let rounded = max(10, (minutes / 5).rounded() * 5)
        let trimp = StrainEngine.trimp(
            forMinutes: rounded,
            reserveFraction: intensity,
            biologicalSex: biologicalSex
        )

        return PrescribedSession(
            kind: kind,
            minutes: Int(rounded),
            forecastStrain: StrainEngine.strain(forTRIMP: trimp),
            paceBand: paceBand(for: kind, model: criticalSpeed),
            isPrimary: isPrimary
        )
    }

    /// The duration a session normally runs, before the ceiling trims it.
    static func defaultMinutes(for kind: SessionKind, intent: Intent) -> Int {
        switch kind {
        case .rest: return 0
        case .easyMovement: return 25
        case .walk: return 40
        case .easyAerobic: return intent >= .moderate ? 50 : 35
        case .steadyAerobic: return intent >= .hard ? 70 : 55
        case .tempo: return 40
        case .intervals: return 45
        case .strengthUpper, .strengthLower: return 50
        case .strengthFull: return 65
        case .compromisedRunning: return 50
        case .stationWork: return 55
        }
    }

    /// The pace band to hold, when the session has one and the model exists.
    static func paceBand(for kind: SessionKind, model: CriticalSpeedModel?) -> PaceZoneBand? {
        guard let model else { return nil }
        let zone: PaceZone?
        switch kind {
        case .easyAerobic: zone = .easy
        case .steadyAerobic: zone = .steady
        case .tempo: zone = .threshold
        case .intervals: zone = .interval
        case .compromisedRunning: zone = .steady
        default: zone = nil
        }
        guard let zone else { return nil }
        return EnduranceEngine.paceZones(from: model).first { $0.zone == zone }
    }

    // MARK: - Timing

    /// The stretch of the day the circadian curve puts highest.
    ///
    /// Taken from the marker set rather than by scanning the samples: the engine already
    /// names the peaks, and re-deriving them here would give the two screens two answers.
    static func trainingWindow(from arc: CircadianArc?) -> DateInterval? {
        guard let arc else { return nil }
        guard let peak = arc.marker(for: .morningPeak) ?? arc.marker(for: .secondaryPeak) else {
            return nil
        }
        return DateInterval(
            start: peak.date.addingTimeInterval(-45 * 60),
            end: peak.date.addingTimeInterval(45 * 60)
        )
    }
}
