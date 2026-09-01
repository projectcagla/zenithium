//
//  FoundationModelNarrator.swift
//  Zenithium
//
//  The optional Apple Foundation Models layer. Faz 24.
//
//  ASSUMPTION AI-1: this file is compiled only where `FoundationModels` exists, and it has
//  never been compiled in this repository — the container has no Swift toolchain and no
//  iOS 26 SDK. It is written against the framework's documented shape. If the API differs,
//  the failure is contained to this file and the app falls back to `NarrativeEngine`, which
//  is what runs everywhere else anyway. Reversal: delete the file; nothing else references
//  its type outside `#if canImport` guards.
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
    Sen Zenithium adlı sağlık ve antrenman uygulamasının anlatıcısısın. Sana verilen
    briefing zaten doğru ve zaten hesaplanmış. Görevin onu daha akıcı bir Türkçeyle
    yeniden yazmak.

    Kesin kurallar:
    - Sana verilmeyen hiçbir sayıyı, oranı veya olguyu uydurma.
    - Teşhis koyma, hastalık adı verme, ilaç veya takviye önerme, doz söyleme.
    - Kalori, kilo veya diyet hedefi verme.
    - Kullanıcıya bir belirtiyi görmezden gelmesini asla söyleme.
    - Referans aralığı dışındaki bir kan değeri için tek söyleyeceğin şey hekime
      danışması gerektiğidir.
    - Sakin ve doğrudan yaz. Abartma, motivasyon konuşması yapma, ünlem kullanma.

    Çıktı biçimi: önce tek cümlelik başlık, sonra boş satır, sonra en fazla üç cümlelik
    gövde. Madde işareti kullanma.
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
        var lines: [String] = []
        lines.append("Başlık: \(briefing.headline)")
        lines.append("Gövde: \(briefing.body)")
        for point in briefing.points {
            lines.append("Destekleyici: \(point)")
        }
        lines.append("Kullanıcının merceği: \(context.lens.displayName)")
        return """
        Aşağıdaki briefingi yeniden yaz.

        \(lines.joined(separator: "\n"))
        """
    }

    /// Split the model's answer back into a headline and a body.
    ///
    /// The supporting points are *not* taken from the model. They carry the lab and
    /// correlation sentences, which are the ones with the strictest wording requirements,
    /// so they stay exactly as the engine wrote them.
    static func parse(_ text: String, from original: Briefing) -> Briefing? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let blocks = trimmed
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let headline = blocks.first else { return nil }
        let body = blocks.count > 1 ? blocks.dropFirst().joined(separator: " ") : original.body

        // A model that ignored the format and returned one long paragraph is not usable as
        // a headline, so the original wins rather than truncating mid-thought.
        guard headline.count <= 160 else { return nil }

        return Briefing(
            headline: headline,
            body: body,
            points: original.points,
            requiresClinicianPrompt: original.requiresClinicianPrompt,
            source: .onDeviceModel
        )
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
