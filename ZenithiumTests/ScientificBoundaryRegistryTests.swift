//
//  ScientificBoundaryRegistryTests.swift
//  ZenithiumTests
//
//  Tests for ScientificBoundaryRegistry, disclaimers, and physiological models.
//

import Foundation
import Testing
@testable import Zenithium

@Suite("Scientific boundary registry and disclaimers")
struct ScientificBoundaryRegistryTests {

    @Test("All registered boundaries carry valid citations and disclaimers")
    func registeredBoundariesAreValid() {
        for (key, boundary) in ScientificBoundaryRegistry.boundaries {
            #expect(!boundary.id.isEmpty)
            #expect(!boundary.physiologicalModel.isEmpty)
            #expect(!boundary.primaryCitation.isEmpty)
            #expect(!boundary.documentedLimitations.isEmpty)
            #expect(SafetyFilter.isSafe(boundary.nonCausalityDisclaimer), "\(key)")
        }
    }

    @Test("EngineResult maps wrapped value while preserving epistemic metadata")
    func engineResultMapping() {
        let original = EngineResult<Int>(
            value: 42,
            confidence: ConfidenceScore(value: 0.95),
            evidence: [EvidenceNode(sourceCategory: "Test", summary: "Test Node", timestamp: Date())],
            limitations: [ScientificLimitation(code: "TEST-LIM", explanation: "Test limitation")],
            calculationSteps: ["Step 1", "Step 2"]
        )

        let transformed = original.map { "Value: \($0)" }
        #expect(transformed.value == "Value: 42")
        #expect(transformed.confidence == original.confidence)
        #expect(transformed.evidence == original.evidence)
        #expect(transformed.limitations == original.limitations)
        #expect(transformed.calculationSteps == original.calculationSteps)
        #expect(transformed.isActionable)
    }
}
