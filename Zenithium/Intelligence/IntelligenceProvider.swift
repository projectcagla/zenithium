//
//  IntelligenceProvider.swift
//  Zenithium
//
//  Who writes the briefing. Faz 24.
//
//  Two layers, and the order matters. `NarrativeEngine` decides what today is about and
//  writes a correct briefing. Only then, and only if the device can, a language model is
//  asked to say the same thing more naturally. The model never chooses the facts, never
//  sees a raw health sample, and never gets the last word — `SafetyFilter` does.
//
//  If every model layer is unavailable, which is the case on most devices, nothing is
//  missing from the product. That is the design, not a compromise.
//

import Foundation

/// Whether a language-model layer can run on this device.
enum IntelligenceAvailability: Sendable, Equatable, Hashable {

    /// A model is ready.
    case available

    /// No model layer; the deterministic narrator is doing the work.
    case deterministicOnly(reason: String)

    var hasModel: Bool { self == .available }
}

/// Anything that can turn a context into a briefing.
protocol IntelligenceProviding: Sendable {

    func availability() async -> IntelligenceAvailability

    func briefing(for context: BriefingContext) async -> Briefing
}

/// The rule-based narrator, wrapped as a provider. Always available, always correct.
struct DeterministicNarrator: IntelligenceProviding {

    func availability() async -> IntelligenceAvailability {
        .deterministicOnly(reason: "Cihaz içi dil modeli kullanılmıyor.")
    }

    func briefing(for context: BriefingContext) async -> Briefing {
        NarrativeEngine.briefing(for: context)
    }
}

/// Uses the on-device model when there is one, and the deterministic narrator otherwise.
///
/// Every path through this type ends in a briefing. There is no error case and no loading
/// failure the user can see: the fallback is not an error state, it is the normal state on
/// most hardware.
struct AdaptiveNarrator: IntelligenceProviding {

    private let deterministic = DeterministicNarrator()

    init() {}

    func availability() async -> IntelligenceAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await FoundationModelNarrator.availability()
        }
        return .deterministicOnly(reason: "Cihaz içi dil modeli iOS 26 gerektiriyor.")
        #else
        return .deterministicOnly(reason: "Bu sürüm cihaz içi dil modeli olmadan derlendi.")
        #endif
    }

    func briefing(for context: BriefingContext) async -> Briefing {
        // The deterministic briefing is produced first, unconditionally. It is both the
        // fallback and the model's source material, so there is never a moment where the
        // app has nothing to show.
        let baseline = NarrativeEngine.briefing(for: context)

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard case .available = await FoundationModelNarrator.availability() else { return baseline }
            guard let rewritten = await FoundationModelNarrator.rephrase(baseline, context: context) else {
                return baseline
            }
            return SafetyFilter.sanitized(rewritten, fallback: baseline)
        }
        #endif

        return baseline
    }
}
