//
//  SafetyFilter.swift
//  Zenithium
//
//  The last thing every generated sentence passes through. Faz 24.
//
//  A language model is a text generator, not a clinician, and it does not know what
//  Zenithium is forbidden to say. So nothing it produces reaches the screen unchecked: the
//  filter runs on the model's output, and when it trips, the sentence Zenithium wrote itself
//  is shown instead. The model can fail; the guarantee cannot.
//
//  The three lines this enforces come straight from the spec:
//
//  * §12 — no diagnosis, no naming a condition, no treatment, no dose.
//  * §1 — no calorie targets, no weight goals, no restriction prompts.
//  * §12 — never tell a user to ignore a symptom.
//
//  Matching is on normalised tokens with prefix stems, because Turkish agglutinates:
//  "ilaç", "ilacı" and "ilaçları" are one idea and three tokens. A stem of four characters
//  or more matches by prefix; anything shorter must match exactly, which keeps "doz" from
//  firing on a word that merely starts with those letters.
//
//  The list is deliberately conservative about words that appear in Zenithium's own honest
//  copy. "Hastalık" is a journal behaviour the user logs themselves, so a sentence may
//  legitimately name it; what is banned is the *claim* — "hastasın", "hastalığın var" — not
//  the word. False positives are cheap here anyway: the fallback is the deterministic text,
//  which was always going to be correct.
//

import Foundation

enum SafetyFilter {

    /// Phrases that must never appear, as sequences of normalised stems.
    static let bannedPhrases: [[String]] = [
        // Diagnostic claims. Naming a condition is the bright line.
        ["teshis"], ["hastasin"], ["hastaligin", "var"], ["hastalik", "belirtisi"],
        ["anemi"], ["enfeksiyon"], ["kanser"], ["tumor"], ["diyabet"], ["grip"],
        ["tiroid", "hastalig"], ["diagnos"], ["you", "have"], ["symptom", "of"],

        // Treatment, supplements, dose.
        ["ilac"], ["doz"], ["takviye"], ["supplement"], ["recete"],
        ["almalisin"], ["kullanmalisin"], ["icmelisin"],

        // Calorie, weight, restriction.
        ["kalori"], ["diyet"], ["zayifla"], ["kilo", "ver"], ["kilo", "kayb"],
        ["kilo", "hedef"], ["calorie"], ["weight", "goal"], ["kisitla"],

        // Dismissing symptoms.
        ["gormezden"], ["onemseme"], ["ignore"], ["bosver"], ["endiselenme"],
        ["kafana", "takma"]
    ]

    /// Stems that must match a token exactly to avoid false positives on words like "dozer".
    static let exactMatchStems: Set<String> = ["doz"]

    /// A stem shorter than this must match a token exactly rather than by prefix.
    static let minimumPrefixStemLength = 3

    /// Whether a text is safe to show.
    static func isSafe(_ text: String) -> Bool {
        violation(in: text) == nil
    }

    /// The first banned phrase in a text, joined for logging. `nil` when the text is clean.
    static func violation(in text: String) -> String? {
        let tokens = BiomarkerCatalog.normalize(text).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        guard let phrase = bannedPhrases.first(where: { contains($0, in: tokens) }) else { return nil }
        return phrase.joined(separator: " ")
    }

    /// A text if it is safe, otherwise the fallback.
    ///
    /// There is no attempt to repair unsafe text. A sentence that reached for a diagnosis
    /// cannot be edited into a safe one without changing what it claims, so the honest move
    /// is to discard it and show the sentence Zenithium wrote itself.
    static func sanitized(_ text: String, fallback: String) -> String {
        isSafe(text) ? text : fallback
    }

    /// A whole briefing, checked field by field.
    ///
    /// Any single failure drops the entire briefing back to the deterministic one. Mixing
    /// the two would leave a body that no longer supports its headline, which reads worse
    /// than either version alone.
    static func sanitized(_ briefing: Briefing, fallback: Briefing) -> Briefing {
        let candidates = [briefing.headline, briefing.body] + briefing.points
        guard candidates.allSatisfy(isSafe) else { return fallback }
        return briefing
    }

    /// Whether `phrase` appears as consecutive tokens, each matching its stem.
    private static func contains(_ phrase: [String], in tokens: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= tokens.count else { return false }
        let limit = tokens.count - phrase.count
        for start in 0...limit {
            var matched = true
            for offset in phrase.indices {
                let stem = phrase[offset]
                let token = tokens[start + offset]
                if !matches(stem: stem, token: token) {
                    matched = false
                    break
                }
            }
            if matched {
                // "teşhis değil" is an explicit disclaimer ("not a diagnosis"), not a diagnosis claim.
                if phrase == ["teshis"] && start + 1 < tokens.count && matches(stem: "degil", token: tokens[start + 1]) {
                    continue
                }
                return true
            }
        }
        return false
    }

    private static func matches(stem: String, token: String) -> Bool {
        if exactMatchStems.contains(stem) {
            return token == stem
        }
        if stem.count >= minimumPrefixStemLength {
            return token.hasPrefix(stem)
        }
        return token == stem
    }
}
