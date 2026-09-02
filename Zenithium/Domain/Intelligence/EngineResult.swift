//
//  EngineResult.swift
//  Zenithium
//
//  The first-class result container for every physiological engine.
//  In Zenithium, an engine never produces a bare number without explaining its confidence,
//  underlying evidence graph, physiological assumptions, and deterministic calculation trace.
//

import Foundation

/// The epistemic confidence level of an engine calculation.
enum ConfidenceRating: String, Sendable, Codable, CaseIterable {
    /// Insufficient data to form a reliable physiological conclusion.
    case insufficient
    /// Minimum threshold met, but subject to high variance or limited baseline.
    case low
    /// Standard confidence with verified baseline and reliable sensor coverage.
    case moderate
    /// High-density multi-sensor verification over a mature physiological baseline.
    case high

    var displayName: String {
        switch self {
        case .insufficient: return "Yetersiz"
        case .low: return "Düşük"
        case .moderate: return "Orta"
        case .high: return "Yüksek"
        }
    }
}

/// A quantified confidence score between 0.0 and 1.0 with a categorical rating.
struct ConfidenceScore: Sendable, Equatable, Codable {
    /// Normalized value in range [0.0, 1.0].
    let value: Double
    /// Categorical confidence level for UX decision gating.
    let rating: ConfidenceRating
    /// Concrete physiological reasons explaining any confidence reduction.
    let penaltyReasons: [String]

    init(value: Double, penaltyReasons: [String] = []) {
        let clamped = MathSupport.clamp(value, 0.0, 1.0)
        self.value = clamped
        self.penaltyReasons = penaltyReasons

        switch clamped {
        case ..<0.30:
            self.rating = .insufficient
        case 0.30..<0.60:
            self.rating = .low
        case 0.60..<0.85:
            self.rating = .moderate
        default:
            self.rating = .high
        }
    }

    static let zero = ConfidenceScore(value: 0.0, penaltyReasons: ["Veri bulunamadı"])
    static let full = ConfidenceScore(value: 1.0)
}

/// A single piece of evidentiary data supporting an engine conclusion.
struct EvidenceNode: Sendable, Equatable, Identifiable, Codable {
    let id: UUID
    /// The sensor or domain category that supplied the evidence.
    let sourceCategory: String
    /// Human-readable description of what was observed (e.g. "Son 14 günlük HRV ortalaması: 58 ms").
    let summary: String
    /// Relative weight of this evidence node in the final decision [0.0 ... 1.0].
    let weight: Double
    /// Observation timestamp or end of observation window.
    let timestamp: Date
    /// Number of raw samples supporting this observation.
    let sampleCount: Int

    init(
        id: UUID = UUID(),
        sourceCategory: String,
        summary: String,
        weight: Double = 1.0,
        timestamp: Date,
        sampleCount: Int = 1
    ) {
        self.id = id
        self.sourceCategory = sourceCategory
        self.summary = summary
        self.weight = MathSupport.clamp(weight, 0.0, 1.0)
        self.timestamp = timestamp
        self.sampleCount = sampleCount
    }
}

/// Known physiological boundary or data limitation affecting this calculation.
struct ScientificLimitation: Sendable, Equatable, Identifiable, Codable {
    let id: UUID
    /// Short identifier for the limitation (e.g. "NORM-UNVERIFIED", "TEMPERATURE-UNAVAILABLE").
    let code: String
    /// Clear, non-technical explanation for the athlete.
    let explanation: String
    /// Whether this limitation prevents actionable recommendations.
    let isBlocking: Bool

    init(
        id: UUID = UUID(),
        code: String,
        explanation: String,
        isBlocking: Bool = false
    ) {
        self.id = id
        self.code = code
        self.explanation = explanation
        self.isBlocking = isBlocking
    }
}

/// The unified container wrapping any engine output with full epistemic transparency.
struct EngineResult<Value: Sendable & Equatable>: Sendable, Equatable {
    /// The primary computed physiological output.
    let value: Value
    /// Quantified confidence in the accuracy and applicability of the result.
    let confidence: ConfidenceScore
    /// The graph of evidence supporting this outcome.
    let evidence: [EvidenceNode]
    /// Documented scientific limitations and sensor caveats.
    let limitations: [ScientificLimitation]
    /// Deterministic explanation log tracing how this outcome was reached.
    let calculationSteps: [String]

    var isActionable: Bool {
        confidence.rating != .insufficient && !limitations.contains { $0.isBlocking }
    }

    init(
        value: Value,
        confidence: ConfidenceScore,
        evidence: [EvidenceNode] = [],
        limitations: [ScientificLimitation] = [],
        calculationSteps: [String] = []
    ) {
        self.value = value
        self.confidence = confidence
        self.evidence = evidence
        self.limitations = limitations
        self.calculationSteps = calculationSteps
    }

    /// Transforms the wrapped value while preserving epistemic metadata.
    func map<T: Sendable & Equatable>(_ transform: (Value) -> T) -> EngineResult<T> {
        EngineResult<T>(
            value: transform(value),
            confidence: confidence,
            evidence: evidence,
            limitations: limitations,
            calculationSteps: calculationSteps
        )
    }
}

extension EngineResult: Codable where Value: Codable {}
