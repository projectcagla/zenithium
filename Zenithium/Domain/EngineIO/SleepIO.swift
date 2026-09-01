//
//  SleepIO.swift
//  Zenithium
//
//  Sleep score engine input and output. Spec §5.2 in full, §5.6 (invalid sleep lengths).
//

import Foundation

/// One of the four weighted components of the sleep score (§5.2).
enum SleepComponent: String, Sendable, Codable, CaseIterable, Hashable {

    /// `100 · clamp(asleep_h / need_h, 0, 1)` — weight 0.50.
    case duration

    /// `100 · clamp((asleep / timeInBed − 0.75) / 0.20, 0, 1)` — weight 0.20.
    case efficiency

    /// `100 · clamp(((deep + REM) / asleep) / 0.42, 0, 1)` — weight 0.20.
    case restorative

    /// `100 · max(0, 1 − |midpoint − μ_midpoint_14d| / 90 min)` — weight 0.10.
    case consistency

    var displayName: String {
        switch self {
        case .duration: return "Süre"
        case .efficiency: return "Verimlilik"
        case .restorative: return "Onarıcı uyku"
        case .consistency: return "Tutarlılık"
        }
    }

    var explanation: String {
        switch self {
        case .duration: return "İhtiyacının ne kadarını karşıladın."
        case .efficiency: return "Yatakta geçen sürenin ne kadarında uyudun."
        case .restorative: return "Uykunun ne kadarı derin ya da REM'di."
        case .consistency: return "Uyku orta noktan alışıldığına ne kadar yakındı."
        }
    }
}

/// A component's score and the weight it carried after any renormalization.
struct SleepComponentScore: Sendable, Equatable, Hashable {

    let component: SleepComponent

    /// The component score, 0…100.
    let score: Double

    /// The weight actually applied — the spec weight, or the renormalized one when a
    /// component was dropped (§5.2).
    let weight: Double

    init(component: SleepComponent, score: Double, weight: Double) {
        self.component = component
        self.score = score
        self.weight = weight
    }

    /// The component's contribution to the final score.
    var contribution: Double { score * weight }
}

/// Everything the sleep engine needs. Assembled by the orchestration layer, which owns the
/// calendar and the night-resolution rules (ASSUMPTION SLEEP-1, SLEEP-2, SLEEP-3).
struct SleepInput: Sendable, Equatable {

    /// Seconds asleep: core + deep + REM + unspecified (§3).
    let asleepSeconds: Double

    /// Seconds in bed — the union of `.inBed` intervals, or the asleep span when the source
    /// never writes `.inBed` (ASSUMPTION SLEEP-3).
    let timeInBedSeconds: Double

    let deepSeconds: Double
    let remSeconds: Double
    let coreSeconds: Double
    let awakeSeconds: Double

    /// Whether any segment carried stage detail. When false, `Restorative` is dropped and
    /// the other three weights are renormalized (§5.2).
    let hasStageData: Bool

    /// The night's midpoint expressed as minutes from local midnight, so the comparison with
    /// the 14-day mean is a wall-clock comparison (§5.2).
    let midpointMinutesFromLocalMidnight: Double

    /// The 14-day circular mean of midpoints, same units (ASSUMPTION SLEEP-5). `nil` when
    /// fewer than two prior nights exist, in which case `Consistency` is dropped.
    let midpointBaselineMinutes: Double?

    /// The user's baseline sleep need, hours. Default 8.0 (§5.2).
    let baselineNeedHours: Double

    /// Yesterday's day strain, 0…21 (§5.2).
    let yesterdayStrain: Double

    /// Accumulated sleep debt in hours, already decayed 25 %/night over 7 nights (§5.2).
    /// The engine applies the `min(debt, 1.5)` cap.
    let sleepDebtHours: Double

    /// Nap credit in hours from the previous day, naps ≥ 20 min, before the 1.0 h cap (§5.2).
    let napCreditHours: Double

    init(
        asleepSeconds: Double,
        timeInBedSeconds: Double,
        deepSeconds: Double,
        remSeconds: Double,
        coreSeconds: Double,
        awakeSeconds: Double,
        hasStageData: Bool,
        midpointMinutesFromLocalMidnight: Double,
        midpointBaselineMinutes: Double?,
        baselineNeedHours: Double,
        yesterdayStrain: Double,
        sleepDebtHours: Double,
        napCreditHours: Double
    ) {
        self.asleepSeconds = asleepSeconds
        self.timeInBedSeconds = timeInBedSeconds
        self.deepSeconds = deepSeconds
        self.remSeconds = remSeconds
        self.coreSeconds = coreSeconds
        self.awakeSeconds = awakeSeconds
        self.hasStageData = hasStageData
        self.midpointMinutesFromLocalMidnight = midpointMinutesFromLocalMidnight
        self.midpointBaselineMinutes = midpointBaselineMinutes
        self.baselineNeedHours = baselineNeedHours
        self.yesterdayStrain = yesterdayStrain
        self.sleepDebtHours = sleepDebtHours
        self.napCreditHours = napCreditHours
    }
}

/// Whether a night can be scored at all (§5.6).
enum SleepValidity: String, Sendable, Codable, Equatable, Hashable {

    case valid

    /// Under 2 h — rejected, record flagged `.suspect` (§5.6).
    case tooShort

    /// Over 14 h — rejected, record flagged `.suspect` (§5.6).
    case tooLong

    /// No sleep recorded at all — the "No overnight data" state (§5.6).
    case noData

    var isScorable: Bool { self == .valid }

    var dataQualityReason: DataQualityReason? {
        switch self {
        case .valid: return nil
        case .tooShort: return .sleepTooShort
        case .tooLong: return .sleepTooLong
        case .noData: return .noOvernightWear
        }
    }
}

/// The sleep engine's result, carrying the explanation as well as the number (§9).
struct SleepOutput: Sendable, Equatable {

    /// The rounded 0…100 score, or `nil` when `validity` is not `.valid`.
    let score: Double?

    /// `need_h` as computed for this night (§5.2).
    let needHours: Double

    /// Hours actually asleep.
    let asleepHours: Double

    /// Every component that was scored, with the weight it carried.
    let components: [SleepComponentScore]

    /// Components dropped because their input was unavailable (§5.2).
    let droppedComponents: [SleepComponent]

    /// Whether any weight was renormalized.
    var weightsWereRenormalized: Bool { !droppedComponents.isEmpty }

    /// Whether the night could be scored.
    let validity: SleepValidity

    /// Debt actually applied after the 1.5 h cap.
    let appliedDebtHours: Double

    /// Nap credit actually applied after the 1.0 h cap.
    let appliedNapCreditHours: Double

    init(
        score: Double?,
        needHours: Double,
        asleepHours: Double,
        components: [SleepComponentScore],
        droppedComponents: [SleepComponent],
        validity: SleepValidity,
        appliedDebtHours: Double,
        appliedNapCreditHours: Double
    ) {
        self.score = score
        self.needHours = needHours
        self.asleepHours = asleepHours
        self.components = components
        self.droppedComponents = droppedComponents
        self.validity = validity
        self.appliedDebtHours = appliedDebtHours
        self.appliedNapCreditHours = appliedNapCreditHours
    }

    /// The score for one component, when it was scored.
    func component(_ component: SleepComponent) -> SleepComponentScore? {
        components.first { $0.component == component }
    }

    /// How much of the night's need was covered, 0…1, for the ring gauge.
    var needCoverage: Double {
        guard needHours > 0 else { return 0 }
        return min(max(asleepHours / needHours, 0), 1)
    }
}
