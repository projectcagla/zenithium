//
//  ClaimStrength.swift
//  Zenithium
//
//  How strongly the app is allowed to speak. Faz 34.
//
//  The instruction "do not overclaim" is the kind that survives review and then quietly
//  erodes over a hundred small copy edits. So it is not an instruction here. The grammar
//  a sentence is permitted to use is **derived** from the evidence behind it, and a test
//  fails when a weakly supported claim reaches for the imperative.
//
//  The mapping, in one place:
//
//  | evidence (lowest grade) | confidence  | strength         | grammar               |
//  |-------------------------|-------------|------------------|-----------------------|
//  | controlled / synthesis  | ≥ 0.70      | .recommendation  | imperative allowed    |
//  | cohort or above         | ≥ 0.45      | .suggestion      | hedged                |
//  | anything else           | anything    | .observation      | descriptive only      |
//
//  Two demotions sit on top of it: a claim resting on sources that contradict each other
//  drops one step, and a claim resting on any unverified source can never be a
//  recommendation regardless of how good the rest of the evidence looks.
//

import Foundation

/// How strongly a claim may be phrased.
enum ClaimStrength: Int, Sendable, Codable, CaseIterable, Comparable {

    /// A description of the user's own data. No instruction, no inference.
    case observation = 0

    /// A hedged suggestion.
    case suggestion = 1

    /// A direct recommendation. The only level permitted the imperative mood.
    case recommendation = 2

    static func < (lhs: ClaimStrength, rhs: ClaimStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .observation: return "Gözlem"
        case .suggestion: return "Öneri"
        case .recommendation: return "Tavsiye"
        }
    }

    /// Only a recommendation may tell the user to do something.
    var permitsImperative: Bool { self == .recommendation }

    /// One step down, floored at `.observation`.
    var demoted: ClaimStrength {
        ClaimStrength(rawValue: max(0, rawValue - 1)) ?? .observation
    }

    // MARK: - Thresholds

    /// Confidence needed before evidence strong enough for a recommendation may produce one.
    static let recommendationConfidence = 0.70

    /// Confidence below which nothing may be phrased as more than an observation.
    static let suggestionConfidence = 0.45

    // MARK: - Resolution

    /// The strongest phrasing a claim with this backing is permitted.
    ///
    /// - Parameters:
    ///   - lowestGrade: the weakest study design among the claim's sources. `nil` when the
    ///     claim has no sources at all, which floors it at `.observation` — an unsourced
    ///     engine states what it measured and stops there.
    ///   - confidence: the claim's own confidence, after every penalty has been applied.
    ///   - hasContradiction: whether the supporting sources disagree with one another.
    ///   - allSourcesVerified: whether every source's bibliographic details are confirmed.
    static func resolve(
        lowestGrade: EvidenceGrade?,
        confidence: Double,
        hasContradiction: Bool = false,
        allSourcesVerified: Bool = true
    ) -> ClaimStrength {
        guard let lowestGrade else { return .observation }

        var strength: ClaimStrength
        if lowestGrade >= .controlled, confidence >= recommendationConfidence {
            strength = .recommendation
        } else if lowestGrade >= .cohort, confidence >= suggestionConfidence {
            strength = .suggestion
        } else {
            strength = .observation
        }

        // Literature that disagrees with itself supports a weaker sentence than literature
        // that agrees, even when every individual study is well designed.
        if hasContradiction {
            strength = strength.demoted
        }

        // An unconfirmed source is capped rather than discarded: the claim can still be
        // made, just not in the imperative.
        if !allSourcesVerified, strength == .recommendation {
            strength = .suggestion
        }

        return strength
    }
}

/// The grammatical contract each strength carries.
///
/// ## How the check works, and why it is shaped this way
///
/// Turkish forms the second-person singular imperative from the bare verb stem — *azalt*,
/// *uyu*, *yat* — and the polite or plural form by adding `-ın / -in / -un / -ün` and their
/// longer variants. So an imperative is recognised by **exact match** against a stem, or a
/// stem plus one of those endings. Nothing else counts.
///
/// The first version of this matched by prefix, and it was wrong in a way worth recording:
/// `ölçütün` ("of the metric") starts with `ölç` ("measure!"), `bölge` starts with `böl`,
/// `yatak` starts with `yat`. Prefix matching flagged the app's own descriptive prose as
/// giving orders. Exact matching also gets the linguistics right in the other direction —
/// *azaltmayı düşünebilirsin* ("you could consider reducing") is an infinitive inside a
/// hedge, and it is genuinely not an instruction, so it should not be flagged.
///
/// ## Scope, stated plainly
///
/// This is a lint over **Zenithium's own copy**, not a Turkish parser. It knows the
/// imperative stems this app actually writes and will miss one phrased some way no engine
/// here uses. That is the honest limit of a word list, and it is still worth having: the
/// failure it prevents is a copy edit that quietly promotes a weakly supported observation
/// into an instruction, and those edits reuse the same handful of verbs every time.
enum ClaimLanguage {

