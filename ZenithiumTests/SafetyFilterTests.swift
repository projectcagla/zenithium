//
//  SafetyFilterTests.swift
//  ZenithiumTests
//
//  The filter that stands between a language model and the screen. The tests that matter
//  most here are the negative ones: Zenithium's own honest sentences must survive it, or
//  the fallback fires constantly and the model layer is dead weight.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Safety filter")
struct SafetyFilterTests {

    // MARK: - Must be blocked

    @Test("Teşhis dili engellenir", arguments: [
        "Bu değerlere bakınca anemi olduğun anlaşılıyor.",
        "Ferritin düşük, demir takviyesi almalısın.",
        "Günde 2000 IU doz öneriyorum.",
        "Bu belirtiyi görmezden gelebilirsin.",
        "Bu hafta 500 kalori açık ver.",
        "Kilo vermen gerekiyor.",
        "Bir enfeksiyon geçiriyor olabilirsin."
    ])
    func blocksUnsafeText(_ text: String) {
        #expect(!SafetyFilter.isSafe(text), "engellenmeliydi: \(text)")
    }

    @Test("Türkçe ekler engellemeyi atlatamaz")
    func stemsSurviveSuffixes() {
        // "ilaç" → "ilacı", "ilaçları"; kök eşleşmesi bunları da yakalamalı.
        #expect(!SafetyFilter.isSafe("Kullandığın ilaçları bırakabilirsin."))
        #expect(!SafetyFilter.isSafe("Takviyeni sabah al."))
    }

    // MARK: - Must survive

    @Test("Zenithium'un kendi dürüst cümleleri geçer", arguments: [
        "Toparlanma 61 — son yedi günün ortalamasının 8 puan altında.",
        "Hastalık kaydettiğin günlerde HRV ortalaman 9 ms düşük çıktı.",
        "Ferritin 22 ng/mL — laboratuvarın referans aralığının altında.",
        "Bu değeri hekimine göster. Zenithium ne anlama geldiğini söyleyemez.",
        "Dün 14.2 zorlanma yaptın. Bugünün tavanı 11.8.",
        "Kuadriseps %64 hazır — vücudundaki en yorgun grup."
    ])
    func allowsSafeText(_ text: String) {
        #expect(SafetyFilter.isSafe(text), "geçmeliydi: \(text)")
    }

    /// The journal has an `illness` behaviour the user logs themselves, so the *word* has
    /// to be sayable. Only the claim is banned.
    @Test("Günlükteki hastalık davranışı adı yasak değil")
    func illnessBehaviourNameIsAllowed() {
        #expect(SafetyFilter.isSafe(JournalBehavior.illness.displayName))
        #expect(!SafetyFilter.isSafe("Bugün hastasın."))
    }

    @Test("Kısa kökler yanlışlıkla eşleşmez")
    func shortStemsDoNotOverMatch() {
        // "doz" üç harf, yalnızca tam eşleşir — "dozer" gibi bir kelimeyi yakalamamalı.
        #expect(SafetyFilter.isSafe("Dozerle kazı yapıldı."))
        #expect(!SafetyFilter.isSafe("Günlük doz 5 mg."))
    }

    // MARK: - Briefings

    @Test("Tek bir ihlal tüm briefingi geri düşürür")
    func oneViolationDropsWholeBriefing() {
        let fallback = Briefing(
            headline: "Toparlanma 61.",
            body: "Bunu en çok uykun belirledi.",
            points: [],
            requiresClinicianPrompt: false,
            source: .deterministic
        )
        let unsafe = Briefing(
            headline: "Toparlanma 61.",
            body: "Bunu en çok uykun belirledi.",
            points: ["Demir takviyesi almalısın."],
            requiresClinicianPrompt: false,
            source: .onDeviceModel
        )
        #expect(SafetyFilter.sanitized(unsafe, fallback: fallback) == fallback)
    }

    @Test("Temiz briefing olduğu gibi geçer")
    func cleanBriefingPasses() {
        let fallback = Briefing(
            headline: "A", body: "B", points: [], requiresClinicianPrompt: false, source: .deterministic
        )
        let clean = Briefing(
            headline: "Toparlanma 61 — dünden 8 puan düşük.",
            body: "Bunu en çok taban çizginin altındaki HRV belirledi.",
            points: ["Dün 14.2 zorlanma yaptın."],
            requiresClinicianPrompt: false,
            source: .onDeviceModel
        )
        #expect(SafetyFilter.sanitized(clean, fallback: fallback) == clean)
    }
}
