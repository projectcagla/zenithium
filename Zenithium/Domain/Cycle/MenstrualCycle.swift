//
//  MenstrualCycle.swift
//  Zenithium
//
//  Cycle phase, and what it does to a baseline. Faz 12.
//
//  ## Why this exists
//
//  Resting heart rate rises by roughly 2–5 bpm in the luteal phase, HRV falls, and core
//  temperature sits about 0.3 °C higher. A recovery engine that does not know this reads a
//  completely ordinary luteal morning as a bad one — every month, for half its users. That
//  is not a missing feature; it is a wrong answer, and this file exists to stop producing it.
//
//  ## What Zenithium is allowed to do with it
//
//  §12 is at its narrowest here, and the line is worth stating plainly:
//
//  * It may estimate which phase you are in, from data you logged, and say how confident it
//    is. It never claims to know.
//  * It may compare today against your own history **in that phase**, which is the entire
//    point — a luteal morning belongs next to other luteal mornings.
//  * It may describe what tends to happen physiologically in a phase.
//  * It may **not** infer pregnancy, diagnose an irregular cycle, predict fertility, or tell
//    anyone what to do about any of it. There is no fertile-window feature here and there
//    will not be one; that is a medical claim in a wellness app's clothing.
//
//  ## The estimate is an estimate
//
//  Phase comes from logged flow plus cycle length. Ovulation is *assumed* to sit a fixed
//  luteal length back from the next expected period, which is the standard approximation and
//  is wrong for anyone whose luteal phase differs — so the phase carries a confidence, and
//  the UI never states it as fact.
//

import Foundation

/// Where in the cycle a day falls.
enum CyclePhase: String, Sendable, Hashable, CaseIterable, Identifiable {

    /// Bleeding.
    case menstrual

    /// After bleeding, before ovulation. Oestrogen rising.
    case follicular

    /// The days around expected ovulation.
    case ovulatory

    /// After ovulation, before the next period. Progesterone dominant.
    case luteal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .menstrual: return "Menstrüel"
        case .follicular: return "Foliküler"
        case .ovulatory: return "Ovulasyon"
        case .luteal: return "Luteal"
        }
    }

    /// What tends to happen to the signals Zenithium reads.
    ///
    /// Descriptive physiology, not a prediction about this person and not advice. The
    /// wording avoids "you will" throughout, because the between-person variation is larger
    /// than the average effect.
    var physiologyNote: String {
        switch self {
        case .menstrual:
            return "Hormon düzeyleri en düşük noktada. Bu fazda istirahat nabzı ve vücut ısısı genelde taban çizgine döner."
        case .follicular:
            return "Östrojen yükselirken çoğu kişide yüksek şiddetli çalışmaya tolerans en iyi seviyededir."
        case .ovulatory:
            return "Östrojen zirvede, vücut ısısı bu fazın sonunda yaklaşık 0,3 °C yükselir."
        case .luteal:
            return "Progesteron baskın. Bu fazda istirahat nabzı tipik olarak 2–5 atım yüksek, HRV daha düşük ve vücut ısısı yaklaşık 0,3 °C üstte seyreder — bunlar normal, kötü toparlanma değil."
        }
    }

    /// Which phase-specific baseline a day is scored against.
    ///
    /// Ovulatory days are pooled with follicular ones. It is a short window, so a separate
    /// baseline would take a year to become usable, and the hormonal profile is closer to
    /// follicular than to luteal.
    var baselineGroup: CycleBaselineGroup {
        switch self {
        case .menstrual, .follicular, .ovulatory: return .follicularPhase
        case .luteal: return .lutealPhase
        }
    }
}

/// The two baselines a phase-aware comparison uses.
enum CycleBaselineGroup: String, Sendable, Hashable, CaseIterable {
    case follicularPhase
    case lutealPhase

    var displayName: String {
        switch self {
        case .follicularPhase: return "Foliküler dönem"
        case .lutealPhase: return "Luteal dönem"
        }
    }
}

/// One logged bleeding day.
struct MenstrualFlowDay: Sendable, Equatable, Hashable, Identifiable {

    let dayStart: Date

    /// Whether this was the first day of a period, when HealthKit recorded that.
    let isCycleStart: Bool

    var id: Date { dayStart }
}

/// A phase estimate for one day.
struct CyclePhaseEstimate: Sendable, Equatable, Hashable {

    let phase: CyclePhase

    /// Day of the cycle, 1 on the first day of bleeding.
    let dayOfCycle: Int

    /// The cycle length used, in days.
    let cycleLength: Int

    /// How much to trust the estimate, 0…1.
    let confidence: Double

    /// Whether the estimate is firm enough to state plainly.
    ///
    /// Below this it is still shown — hiding it would be worse — but the copy hedges and
    /// the phase-aware baseline is not used, because scoring against the wrong phase is
    /// worse than scoring against a pooled one.
    var isConfident: Bool { confidence >= 0.6 }

    /// How the estimate should be worded.
    var qualifier: String {
        isConfident ? "\(phase.displayName) fazdasın" : "Muhtemelen \(phase.displayName.lowercased()) fazdasın"
    }
}
