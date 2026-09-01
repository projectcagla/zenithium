//
//  LongevityIO.swift
//  Zenithium
//
//  The long-horizon composite. Faz 29.
//
//  ## Why a composite at all, and why this one
//
//  The health-lens user has no strain ceiling and no session to plan. What they have is a
//  question nothing else in the app answers: *is the direction right?* A single number that
//  moves over months answers it, and eighteen separate trend lines do not.
//
//  ## The rule that keeps it honest
//
//  Every composite score is a black box unless it opens. So this one always carries its
//  components, their weights, and what each contributed — and the view is required to show
//  them. A number the user cannot take apart is a horoscope with arithmetic.
//
//  §12: this is not a health assessment, a biological age, or a risk score. It is a weighted
//  average of the user's own trends against the user's own history, and the copy says so.
//

import Foundation

/// One pillar of the composite.
enum LongevityPillar: String, Sendable, Hashable, CaseIterable, Identifiable {

    /// Aerobic capacity: VO₂max, heart-rate recovery.
    case cardiorespiratory

    /// Recovery quality: HRV and resting heart rate against baseline.
    case autonomic

    /// Sleep duration and consistency.
    case sleep

    /// Movement quality: walking speed, steadiness, stair speed.
    case mobility

    /// How consistently the person moved at all.
    case activity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cardiorespiratory: return "Aerobik kapasite"
        case .autonomic: return "Otonom denge"
        case .sleep: return "Uyku"
        case .mobility: return "Hareket kalitesi"
        case .activity: return "Hareket sürekliliği"
        }
    }

    /// Why the pillar is in the composite.
    var rationale: String {
        switch self {
        case .cardiorespiratory:
            return "VO₂max ve nabız toparlanması, uzun vadeli sağlıkla en tutarlı ilişkilendirilen iki ölçüm."
        case .autonomic:
            return "HRV ve istirahat nabzının kendi taban çizgine göre durumu."
        case .sleep:
            return "Süre ve tutarlılık birlikte; ikisi de tek başına yeterli değil."
        case .mobility:
            return "Yürüme hızı, denge ve merdiven hızı — fonksiyonel kapasitenin en erken göstergeleri."
        case .activity:
            return "Ne kadar sert değil, ne kadar düzenli hareket ettiğin."
        }
    }

    /// Weight in the composite.
    ///
    /// Cardiorespiratory carries most because it is the pillar with the strongest and
    /// longest-running evidence base. The weights sum to 1 and are asserted to.
    var weight: Double {
        switch self {
        case .cardiorespiratory: return 0.30
        case .autonomic: return 0.20
        case .sleep: return 0.20
        case .mobility: return 0.15
        case .activity: return 0.15
        }
    }
}

/// One pillar's contribution.
struct LongevityComponent: Sendable, Equatable, Hashable, Identifiable {

    let pillar: LongevityPillar

    /// The pillar's own score, 0…100.
    let score: Double

    /// What this pillar added to the composite: `score × weight`.
    let contribution: Double

    /// Which signals were available for it, so a thin pillar is visible as thin.
    let inputCount: Int

    /// Direction over the window, per month, when a line could be fitted.
    let monthlyChange: Double?

    var id: LongevityPillar { pillar }

    /// The pillar's share of the total, for the breakdown bar.
    func share(ofTotal total: Double) -> Double {
        total > 0 ? contribution / total : 0
    }
}

/// The composite.
struct LongevityScore: Sendable, Equatable {

    /// 0…100, the weighted mean of whichever pillars had data.
    let score: Double

    let components: [LongevityComponent]

    /// How much of the full weight was actually covered. Below 1 the score is computed from
    /// a partial set and the view says so rather than quietly renormalising in silence.
    let coverage: Double

    /// Change per month across the window, when there is enough history.
    let monthlyChange: Double?

    var isPartial: Bool { coverage < 0.99 }

    /// The one sentence. Descriptive, relative to the user's own history, never a verdict
    /// about health (§12).
    var summary: String {
        var sentence = "Zenithium skoru \(ZenithiumFormat.score(score))."
        if let monthlyChange, abs(monthlyChange) >= 0.5 {
            let direction = monthlyChange > 0 ? "yükseliyor" : "düşüyor"
            sentence += " Son aylarda ayda \(ZenithiumFormat.metric(abs(monthlyChange), digits: 1)) puan \(direction)."
        } else {
            sentence += " Son aylarda belirgin bir yön değişikliği yok."
        }
        if isPartial {
            sentence += " Bileşenlerin \(ZenithiumFormat.percentTR(coverage))'i ölçülebildi."
        }
        return sentence
    }
}
