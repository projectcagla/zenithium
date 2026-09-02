//
//  EvidenceLayerTests.swift
//  ZenithiumTests
//
//  The evidence layer's invariants. Faz 34.
//
//  These tests guard a class of failure that no build catches and no reviewer reliably
//  catches either: a citation that quietly stops matching the claim it supports, or a
//  weakly supported sentence that drifts into the imperative during a copy edit. Both are
//  invisible in a diff and permanent once shipped.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Kanıt katmanı")
struct EvidenceLayerTests {

    // MARK: - The table itself

    @Test("Kaynak tablosu yapısal olarak tutarlı")
    func libraryIsStructurallySound() {
        let failures = EvidenceLibrary.integrityFailures()
        #expect(failures.isEmpty, "\(failures)")
    }

    /// The field that carries most of the honesty. A source without it would let a claim
    /// inherit an authority nobody ever wrote down.
    @Test("Her kaynak neyi göstermediğini söylüyor")
    func everySourceStatesWhatItDoesNotShow() {
        for reference in EvidenceLibrary.all {
            let text = reference.doesNotShow.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!text.isEmpty, "\(reference.id) doesNotShow boş")
        }
    }

    /// The servability guard is unreachable from the shipped table — by design, since
    /// `everySourceStatesWhatItDoesNotShow` keeps the table clean. What is asserted here is
    /// the guard's premise and the lookup's behaviour on an id nobody defined.
    @Test("Tanımsız kaynak sunulmuyor")
    func anUndefinedSourceIsNotServed() {
        let hollow = Reference(
            id: "HOLLOW-2000",
            authors: "Test",
            year: 2000,
            title: "Boş",
            venue: "Test",
            doi: "10.1000/test",
            grade: .synthesis,
            population: .unreported,
            doesNotShow: "   "
        )
        // The library serves from its own table, so the guard is exercised through the
        // property that decides servability rather than by mutating a `static let`.
        #expect(hollow.doesNotShow.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(EvidenceLibrary.reference("HOLLOW-2000") == nil)
    }

    @Test("Tanımlayıcısı olmayan kaynak doğrulanmamış sayılıyor")
    func anUnlocatableSourceIsNeverVerified() {
        for reference in EvidenceLibrary.all where !reference.isLocatable {
            #expect(reference.needsVerification, "\(reference.id) tanımlayıcısız ama işaretsiz")
            #expect(!reference.isVerified)
        }
    }

    @Test("DOI biçimi geçerli")
    func doiFormatHolds() {
        for reference in EvidenceLibrary.all {
            guard let doi = reference.doi else { continue }
            #expect(doi.hasPrefix("10."), "\(reference.id): \(doi)")
            #expect(doi.contains("/"), "\(reference.id): \(doi)")
            #expect(!doi.contains(" "), "\(reference.id): \(doi)")
        }
    }

    @Test("PMID yalnızca rakam")
    func pmidIsNumeric() {
        for reference in EvidenceLibrary.all {
            guard let pmid = reference.pmid else { continue }
            #expect(!pmid.isEmpty)
            let isAllDigits = pmid.allSatisfy { $0.isNumber }
            #expect(isAllDigits, "\(reference.id): \(pmid)")
        }
    }

    /// Recorded disagreement has to point both ways, or one card shows the conflict and
    /// its counterpart silently does not.
    @Test("Çelişkiler çift yönlü")
    func contradictionsAreSymmetric() {
        for reference in EvidenceLibrary.all {
            for otherID in reference.contradicts {
                let other = EvidenceLibrary.references[otherID]
                #expect(other != nil, "\(reference.id) → \(otherID) yok")
                #expect(other?.contradicts.contains(reference.id) == true,
                        "\(otherID) geri işaret etmiyor")
            }
        }
    }

    @Test("ACWR çelişkisi kayıtlı")
    func theLoadRatioDisputeIsRecorded() {
        let ids = ["GABBETT-2016", "HULIN-2016", "LOLLI-2019"]
        #expect(EvidenceLibrary.hasContradiction(among: ids))
        #expect(!EvidenceLibrary.contradictions(among: ids).isEmpty)
    }

    @Test("Çelişki çiftleri bir kez listeleniyor")
    func contradictionPairsAreNotDuplicated() {
        let pairs = EvidenceLibrary.contradictions(among: ["GABBETT-2016", "LOLLI-2019"])
        #expect(pairs.count == 1)
    }

    @Test("Kaynağı olmayan sınırların derecesi yok")
    func gradeIsNilWithoutSources() {
        #expect(EvidenceLibrary.lowestGrade(among: []) == nil)
        #expect(EvidenceLibrary.lowestGrade(among: ["YOK-1999"]) == nil)
    }

    @Test("En zayıf tasarım belirleyici")
    func theWeakestDesignGoverns() {
        // KAMINSKY-2015 is cross-sectional, ROSS-2016 is a consensus statement.
        let grade = EvidenceLibrary.lowestGrade(among: ["ROSS-2016", "KAMINSKY-2015"])
        #expect(grade == .observational)
    }

    // MARK: - Claim strength

    @Test("Kaynaksız iddia gözlemde kalıyor")
    func noSourcesMeansObservation() {
        #expect(ClaimStrength.resolve(lowestGrade: nil, confidence: 1.0) == .observation)
    }

    @Test("Güçlü kanıt ve yüksek güven tavsiye üretiyor")
    func strongEvidenceEarnsARecommendation() {
        let strength = ClaimStrength.resolve(lowestGrade: .synthesis, confidence: 0.80)
        #expect(strength == .recommendation)
    }

    @Test("Güven düşünce tavsiye öneriye iniyor")
    func lowConfidenceDemotesEvenStrongEvidence() {
        #expect(ClaimStrength.resolve(lowestGrade: .synthesis, confidence: 0.50) == .suggestion)
        #expect(ClaimStrength.resolve(lowestGrade: .synthesis, confidence: 0.30) == .observation)
    }

    @Test("Kohort tasarımı tavsiyeye yükselemiyor")
    func cohortDesignCannotReachRecommendation() {
        #expect(ClaimStrength.resolve(lowestGrade: .cohort, confidence: 0.99) == .suggestion)
    }

    @Test("Mekanizma düzeyi yalnızca gözlem")
    func mechanisticStaysObservational() {
        #expect(ClaimStrength.resolve(lowestGrade: .mechanistic, confidence: 0.99) == .observation)
        #expect(ClaimStrength.resolve(lowestGrade: .observational, confidence: 0.99) == .observation)
    }

    @Test("Çelişki bir kademe düşürüyor")
    func contradictionCostsOneStep() {
        let agreed = ClaimStrength.resolve(lowestGrade: .synthesis, confidence: 0.90)
        let disputed = ClaimStrength.resolve(
            lowestGrade: .synthesis,
            confidence: 0.90,
            hasContradiction: true
        )
        #expect(agreed == .recommendation)
        #expect(disputed == .suggestion)
    }

    @Test("Doğrulanmamış kaynak tavsiyeyi engelliyor")
    func anUnverifiedSourceBlocksTheImperative() {
        let strength = ClaimStrength.resolve(
            lowestGrade: .synthesis,
            confidence: 0.95,
            allSourcesVerified: false
        )
        #expect(strength == .suggestion)
    }

    // MARK: - The grammar contract

    @Test("Emir kipi yalnızca tavsiye seviyesinde serbest")
    func onlyRecommendationsMayInstruct() {
        let imperative = "Bugün yükü azalt."
        #expect(ClaimLanguage.permits(imperative, at: .recommendation))
        #expect(!ClaimLanguage.permits(imperative, at: .suggestion))
        #expect(!ClaimLanguage.permits(imperative, at: .observation))
    }

    @Test("Betimleyici cümle her seviyede serbest")
    func descriptiveCopyIsAlwaysAllowed() {
        let descriptive = "Toparlanma skorun 42; son 14 günün en düşüğü."
        for strength in ClaimStrength.allCases {
            #expect(ClaimLanguage.permits(descriptive, at: strength))
        }
    }

    /// "Show this to your doctor" has to stay sayable at every level. An app that could
    /// not point someone at a clinician unless it was confident would be worse, not humbler.
    @Test("Güvenlik yönlendirmesi her seviyede serbest")
    func safetyDirectivesAreExempt() {
        let safety = "Bu değeri hekimine göster."
        #expect(ClaimLanguage.permits(safety, at: .observation))
        #expect(ClaimLanguage.imperativeStems(in: safety).isEmpty)
    }

    @Test("Türkçe büyük harf emir kipini gizlemiyor")
    func turkishUppercaseDoesNotHideAnImperative() {
        #expect(!ClaimLanguage.permits("BUGÜN YÜKÜ AZALT", at: .observation))
        #expect(!ClaimLanguage.permits("Yükü ARTTIR", at: .suggestion))
    }

    /// The bug this replaces was real and shipped in the first draft of this file: prefix
    /// matching flagged `ölçütün` ("of the metric") because it begins with `ölç`
    /// ("measure!"), which made the app's own descriptive prose read as giving orders.
    @Test("Emir köküyle başlayan isimler emir sayılmıyor")
    func nounsBeginningWithAStemAreNotImperatives() {
        let nouns = [
            "Bu ölçütün sakatlıkla ilişkisi tartışmalı.",
            "Bölge bazlı bir dağılım gösteriyor.",
            "Yatak odası sıcaklığı kaydedilmedi.",
            "Bugünü hafif tutmayı düşünebilirsin.",
            "Uyku süren ortalamanın altında."
        ]
        for sentence in nouns {
            #expect(
                ClaimLanguage.imperativeStems(in: sentence).isEmpty,
                "yanlış işaretlendi: \(sentence) → \(ClaimLanguage.imperativeStems(in: sentence))"
            )
        }
    }

    /// Turkish forms the singular imperative from the bare stem and the polite form with
    /// `-ın / -in / -un / -ün`. Both must be caught; the infinitive inside a hedge must not.
    @Test("Emir kipinin çekimli hâlleri yakalanıyor, mastar yakalanmıyor")
    func imperativeInflectionsAreCaughtButInfinitivesAreNot() {
        #expect(ClaimLanguage.imperativeStems(in: "Yükü azalt") == ["azalt"])
        #expect(ClaimLanguage.imperativeStems(in: "Yükü azaltın") == ["azalt"])
        #expect(ClaimLanguage.imperativeStems(in: "Yükü azaltınız") == ["azalt"])
        #expect(ClaimLanguage.imperativeStems(in: "Yükü azaltmayı düşünebilirsin").isEmpty)
    }

    // MARK: - Population transfer

    @Test("Uyumlu popülasyon güveni düşürmüyor")
    func aMatchingSampleCostsNothing() {
        let reference = Reference(
            id: "MATCH-2020",
            authors: "Test",
            year: 2020,
            title: "Test",
            venue: "Test",
            doi: "10.1000/match",
            grade: .synthesis,
            population: StudiedPopulation(sex: .mixed, trainingStatus: .recreational),
            doesNotShow: "Test"
        )
        let fit = PopulationTransfer.fit(
            of: reference,
            userAge: 40,
            userSex: .female,
            userStatus: .recreational
        )
        #expect(fit.factor == 1.0)
        #expect(fit.note == nil)
    }

    @Test("Uzak popülasyon güveni düşürüyor ve gerekçesini yazıyor")
    func adistantSampleCostsConfidenceAndSaysWhy() {
        // HULIN-2016: 53 elite men. A recreational woman is three mismatches away.
        let fit = PopulationTransfer.combinedFit(
            of: ["HULIN-2016"],
            userAge: 45,
            userSex: .female,
            userStatus: .recreational
        )
        #expect(fit.factor < 1.0)
        #expect(fit.note != nil)
        #expect(!fit.reasons.isEmpty)
    }

    @Test("Popülasyon cezası tabanın altına inmiyor")
    func theTransferPenaltyHasAFloor() {
        let hostile = Reference(
            id: "HOSTILE-2020",
            authors: "Test",
            year: 2020,
            title: "Test",
            venue: "Test",
            doi: "10.1000/hostile",
            grade: .controlled,
            population: StudiedPopulation(
                sex: .male,
                ageRange: 18...25,
                trainingStatus: .elite,
                sampleSize: 6
            ),
            doesNotShow: "Test"
        )
        let fit = PopulationTransfer.fit(
            of: hostile,
            userAge: 62,
            userSex: .female,
            userStatus: .untrained
        )
        #expect(fit.factor >= PopulationTransfer.confidenceFloor)
        #expect(fit.reasons.count == 4)
    }

    @Test("Bildirilmemiş örneklem ayrıca cezalandırılıyor")
    func anUnreportedSampleIsPenalised() {
        let fit = PopulationTransfer.combinedFit(
            of: ["LOLLI-2019"],
            userAge: 30,
            userSex: .male,
            userStatus: .trained
        )
        #expect(fit.factor < 1.0)
    }

    /// Averaging would let one well-matched study launder a distant one.
    @Test("Birleşik uyum en kötü kaynağa göre belirleniyor")
    func theWorstFitGoverns() {
        let ids = ["WATSON-2015", "HULIN-2016"]
        let combined = PopulationTransfer.combinedFit(
            of: ids,
            userAge: 45,
            userSex: .female,
            userStatus: .recreational
        )
        let worst = EvidenceLibrary.resolve(ids)
            .map {
                PopulationTransfer.fit(
                    of: $0,
                    userAge: 45,
                    userSex: .female,
                    userStatus: .recreational
                ).factor
            }
            .min()
        #expect(combined.factor == worst)
    }

    @Test("Yaşı bilinmeyen kullanıcı yaş yüzünden cezalandırılmıyor")
    func unknownAgeIsNotChargedTwice() {
        let withoutAge = PopulationTransfer.combinedFit(
            of: ["KAMINSKY-2015"],
            userAge: nil,
            userSex: .male,
            userStatus: .mixed
        )
        #expect(withoutAge.factor == 1.0)
    }

    // MARK: - Disclaimer tiers

    @Test("Gözlem kartı uyarı taşımıyor, sağlık kartı taşıyor")
    func disclaimersScaleWithSubject() {
        #expect(SafetyCopy.disclaimer(for: .none) == nil)
        #expect(SafetyCopy.disclaimer(for: .training)?.isEmpty == false)

        let health = SafetyCopy.disclaimer(for: .health)
        #expect(health?.contains("teşhis") == true)
        #expect(health?.contains("hekim") == true)
    }

    // MARK: - Boundary registry

    @Test("Sınır kayıtlarındaki her kaynak kütüphanede var")
    func everyBoundaryReferenceResolves() {
        for (engine, boundary) in ScientificBoundaryRegistry.boundaries {
            for id in boundary.referenceIDs {
                #expect(EvidenceLibrary.references[id] != nil, "\(engine) → \(id) çözümlenemedi")
            }
        }
    }

    @Test("Kaynaklandırılmış sınırlar yapısal anahtar taşıyor")
    func migratedBoundariesCarryStructuredKeys() {
        for key in ["Recovery", "TrainingLoad", "SleepScore", "Fatigue", "VitalsDeviation"] {
            let boundary = ScientificBoundaryRegistry.boundaries[key]
            #expect(boundary != nil, "\(key)")
            #expect(boundary?.referenceIDs.isEmpty == false, "\(key) yapısal kaynak taşımıyor")
        }
    }
}
