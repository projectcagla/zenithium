//
//  ClinicalContext.swift
//  Zenithium
//
//  Epistemic clinical context affecting decision confidence without diagnosing. Spec §12.
//

import Foundation

struct ClinicalContext: Sendable, Equatable, Codable {
    /// Karar güvenine uygulanacak çarpan, (0, 1] aralığında.
    let confidenceMultiplier: Double
    /// ConfidenceScore.penaltyReasons'a eklenecek gerekçeler.
    let penaltyReasons: [String]
    /// EngineResult.limitations'a katılacak sınırlar.
    let limitations: [ScientificLimitation]
    /// Karar izine girecek kanıt düğümleri.
    let evidence: [EvidenceNode]
    /// HRV türevli toparlanma skorlaması geçersiz mi (yalnızca AF durumu).
    let suppressesHRVRecovery: Bool

    init(
        confidenceMultiplier: Double = 1.0,
        penaltyReasons: [String] = [],
        limitations: [ScientificLimitation] = [],
        evidence: [EvidenceNode] = [],
        suppressesHRVRecovery: Bool = false
    ) {
        self.confidenceMultiplier = MathSupport.clamp(confidenceMultiplier, 0.0, 1.0)
        self.penaltyReasons = penaltyReasons
        self.limitations = limitations
        self.evidence = evidence
        self.suppressesHRVRecovery = suppressesHRVRecovery
    }

    static let neutral = ClinicalContext(
        confidenceMultiplier: 1.0,
        penaltyReasons: [],
        limitations: [],
        evidence: [],
        suppressesHRVRecovery: false
    )
}
