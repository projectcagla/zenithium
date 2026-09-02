//
//  BiomarkerCatalogTests.swift
//  ZenithiumTests
//
//  The catalogue is data, so it gets the tests data deserves: that nothing collides, that
//  the persisted keys still resolve, and that Turkish folding actually reaches the letters
//  Unicode diacritic folding does not.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Biomarker catalogue")
struct BiomarkerCatalogTests {

    @Test("Anahtarlar benzersiz")
    func keysAreUnique() {
        let keys = BiomarkerCatalog.all.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test("Her belirtecin en az bir birimi var ve ilki kanonik")
    func everyMarkerHasCanonicalUnit() {
        for definition in BiomarkerCatalog.all {
            #expect(!definition.units.isEmpty, "birimsiz: \(definition.key)")
            #expect(definition.canonicalUnit.factorToCanonical == 1, "kanonik birim 1 değil: \(definition.key)")
        }
    }

    @Test("Referans aralıkları tutarlı")
    func rangesAreOrdered() {
        for definition in BiomarkerCatalog.all {
            for sex in [BiologicalSexValue.male, .female, .notSet] {
                let range = definition.referenceRange.range(for: sex)
                if let minimum = range.minimum, let maximum = range.maximum {
                    #expect(minimum < maximum, "ters aralık: \(definition.key)")
                }
            }
        }
    }

    /// The five markers that shipped before the catalogue existed must still resolve, or
    /// every value written by an earlier build loses its identity.
    @Test("Eski depolama anahtarları hâlâ çözülüyor", arguments: [
        "apoB", "highSensitivityCRP", "vitaminD", "ferritin", "fastingGlucose"
    ])
    func legacyKeysResolve(_ key: String) throws {
        let kind = try #require(BloodMarkerKind.kind(forStorageKey: key))
        #expect(kind.storageKey == key)
        #expect(kind.definition != nil)
    }

    @Test("Bilinmeyen anahtar düşürülmez, özel belirteç olur")
    func unknownKeyBecomesCustom() throws {
        let kind = try #require(BloodMarkerKind.kind(forStorageKey: "gelecektekiBelirtec"))
        #expect(kind == .custom("gelecektekiBelirtec"))
    }

    @Test("Özel belirteç öneki korunur")
    func customRoundTrips() throws {
        let kind = BloodMarkerKind.custom("Kendi Testim")
        let restored = try #require(BloodMarkerKind.kind(forStorageKey: kind.storageKey))
        #expect(restored == kind)
    }

    // MARK: - Normalisation

    /// Dotless "ı" is a letter, not a decorated "i", so `.diacriticInsensitive` folding does
    /// not reach it. This is the case that forced an explicit map.
    @Test("Türkçe harfler katlanıyor")
    func foldsTurkishLetters() {
        #expect(BiomarkerCatalog.normalize("Açlık Glukozu") == "aclik glukozu")
        #expect(BiomarkerCatalog.normalize("HEMOGLOBİN") == "hemoglobin")
        #expect(BiomarkerCatalog.normalize("Çinko") == "cinko")
        #expect(BiomarkerCatalog.normalize("D  Vitamini!!") == "d vitamini")
    }

    @Test("Eşanlamlı eşleştirme")
    func matchesSynonyms() throws {
        #expect(BiomarkerCatalog.definition(matchingName: "HGB")?.key == "hemoglobin")
        #expect(BiomarkerCatalog.definition(matchingName: "Trigliserit")?.key == "triglycerides")
        #expect(BiomarkerCatalog.definition(matchingName: "25 OH Vitamin D")?.key == "vitaminD")
    }

    /// "crp" is a synonym of hs-CRP and "hs crp" is a longer one; on a line carrying both,
    /// the longer match has to win or the marker is right by luck rather than by rule.
    @Test("Uzun eşanlamlı kısa olanı yener")
    func longerSynonymWins() throws {
        let match = try #require(BiomarkerCatalog.bestMatch(inLine: "hs-CRP (C reaktif protein)  0,8  mg/L"))
        #expect(match.definition.key == "highSensitivityCRP")
        #expect(match.matchedTokens >= 2)
    }

    @Test("Eşleşen adın aralığı orijinal metinde doğru yerde")
    func matchRangeMapsBackToOriginal() throws {
        let line = "B12 Vitamini   350   pg/mL"
        let match = try #require(BiomarkerCatalog.bestMatch(inLine: line))
        let matched = String(line[match.originalRange])
        #expect(matched.hasPrefix("B12"))
        #expect(matched.contains("Vitamini"))
    }
}

// MARK: - Index equivalence (Yol haritası v4, A2)

/// The matcher used to scan the whole catalogue for every line, folding each synonym as it
/// went. It now scans the line's tokens against a prebuilt index instead. That is a large
/// enough change to the control flow to be worth pinning: this suite runs the old algorithm
/// as a reference and requires the new one to agree with it, marker for marker.
@Suite("Biomarker matching is unchanged by the index")
struct BiomarkerMatcherEquivalenceTests {

