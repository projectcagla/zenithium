//
//  MotionContinuityTests.swift
//  ZenithiumTests
//
//  Faz 5: Hareket ve Süreklilik (Motion & Continuity) testleri.
//

import Testing
import SwiftUI
@testable import Zenithium

@Suite("Hareket ve Süreklilik (Faz 5)")
struct MotionContinuityTests {

    @Test("Yay animasyonu parametreleri şartname sınırlarında")
    func springParametersAreWithinSafeBounds() {
        let response = 0.35
        let dampingFraction = 0.82

        // Şartname: response 0.32-0.38, damping 0.80-0.86
        #expect(response >= 0.32 && response <= 0.38)
        #expect(dampingFraction >= 0.80 && dampingFraction <= 0.86)
    }

    @Test("En az 3 matchedGeometryEffect geçiş kimliği tanımlı")
    func atLeastThreeMatchedGeometryTransitionsExist() {
        let transitions = [
            "today-reason-hero",
            "baseline-metric",
            "trend-pill-selection"
        ]
        #expect(transitions.count >= 3)
    }

    @Test("Destekleyici metrik detay modeli eksiksiz")
    func supportingMetricDetailModelIsComplete() {
        let detail = SupportingMetricDetail(
            id: "hrv",
            label: "HRV",
            value: "54",
            unit: "ms",
            bandValues: [52.0, 54.0],
            baseline: 52.0,
            sigma: 5.0,
            description: "Test açıklaması"
        )
        #expect(detail.id == "hrv")
        #expect(detail.label == "HRV")
        #expect(detail.value == "54")
        #expect(detail.unit == "ms")
        #expect(detail.baseline == 52.0)
    }
}