    /// Imperative stems the app's own recommendation copy uses.
    ///
    /// Bare stems only. Suffixed forms are derived by `imperativeForms`, so adding a verb
    /// here covers every ending without listing them.
    static let imperativeVerbStems: Set<String> = [
        "azalt", "artır", "arttır", "yükselt", "düşür",
        "dinlen", "uyu", "yat", "kalk", "bekle",
        "koru", "sürdür", "bırak", "ekle", "çıkar",
        "kaçın", "ertele", "hafiflet", "kısalt", "uzat",
        "planla", "ölç", "kaydet", "tamamla", "önceliklendir",
        "yavaşla", "hızlan", "böl", "dağıt", "atla"
    ]

    /// Imperatives that are safety directives rather than training instructions.
    ///
    /// "Show this to your doctor" must remain sayable at every strength — an observation
    /// that could not direct someone to a clinician would be a worse app, not a humbler one.
    static let safetyStems: Set<String> = [
        "başvur", "danış", "göster", "sor", "durdur"
    ]

    /// The imperative endings Turkish adds to a bare stem.
    ///
    /// The empty string is first: the bare stem *is* the singular imperative.
    static let imperativeSuffixes: [String] = [
        "", "ın", "in", "un", "ün", "ınız", "iniz", "unuz", "ünüz"
    ]

    /// Every surface form of `stem` that is an imperative.
    static func imperativeForms(of stem: String) -> Set<String> {
        Set(imperativeSuffixes.map { stem + $0 })
    }

    private static let allImperativeForms: Set<String> = {
        var forms: Set<String> = []
        for stem in imperativeVerbStems {
            forms.formUnion(imperativeForms(of: stem))
        }
        return forms
    }()

    private static let allSafetyForms: Set<String> = {
        var forms: Set<String> = []
        for stem in safetyStems {
            forms.formUnion(imperativeForms(of: stem))
        }
        return forms
    }()

    /// Lowercases using the Turkish rules, so `İ → i` and `I → ı` rather than the invariant
    /// mapping that would turn `AZALTIN` into a token no stem matches.
    static func turkishLowercased(_ text: String) -> String {
        text.replacingOccurrences(of: "I", with: "ı")
            .replacingOccurrences(of: "İ", with: "i")
            .lowercased(with: Locale(identifier: "tr_TR"))
    }

    /// Splits text into word tokens, keeping Turkish letters together.
    static func tokens(in text: String) -> [String] {
        turkishLowercased(text)
            .unicodeScalars
            .split(whereSeparator: { !CharacterSet.alphanumerics.contains($0) })
            .map { String(String.UnicodeScalarView($0)) }
    }

    /// Every imperative stem the text uses, excluding safety directives.
    static func imperativeStems(in text: String) -> [String] {
        var found: [String] = []
        for token in tokens(in: text) {
            guard !allSafetyForms.contains(token) else { continue }
            guard allImperativeForms.contains(token) else { continue }
            guard let stem = imperativeVerbStems.first(where: { imperativeForms(of: $0).contains(token) }) else {
                continue
            }
            if !found.contains(stem) { found.append(stem) }
        }
        return found
    }

    /// Whether `text` is permitted at `strength`.
    static func permits(_ text: String, at strength: ClaimStrength) -> Bool {
        guard !strength.permitsImperative else { return true }
        return imperativeStems(in: text).isEmpty
    }
}

/// How loudly a claim must disclaim itself.
///
/// The strength is deliberately not a copy of `ClaimStrength`: a confident training
/// recommendation carries a lighter disclaimer than a tentative observation that touches
/// health. What matters is the subject, not the certainty.
enum DisclaimerTier: Int, Sendable, Codable, CaseIterable, Comparable {

    /// A description of the user's own measurements. Needs no disclaimer, and printing one
    /// here is how an app teaches people to stop reading disclaimers.
    case none = 0

    /// A training instruction.
    case training = 1

    /// Anything that touches health rather than performance.
    case health = 2

    static func < (lhs: DisclaimerTier, rhs: DisclaimerTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
