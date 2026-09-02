//
//  Recommendation.swift
//  Zenithium
//
//  One thing the app has to say, with everything needed to argue about it. Faz 34.
//
//  `PrescriptionEngine`'s own header states the standard this type exists to meet: a
//  suggestion the user cannot interrogate is a horoscope. So every field below that looks
//  like overhead is the part that makes the headline answerable — where the number came
//  from, which literature it leans on, how far that literature had to travel to reach
//  this user, and what would have to change for the answer to change.
//
//  `wouldChangeIf` is mandatory and cannot be empty. A system that cannot say what would
//  change its mind is not advising, it is predicting.
//

import Foundation

/// Which part of the user's life a recommendation is about.
enum RecommendationDomain: String, Sendable, Codable, CaseIterable, Identifiable {
    case training
    case sleep
    case recovery
    case circadian
    case environment
    case measurement

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .training: return "Antrenman"
        case .sleep: return "Uyku"
        case .recovery: return "Toparlanma"
        case .circadian: return "Sirkadiyen ritim"
        case .environment: return "Çevre"
        case .measurement: return "Ölçüm"
        }
    }

    var symbolName: String {
        switch self {
        case .training: return "figure.run"
        case .sleep: return "bed.double"
        case .recovery: return "heart.text.square"
        case .circadian: return "sun.horizon"
        case .environment: return "thermometer.medium"
        case .measurement: return "sensor.tag.radiowaves.forward"
        }
    }
}

/// One statement the app makes, and its complete backing.
struct Recommendation: Sendable, Equatable, Identifiable {

    /// Stable across days for the same rule, so a card does not lose its place on refresh.
    let id: String

    let domain: RecommendationDomain
    let strength: ClaimStrength

    /// One sentence. Its grammar is constrained by `strength`.
    let headline: String

    /// The supporting paragraph.
    let body: String

    let confidence: ConfidenceScore

    /// The user's own measurements behind this.
    let evidence: [EvidenceNode]

    /// Keys into `EvidenceLibrary`.
    let referenceIDs: [String]

    let limitations: [ScientificLimitation]

    /// Concrete conditions that would retract or change this. Never empty.
    let wouldChangeIf: [String]

    let disclaimerTier: DisclaimerTier

    /// How far the cited literature sits from this user, when it does.
    let populationNote: String?

    init(
        id: String,
        domain: RecommendationDomain,
        strength: ClaimStrength,
        headline: String,
        body: String,
        confidence: ConfidenceScore,
        evidence: [EvidenceNode] = [],
        referenceIDs: [String] = [],
        limitations: [ScientificLimitation] = [],
        wouldChangeIf: [String],
        disclaimerTier: DisclaimerTier,
        populationNote: String? = nil
    ) {
        self.id = id
        self.domain = domain
        self.strength = strength
        self.headline = headline
        self.body = body
        self.confidence = confidence
        self.evidence = evidence
        self.referenceIDs = referenceIDs
        self.limitations = limitations
        self.wouldChangeIf = wouldChangeIf
        self.disclaimerTier = disclaimerTier
        self.populationNote = populationNote
    }

    /// The sources behind this, resolved.
    var references: [Reference] { EvidenceLibrary.resolve(referenceIDs) }

    /// Pairs of sources that disagree, for the "the literature is not settled" line.
    var contradictions: [(Reference, Reference)] {
        EvidenceLibrary.contradictions(among: referenceIDs)
    }

    /// Whether this recommendation keeps the grammatical contract its strength implies.
    ///
    /// Used by tests and by `Scripts/check-symbols.py`. It is checked rather than assumed
    /// because the failure it catches — a copy edit that promotes an observation into an
    /// instruction — is invisible in review and permanent once shipped.
    var honoursLanguageContract: Bool {
        ClaimLanguage.permits(headline, at: strength) && ClaimLanguage.permits(body, at: strength)
    }
}
