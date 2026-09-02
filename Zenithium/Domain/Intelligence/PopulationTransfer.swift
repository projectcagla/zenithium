//
//  PopulationTransfer.swift
//  Zenithium
//
//  How far a finding has to travel to reach this user. Faz 34.
//
//  A result established in ten trained men aged 22–30 is not false for a 52-year-old
//  recreational woman — it is simply untested there. Most health software resolves that
//  gap by not mentioning it. Zenithium prices it: the further the study's sample sits
//  from the person reading the screen, the lower the confidence attached to the claim,
//  and the reason is written out in the same sentence.
//
//  The penalties are deliberately mild and they multiply rather than accumulate to zero.
//  A floor of 0.60 keeps the mechanism from turning every claim about a woman into
//  noise, which is what a harsher rule would do given how much of the sports science
//  literature was collected in men.
//

import Foundation

/// How well a source's sample matches the person reading the result.
struct PopulationFit: Sendable, Equatable {

    /// Multiplier applied to the claim's confidence, in `0.60 ... 1.00`.
    let factor: Double

    /// Turkish explanation, or `nil` when the sample matches well enough to be silent.
    let note: String?

    /// The individual mismatches found, for the trace.
    let reasons: [String]

    static let exact = PopulationFit(factor: 1.0, note: nil, reasons: [])
}

enum PopulationTransfer {

    /// Confidence never falls below this from population mismatch alone.
    ///
    /// Named `confidenceFloor` rather than `floor` on purpose: the shorter name shadows the
    /// standard library's `floor(_:)` inside this type, and the resulting diagnostic is one
    /// of the less obvious ones to read.
    static let confidenceFloor = 0.60

    /// Penalty when the study's sample is one sex and the user is the other.
    static let sexMismatchPenalty = 0.88

    /// Penalty when the sample's sex was never reported.
    static let sexUnreportedPenalty = 0.94

    /// Penalty when the user's age falls outside the studied range.
    static let ageOutsidePenalty = 0.90

    /// Penalty per step of distance on the untrained → elite ladder.
    static let trainingStepPenalty = 0.93

    /// Penalty for a sample too small to generalise from.
    static let smallSamplePenalty = 0.92

    /// Below this many participants a sample counts as small.
    static let smallSampleThreshold = 20

    // MARK: - Entry point

    /// How much of `reference` transfers to this user.
    ///
    /// - Parameters:
    ///   - reference: the source being applied.
    ///   - userAge: the user's age in years, or `nil` when unknown. Unknown age is not
    ///     penalised — the app already discounts unknown characteristics elsewhere, and
    ///     charging twice for the same gap would make every claim about a new user weak
    ///     for reasons that have nothing to do with the literature.
    ///   - userSex: the user's biological sex.
    ///   - userStatus: how trained the user is.
    static func fit(
        of reference: Reference,
        userAge: Int?,
        userSex: BiologicalSexValue,
        userStatus: TrainingStatus
    ) -> PopulationFit {
        let population = reference.population
        var factor = 1.0
        var reasons: [String] = []

        // Sex.
        switch (population.sex, userSex) {
        case (.male, .female), (.female, .male):
            factor *= sexMismatchPenalty
            reasons.append("Bulgu yalnızca \(population.sex.displayName) katılımcılarda gösterildi.")
        case (.unreported, _):
            factor *= sexUnreportedPenalty
            reasons.append("Çalışmanın katılımcı cinsiyeti bildirilmemiş.")
        default:
            break
        }

        // Age.
        if let userAge, let ageRange = population.ageRange, !ageRange.contains(userAge) {
            factor *= ageOutsidePenalty
            reasons.append("Yaşın, çalışmanın \(ageRange.lowerBound)–\(ageRange.upperBound) yaş aralığının dışında.")
        }

        // Training status, measured as distance on the ladder rather than as a mismatch,
        // so elite-versus-recreational costs more than trained-versus-recreational.
        if let studied = population.trainingStatus.ladderPosition,
           let user = userStatus.ladderPosition {
            let distance = abs(studied - user)
            if distance > 0 {
                factor *= pow(trainingStepPenalty, Double(distance))
                reasons.append("Çalışma \(population.trainingStatus.displayName) katılımcılarda yapıldı; sen \(userStatus.displayName) profildesin.")
            }
        }

        // Sample size.
        if let sampleSize = population.sampleSize, sampleSize < smallSampleThreshold {
            factor *= smallSamplePenalty
            reasons.append("Örneklem küçük (\(sampleSize) kişi).")
        }

        let clamped = MathSupport.clamp(factor, confidenceFloor, 1.0)
        guard !reasons.isEmpty else { return .exact }

        let note = "Bu bulgu \(population.summary) katılımcılarda gösterildi; "
            + "senin profilinle arasındaki fark nedeniyle güven düşürüldü."

        return PopulationFit(factor: clamped, note: note, reasons: reasons)
    }

    /// The combined fit across several sources.
    ///
    /// The *worst* fit governs rather than the average. A claim leaning on one well-matched
    /// study and one distant one is only as transferable as its weakest leg, and averaging
    /// would let a good match launder a bad one.
    static func combinedFit(
        of ids: [String],
        userAge: Int?,
        userSex: BiologicalSexValue,
        userStatus: TrainingStatus
    ) -> PopulationFit {
        let fits = EvidenceLibrary.resolve(ids).map {
            fit(of: $0, userAge: userAge, userSex: userSex, userStatus: userStatus)
        }
        guard let worst = fits.min(by: { $0.factor < $1.factor }) else { return .exact }
        return worst
    }
}
