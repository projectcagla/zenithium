//
//  DecisionTrace.swift
//  Zenithium
//
//  Deterministic decision trace modeling for athletic recommendations.
//  Replaces opaque "black-box AI" with a verifiable, auditable chain of physiological facts.
//

import Foundation

/// The primary daily athletic recommendation.
enum DecisionAction: Sendable, Equatable, Codable {
    /// Green light to train hard and exceed baseline strain.
    case push(targetStrain: Double)
    /// Standard training within maintenance load boundaries.
    case maintain(targetStrain: Double)
    /// Active recovery or rest; training load should remain minimal.
    case recover
    /// Baseline insufficient; prioritize wearing device and collecting biometric anchors.
    case calibrate
}

/// A discrete step in the deterministic decision pipeline.
struct TraceStep: Sendable, Equatable, Identifiable, Codable {
    let id: UUID
    let stepNumber: Int
    let engineName: String
    let inputDescription: String
    let outputDescription: String
    let physiologicalImpact: String

    init(
        id: UUID = UUID(),
        stepNumber: Int,
        engineName: String,
        inputDescription: String,
        outputDescription: String,
        physiologicalImpact: String
    ) {
        self.id = id
        self.stepNumber = stepNumber
        self.engineName = engineName
        self.inputDescription = inputDescription
        self.outputDescription = outputDescription
        self.physiologicalImpact = physiologicalImpact
    }
}

/// The synthesized athletic intelligence decision presented to the athlete.
struct AthleticDecision: Sendable, Equatable, Codable {
    let action: DecisionAction
    let headline: String
    let primaryRationale: String
    let suggestedActivities: [WorkoutActivity]
    let confidence: ConfidenceScore
    let evidence: [EvidenceNode]
    let traceSteps: [TraceStep]
    let limitations: [ScientificLimitation]

    init(
        action: DecisionAction,
        headline: String,
        primaryRationale: String,
        suggestedActivities: [WorkoutActivity] = [],
        confidence: ConfidenceScore,
        evidence: [EvidenceNode] = [],
        traceSteps: [TraceStep] = [],
        limitations: [ScientificLimitation] = []
    ) {
        self.action = action
        self.headline = headline
        self.primaryRationale = primaryRationale
        self.suggestedActivities = suggestedActivities
        self.confidence = confidence
        self.evidence = evidence
        self.traceSteps = traceSteps
        self.limitations = limitations
    }
}