    /// The pre-index algorithm, written out so the fast path has something to be checked
    /// against. Deliberately naive — that is the point of a reference implementation.
    private func referenceMatch(inLine line: String) -> BiomarkerDefinition? {
        let normalized = BiomarkerCatalog.normalizedMapping(line)
        let tokenTexts = normalized.tokens.map(\.text)
        guard !tokenTexts.isEmpty else { return nil }

        var best: (definition: BiomarkerDefinition, tokens: Int, characters: Int, position: Int)?
        for definition in BiomarkerCatalog.all {
            for synonym in definition.synonyms + [definition.displayName] {
                let needle = BiomarkerCatalog.normalize(synonym).split(separator: " ").map(String.init)
                guard !needle.isEmpty, needle.count <= tokenTexts.count else { continue }

                var found: Int?
                for start in 0...(tokenTexts.count - needle.count)
                where Array(tokenTexts[start..<(start + needle.count)]) == needle {
                    found = start
                    break
                }
                guard let position = found else { continue }

                let candidate = (
                    definition: definition,
                    tokens: needle.count,
                    characters: needle.reduce(0) { $0 + $1.count },
                    position: position
                )
                guard let current = best else {
                    best = candidate
                    continue
                }
                let better: Bool
                if candidate.tokens != current.tokens {
                    better = candidate.tokens > current.tokens
                } else if candidate.characters != current.characters {
                    better = candidate.characters > current.characters
                } else {
                    better = candidate.position < current.position
                }
                if better { best = candidate }
            }
        }
        return best?.definition
    }

    /// Every synonym in the catalogue, printed the way a laboratory would print it, plus the
    /// lines that historically caused trouble.
    @Test("Both algorithms name the same marker on every catalogue synonym")
    func agreesOnEverySynonym() {
        for definition in BiomarkerCatalog.all {
            for synonym in definition.synonyms + [definition.displayName] {
                let line = "\(synonym)   12,4  \(definition.canonicalUnit.symbol)   (3,1 - 20,8)"
                let fast = BiomarkerCatalog.bestMatch(inLine: line)?.definition.key
                let reference = referenceMatch(inLine: line)?.key
                #expect(fast != nil, "Hızlı eşleştirici bulamadı: \(line)")
                #expect(reference != nil, "Referans eşleştirici bulamadı: \(line)")
                #expect(fast == reference, "\(line): \(fast ?? "nil") vs \(reference ?? "nil")")
            }
        }
    }

    @Test(
        "Both algorithms agree on awkward report lines",
        arguments: [
            "hs-CRP (C reaktif protein)  0,8  mg/L",
            "LDL Kolesterol            132   mg/dL   (0 - 130)",
            "B12 Vitamini              350   pg/mL",
            "HbA1c  %5,4",
            "Hb 14,2 g/dL   Hct 42",
            "TSH 2,10 uIU/mL     Serbest T4 1,21 ng/dL",
            "Sonuç raporu — hiçbir belirteç yok",
            "",
            "25 OH Vitamin D  18 ng/mL",
            "Ferritin 44 ng/mL  Demir 78 ug/dL"
        ]
    )
    func agreesOnAwkwardLines(line: String) {
        let fast = BiomarkerCatalog.bestMatch(inLine: line)?.definition.key
        let reference = referenceMatch(inLine: line)?.key
        #expect(fast == reference, "\(line): \(fast ?? "nil") vs \(reference ?? "nil")")
    }
}
