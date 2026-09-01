//
//  StrengthIO.swift
//  Zenithium
//
//  Types crossing the strength boundary. Faz 17.
//

import Foundation

/// An estimated one-rep maximum for one exercise.
struct OneRepMaxEstimate: Sendable, Equatable, Hashable, Identifiable {

    /// The exercise name exactly as the user typed it.
    let exerciseName: String

    /// Estimated maximum, kilograms.
    let estimate: Double

    /// The set it came from.
    let weight: Double
    let reps: Int

    let date: Date

    /// The previous best estimate, when there is one, for the progression figure.
    let previousEstimate: Double?

    var id: String { exerciseName }

    /// Fractional change from the previous best. `nil` when this is the first.
    var change: Double? {
        guard let previousEstimate, previousEstimate > 0 else { return nil }
        return (estimate - previousEstimate) / previousEstimate
    }

    /// Whether the estimate is inside the rep range the formulas were built for.
    ///
    /// Both Epley and Brzycki are fitted to sets of roughly one to ten. At fifteen reps they
    /// disagree with each other by more than they agree, and a set of twenty says more about
    /// endurance than about maximum strength.
    var isReliable: Bool { reps <= 10 }
}

/// Weekly hard sets landing on one muscle group.
struct WeeklyVolume: Sendable, Equatable, Hashable, Identifiable {

    let muscle: MuscleGroup

    /// Effective sets this week — each set weighted by how much of it that muscle took.
    let sets: Double

    var id: MuscleGroup { muscle }

    /// Where the count sits against the range most often cited for hypertrophy.
    ///
    /// §12 does not reach here — this is training, not health — but the same honesty rule
    /// does: the range is presented as what the literature reports, not as a target the app
    /// is setting for this person.
    var band: VolumeBand {
        switch sets {
        case ..<4: return .minimal
        case ..<10: return .maintenance
        case ..<20: return .productive
        default: return .high
        }
    }
}

enum VolumeBand: String, Sendable, Hashable, CaseIterable {
    case minimal
    case maintenance
    case productive
    case high

    var displayName: String {
        switch self {
        case .minimal: return "Çok az"
        case .maintenance: return "Koruma"
        case .productive: return "Verimli"
        case .high: return "Yüksek"
        }
    }

    var explanation: String {
        switch self {
        case .minimal: return "Haftada 4 setin altı; literatürde gelişim için genelde yetersiz sayılır."
        case .maintenance: return "Mevcut kas kütlesini korumaya yeten aralık."
        case .productive: return "Hipertrofi çalışmalarında en sık anılan 10–20 set aralığı."
        case .high: return "20 setin üstü; toparlanma buna yetişiyorsa sorun değil, yetişmiyorsa ilk kısılacak yer."
        }
    }
}

/// How push and pull, or front and back, compare.
struct StrengthBalance: Sendable, Equatable, Hashable {

    let pushSets: Double
    let pullSets: Double
    let anteriorSets: Double
    let posteriorSets: Double

    /// Push divided by pull. `nil` when there is no pull work at all.
    var pushPullRatio: Double? {
        pullSets > 0 ? pushSets / pullSets : nil
    }

    /// Front chain divided by back chain.
    var chainRatio: Double? {
        posteriorSets > 0 ? anteriorSets / posteriorSets : nil
    }

    /// The sentence about balance, when there is one worth saying.
    ///
    /// A ratio near one is the usual recommendation; the copy names the imbalance and its
    /// size and leaves the decision to the person, because plenty of programmes are
    /// deliberately unbalanced for a season.
    var summary: String? {
        guard let ratio = pushPullRatio else { return nil }
        if ratio > 1.5 {
            return "İtme hacmin çekmenin \(ZenithiumFormat.metric(ratio, digits: 1)) katı. Çoğu program bu ikisini bire bir civarında tutar."
        }
        if ratio < 0.67 {
            return "Çekme hacmin itmenin \(ZenithiumFormat.metric(1 / ratio, digits: 1)) katı. Çoğu program bu ikisini bire bir civarında tutar."
        }
        return "İtme ve çekme hacmin dengeli (\(ZenithiumFormat.metric(ratio, digits: 2)))."
    }
}

/// Whether the week is asking for a lighter one.
struct DeloadSignal: Sendable, Equatable, Hashable {

    /// The reasons that fired, strongest first.
    let reasons: [Reason]

    enum Reason: String, Sendable, Hashable, Identifiable {
        case highVolume
        case lowRecovery
        case persistentMuscleFatigue
        case risingLoadRatio

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .highVolume: return "Hacim yüksek"
            case .lowRecovery: return "Toparlanma düşük seyrediyor"
            case .persistentMuscleFatigue: return "Kaslar toparlanmıyor"
            case .risingLoadRatio: return "Yük oranı yükseliyor"
            }
        }
    }

    /// Whether enough signals agree to say anything.
    ///
    /// Two, not one. Any single one of these is an ordinary hard week; it is their
    /// coincidence that describes a week worth easing.
    var isTriggered: Bool { reasons.count >= 2 }

    var summary: String? {
        guard isTriggered else { return nil }
        let list = reasons.map(\.displayName).joined(separator: ", ")
        return "Hafif bir hafta için birkaç işaret aynı anda var: \(list.lowercased()). Karar senin — bu bir gözlem."
    }

    static let none = DeloadSignal(reasons: [])
}
