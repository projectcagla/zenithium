//
//  PrescriptionIO.swift
//  Zenithium
//
//  Types crossing the prescription boundary. Faz 19.
//
//  This is where every engine's answer meets. Recovery says how much the body will take,
//  the strain ceiling puts a number on it, the load ratio says whether the number is a step
//  up or a step back, the muscle map says which tissue is available, and the lens decides
//  what any of that looks like as a session.
//
//  Two rules shape the whole design:
//
//  * **Every prescription states its reason.** A suggestion the user cannot interrogate is
//    a horoscope. `rationale` is not optional and never empty.
//  * **The forecast runs the strain engine backwards.** Rather than guessing what a session
//    will cost, the same TRIMP integral that scores a finished day is inverted to answer
//    "what does 55 minutes at this intensity come to?" — so the number on the prescription
//    is on the same scale as the number the user will see tonight.
//

import Foundation

/// The shape of a session.
enum SessionKind: String, Sendable, Hashable, CaseIterable, Identifiable {
    case rest
    case easyMovement
    case easyAerobic
    case steadyAerobic
    case tempo
    case intervals
    case strengthUpper
    case strengthLower
    case strengthFull
    case compromisedRunning
    case stationWork
    case walk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rest: return "Dinlenme"
        case .easyMovement: return "Hafif hareket"
        case .easyAerobic: return "Kolay aerobik"
        case .steadyAerobic: return "Sürekli koşu"
        case .tempo: return "Tempo"
        case .intervals: return "Interval"
        case .strengthUpper: return "Üst vücut kuvvet"
        case .strengthLower: return "Alt vücut kuvvet"
        case .strengthFull: return "Tam vücut kuvvet"
        case .compromisedRunning: return "Kompanse koşu"
        case .stationWork: return "İstasyon çalışması"
        case .walk: return "Tempolu yürüyüş"
        }
    }

    var symbolName: String {
        switch self {
        case .rest: return "moon.zzz.fill"
        case .easyMovement: return "figure.cooldown"
        case .easyAerobic, .steadyAerobic: return "figure.run"
        case .tempo: return "figure.run.circle"
        case .intervals: return "stopwatch"
        case .strengthUpper, .strengthLower, .strengthFull: return "dumbbell.fill"
        case .compromisedRunning: return "figure.mixed.cardio"
        case .stationWork: return "square.grid.3x3.fill"
        case .walk: return "figure.walk"
        }
    }

    /// Typical fraction of heart-rate reserve, used to invert the TRIMP integral.
    ///
    /// A range rather than a point, because a prescription that says "exactly 71% of
    /// reserve" is pretending to a precision nobody trains to.
    var reserveFraction: ClosedRange<Double> {
        switch self {
        case .rest: return 0.00...0.00
        case .easyMovement, .walk: return 0.25...0.35
        case .easyAerobic: return 0.45...0.55
        case .steadyAerobic: return 0.55...0.68
        case .tempo: return 0.72...0.82
        case .intervals: return 0.85...0.95
        case .strengthUpper, .strengthLower, .strengthFull: return 0.40...0.55
        case .compromisedRunning: return 0.68...0.80
        case .stationWork: return 0.70...0.85
        }
    }

    /// Whether this session loads muscle rather than mainly the cardiovascular system.
    var isMuscular: Bool {
        switch self {
        case .strengthUpper, .strengthLower, .strengthFull, .stationWork: return true
        default: return false
        }
    }
}

/// One prescribed session.
struct PrescribedSession: Sendable, Equatable, Hashable, Identifiable {

    let kind: SessionKind

    /// Suggested duration, minutes.
    let minutes: Int

    /// What this is forecast to cost, on the strain scale.
    let forecastStrain: Double

    /// Where to hold the effort, when the session has a pace target.
    let paceBand: PaceZoneBand?

    /// Whether this is the primary suggestion or an alternative.
    let isPrimary: Bool

    var id: String { "\(kind.rawValue)-\(minutes)" }
}

/// Today's suggestion, with everything needed to argue with it.
/// What the prescription knows about where the person is in their cycle.
///
/// Deliberately narrow, and deliberately not an input to how hard the day should be. See
/// `PrescriptionEngine.cycleContextLine` for why. Yol haritası v4, C6.
struct CycleContext: Sendable, Equatable, Hashable {

    let estimate: CyclePhaseEstimate

    /// The person's own mean heart-rate variability across this phase's baseline group,
    /// when there is enough history to compute one.
    let phaseBaselineHRV: Double?

    /// This morning's reading.
    let todayHRV: Double?

    /// How far today sits from the phase's own mean, as a fraction of that mean.
    ///
    /// A fraction rather than a z-score because the phase baseline is a mean without a
    /// variance — `CycleEngine` partitions days into two groups and averages them, and
    /// inventing a spread from that would be inventing precision.
    var deviationFromPhaseMean: Double? {
        guard let phaseBaselineHRV, let todayHRV, phaseBaselineHRV > 0 else { return nil }
        return (todayHRV - phaseBaselineHRV) / phaseBaselineHRV
    }
}

struct Prescription: Sendable, Equatable {

    /// The headline session.
    let primary: PrescribedSession

    /// One or two other reasonable choices. Never empty for a training lens — a single
    /// option presented as *the* answer overstates how well any app knows a person's day.
    let alternatives: [PrescribedSession]

    /// Why this session and not another. Never empty.
    let rationale: [String]

    /// The best window to train in, from the circadian curve.
    let suggestedWindow: DateInterval?

    /// The strain ceiling this was built against.
    let ceiling: Double?

    /// What the load ratio becomes if the primary session is done.
    let projectedRatio: Double?

    /// Muscles too fatigued to load today, which is what steers a strength lens away from
    /// the obvious session.
    let constrainedMuscles: [MuscleGroup]

    /// The cycle phase this was written in, when one was known. Context for the reader;
    /// it never moved the session. Yol haritası v4, C6.
    let cyclePhase: CyclePhaseEstimate?

    var everySession: [PrescribedSession] { [primary] + alternatives }
}
