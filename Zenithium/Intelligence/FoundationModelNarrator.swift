//
//  FoundationModelNarrator.swift
//  Zenithium
//
//  The optional Apple Foundation Models layer. Faz 24.
//
//  Compiled and weak-linked with FoundationModels on iOS 26+. Older systems use the
//  deterministic narrator. Numerical body and evidence always stay untouched.
//
//  What the model is and is not allowed to do:
//
//  * It receives a briefing that is **already correct** and already safe, plus a short
//    structured summary. It is asked to rewrite, not to conclude.
//  * It receives no raw health samples, no dates of birth, no identifiers — only numbers
//    that are already on screen.
//  * Its output goes through `SafetyFilter` before anything is displayed.
//  * It runs on device. There is no network call here, which is the reason this is the only
//    model layer Zenithium will ever ship.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
enum FoundationModelNarrator {

    /// Instructions the session is created with. Constraints first, because they are the
    /// part that must survive a long context.
    static let instructions = """
    Zenithium için sana verilen başlığı aynı anlamı koruyarak sade Türkçeyle yeniden yaz.
    Yalnızca tek kısa cümle döndür. Gövde, açıklama veya öneri ekleme.
    Rakam, sayı sözcüğü, miktar, oran, süre, karşılaştırma veya yeni sağlık iddiası üretme.
    Tanı, hastalık, ilaç, takviye, kalori, kilo ve diyet hakkında yorum yapma.
    Anlamı koruyamıyorsan verilen başlığı aynen döndür.
    """

    /// Whether the system model is ready on this device.
    static func availability() async -> IntelligenceAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .deterministicOnly(reason: description(of: reason))
        @unknown default:
            return .deterministicOnly(reason: "Cihaz içi dil modeli kullanılamıyor.")
        }
    }

    /// Ask the model to rewrite a briefing. Returns `nil` on any failure, which the caller
    /// reads as "use the deterministic one".
    static func rephrase(_ briefing: Briefing, context: BriefingContext) async -> Briefing? {
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt(for: briefing, context: context))
            return parse(response.content, from: briefing)
        } catch {
            ZenithiumLog.intelligence.debug("Cihaz içi model yanıt veremedi, belirlenimci metne düşüldü.")
            return nil
        }
    }

    /// The prompt: the briefing to rewrite, and nothing the user cannot already see.
    static func prompt(for briefing: Briefing, context: BriefingContext) -> String {
        // The model never sees quantitative body text and cannot author it.
        briefing.headline
    }

    static func parse(_ text: String, from original: Briefing) -> Briefing? {
        let headline = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headline.isEmpty, headline.count <= 160, !headline.contains("\n"),
              NarrationGuard.containsNoQuantity(headline) else { return nil }
        return Briefing(headline: headline, body: original.body, points: original.points,
            requiresClinicianPrompt: original.requiresClinicianPrompt, source: .onDeviceModel)
    }

    private static func description(of reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "Bu cihaz Apple Intelligence desteklemiyor."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence kapalı. Ayarlar'dan açabilirsin."
        case .modelNotReady:
            return "Cihaz içi model henüz indirilmedi."
        @unknown default:
            return "Cihaz içi dil modeli kullanılamıyor."
        }
    }
}
#endif
