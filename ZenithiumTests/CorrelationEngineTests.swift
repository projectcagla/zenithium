//
//  CorrelationEngineTests.swift
//  ZenithiumTests
//
//  Korelasyon motoru. Sayılar bağımsız olarak doğrulandı.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Correlation engine")
struct CorrelationEngineTests {

    private func observations(with: [Double], without: [Double]) -> [CorrelationObservation] {
        with.map { CorrelationObservation(behaviorLogged: true, value: $0) }
            + without.map { CorrelationObservation(behaviorLogged: false, value: $0) }
    }

    @Test("Ortalama farkı, güven aralığı ve etki büyüklüğü")
    func computesDifferenceAndInterval() throws {
        let result = try #require(
            CorrelationEngine.analyse(
                behavior: .alcohol,
                outcome: .recovery,
                observations: observations(
                    with: [60, 62, 58, 61, 59, 63],
                    without: [70, 72, 68, 71, 69, 73]
                )
            )
        )

        expectClose(result.meanWithBehavior, 60.5, tolerance: 1e-9, "davranışlı ortalama")
        expectClose(result.meanWithoutBehavior, 70.5, tolerance: 1e-9, "davranışsız ortalama")
        expectClose(result.difference, -10.0, tolerance: 1e-9, "fark")
        expectClose(result.confidenceLower, -12.1170, tolerance: 0.001, "CI alt")
        expectClose(result.confidenceUpper, -7.8830, tolerance: 0.001, "CI üst")
        expectClose(result.cohensD, -5.3452, tolerance: 0.001, "Cohen d")
        #expect(result.isConsistent)
        #expect(result.magnitude == .large)
        #expect(result.sampleWithBehavior == 6)
        #expect(result.sampleWithoutBehavior == 6)
    }

    @Test("Sıfırı kapsayan aralık tutarlı sayılmaz")
    func overlappingIntervalIsNotConsistent() throws {
        // Aynı dağılım, yalnızca gürültü — fark olmaması gereken durum.
        let result = try #require(
            CorrelationEngine.analyse(
                behavior: .meditation,
                outcome: .recovery,
                observations: observations(
                    with: [65, 70, 60, 68, 62, 71],
                    without: [66, 69, 61, 67, 63, 70]
                )
            )
        )
        #expect(!result.isConsistent)
        // "Tutarlı değil" ile "etki yok" farklı şeyler; motor ikincisini iddia etmiyor.
        #expect(result.totalSample == 12)
    }

    @Test("Altı gözlemin altındaki grup sonuç üretmez")
    func requiresMinimumSamples() {
        for count in 0..<CorrelationEngine.minimumSamplesPerGroup {
            let result = CorrelationEngine.analyse(
                behavior: .alcohol,
                outcome: .recovery,
                observations: observations(
                    with: Array(repeating: 60.0, count: count),
                    without: Array(repeating: 70.0, count: 10)
                )
            )
            #expect(result == nil, "\(count) gözlemle sonuç üretilmemeli")
        }
        #expect(
            CorrelationEngine.analyse(
                behavior: .alcohol,
                outcome: .recovery,
                observations: observations(
                    with: Array(repeating: 60.0, count: 6),
                    without: Array(repeating: 70.0, count: 6)
                )
            ) != nil
        )
    }

    @Test("Yön, ölçümün doğasına göre okunur")
    func directionRespectsOutcome() throws {
        // Dinlenme nabzında düşüş kullanıcının lehinedir, toparlanmada yükseliş.
        let restingHR = try #require(
            CorrelationEngine.analyse(
                behavior: .meditation,
                outcome: .restingHeartRate,
                observations: observations(
                    with: [48, 49, 47, 50, 48, 49],
                    without: [54, 55, 53, 56, 54, 55]
                )
            )
        )
        #expect(restingHR.difference < 0)
        #expect(restingHR.movesUpward, "düşen dinlenme nabzı lehte sayılmalı")

        let recovery = try #require(
            CorrelationEngine.analyse(
                behavior: .meditation,
                outcome: .recovery,
                observations: observations(
                    with: [70, 72, 71, 73, 69, 74],
                    without: [60, 62, 61, 63, 59, 64]
                )
            )
        )
        #expect(recovery.difference > 0)
        #expect(recovery.movesUpward)
    }

    @Test("Sıralama tutarlı olanları öne, sonra etkiye göre koyar")
    func rankingOrdersConsistentFirst() {
        let strong = observations(with: [50, 52, 48, 51, 49, 53], without: [70, 72, 68, 71, 69, 73])
        let noisy = observations(with: [60, 75, 50, 80, 55, 70], without: [62, 74, 52, 78, 57, 68])

        let ranked = CorrelationEngine.rank(
            outcome: .recovery,
            observationsByBehavior: [.alcohol: strong, .travel: noisy]
        )
        #expect(ranked.count == 2)
        #expect(ranked[0].behavior == .alcohol)
        #expect(ranked[0].isConsistent)
    }

    @Test("Özet cümlesi gözlem sayısını her zaman taşır")
    func summaryAlwaysCitesSampleSize() throws {
        let result = try #require(
            CorrelationEngine.analyse(
                behavior: .alcohol,
                outcome: .recovery,
                observations: observations(
                    with: [60, 62, 58, 61, 59, 63],
                    without: [70, 72, 68, 71, 69, 73]
                )
            )
        )
        let summary = CorrelationEngine.summary(for: result)
        #expect(summary.contains("12 gözlem"))
        // §12 ve yol haritası kuralı 5: nedensellik iddia edilmez.
        #expect(!summary.lowercased().contains("sebep"))
        #expect(!summary.lowercased().contains("neden ol"))
    }

    @Test("Etki büyüklüğü eşikleri Cohen'in sınırlarında")
    func effectMagnitudeThresholds() {
        #expect(EffectMagnitude.magnitude(forCohensD: 0.1) == .negligible)
        #expect(EffectMagnitude.magnitude(forCohensD: 0.3) == .small)
        #expect(EffectMagnitude.magnitude(forCohensD: 0.6) == .medium)
        #expect(EffectMagnitude.magnitude(forCohensD: 1.2) == .large)
        // İşaret büyüklüğü etkilemez.
        #expect(EffectMagnitude.magnitude(forCohensD: -1.2) == .large)
    }

    @Test("Sıfır varyanslı gruplar çökmez")
    func handlesZeroVariance() {
        let result = CorrelationEngine.analyse(
            behavior: .illness,
            outcome: .recovery,
            observations: observations(
                with: Array(repeating: 50.0, count: 6),
                without: Array(repeating: 70.0, count: 6)
            )
        )
        // Havuzlanmış sapma sıfır olduğunda d sıfırlanır, ama sonuç yine üretilir ve fark
        // doğru kalır — çökmemek burada asıl test.
        #expect(result != nil)
        if let result {
            expectClose(result.difference, -20, tolerance: 1e-9, "fark")
            #expect(result.cohensD.isFinite)
        }
    }
}
