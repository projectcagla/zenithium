//
//  HybridEngineTests.swift
//  ZenithiumTests
//
//  Hibrit motor. Sayılar bağımsız olarak doğrulandı.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Hybrid engine")
struct HybridEngineTests {

    private let start = iso("2025-09-14T09:00:00Z")

    /// Beş turluk bir simülasyon: koşular yavaşlıyor, sled push orantısız uzun sürüyor.
    private func sampleSegments() -> [HybridSegment] {
        let runs: [Double] = [240, 260, 265, 270, 275]
        let transitions: [Double] = [30, 35, 40, 45, 50]
        let stations: [Double] = [180, 260, 200, 200, 160]
        let order = HyroxStation.allCases.sorted { $0.order < $1.order }

        var segments: [HybridSegment] = []
        var cursor = start

        for index in 0..<5 {
            let runEnd = cursor.addingTimeInterval(runs[index])
            segments.append(
                HybridSegment(
                    id: UUID(),
                    kind: .run(distanceMeters: 1000, roundIndex: index + 1),
                    interval: DateInterval(start: cursor, end: runEnd),
                    averageHeartRate: 165,
                    peakHeartRate: 178
                )
            )
            cursor = runEnd

            let transitionEnd = cursor.addingTimeInterval(transitions[index])
            segments.append(
                HybridSegment(
                    id: UUID(),
                    kind: .transition,
                    interval: DateInterval(start: cursor, end: transitionEnd),
                    averageHeartRate: nil,
                    peakHeartRate: nil
                )
            )
            cursor = transitionEnd

            let stationEnd = cursor.addingTimeInterval(stations[index])
            segments.append(
                HybridSegment(
                    id: UUID(),
                    kind: .station(order[index]),
                    interval: DateInterval(start: cursor, end: stationEnd),
                    averageHeartRate: 172,
                    peakHeartRate: 184
                )
            )
            cursor = stationEnd
        }
        return segments
    }

    private func analyse(freshPace: Double? = nil) -> HybridSessionOutput {
        HybridEngine.analyse(
            HybridSessionInput(
                segments: sampleSegments(),
                freshPaceSecondsPerKilometre: freshPace,
                restingHeartRate: 50,
                maxHeartRate: 190,
                performedAt: start
            )
        )
    }

    // MARK: - Kompanse koşu

    @Test("Kompanse koşu cezası ilk turdan türetilir")
    func compromisedPenaltyFromFirstRound() throws {
        let output = analyse()
        let compromised = try #require(output.compromisedRunning)

        expectClose(compromised.referencePaceSecondsPerKilometre, 240, tolerance: 1e-9, "referans")
        expectClose(compromised.compromisedPaceSecondsPerKilometre, 267.5, tolerance: 1e-9, "kompanse ort.")
        expectClose(compromised.penalty, 0.114583, tolerance: 0.000005, "ceza")
        #expect(compromised.referenceWasDerivedFromFirstRound)
    }

    @Test("Dışarıdan taze tempo verilince bütün turlar kompanse sayılır")
    func externalFreshPaceIncludesEveryRound() throws {
        let output = analyse(freshPace: 235)
        let compromised = try #require(output.compromisedRunning)

        // Ortalama artık beş turun tamamı: (240+260+265+270+275)/5 = 262
        expectClose(compromised.compromisedPaceSecondsPerKilometre, 262, tolerance: 1e-9, "kompanse ort.")
        expectClose(compromised.penalty, (262 - 235) / 235, tolerance: 1e-9, "ceza")
        #expect(!compromised.referenceWasDerivedFromFirstRound)
    }

    @Test("Bozulma eğimi tur başına yavaşlamayı verir")
    func degradationSlope() throws {
        let compromised = try #require(analyse().compromisedRunning)
        expectClose(compromised.degradationPerRound, 8.0, tolerance: 1e-9, "sn/km/tur")
    }

    @Test("Tek koşuyla ceza hesaplanmaz")
    func singleRunProducesNoPenalty() {
        let single = [
            HybridSegment(
                id: UUID(),
                kind: .run(distanceMeters: 1000, roundIndex: 1),
                interval: DateInterval(start: start, end: start.addingTimeInterval(240)),
                averageHeartRate: nil,
                peakHeartRate: nil
            )
        ]
        let output = HybridEngine.analyse(
            HybridSessionInput(
                segments: single,
                freshPaceSecondsPerKilometre: nil,
                restingHeartRate: 50,
                maxHeartRate: 190,
                performedAt: start
            )
        )
        #expect(output.compromisedRunning == nil)
    }

    // MARK: - Roxzone

    @Test("Roxzone toplamı ve payı")
    func roxzone() {
        let output = analyse()
        expectClose(output.roxzoneSeconds, 200, tolerance: 1e-9, "geçiş toplamı")
        expectClose(output.totalDurationSeconds, 2510, tolerance: 1e-9, "toplam süre")
        expectClose(output.roxzoneShare, 0.079681, tolerance: 0.000005, "geçiş payı")
    }

    @Test("Koşu ve istasyon toplamları ayrı tutulur")
    func runAndStationTotals() {
        let output = analyse()
        expectClose(output.totalRunSeconds, 1310, tolerance: 1e-9, "koşu")
        expectClose(output.totalStationSeconds, 1000, tolerance: 1e-9, "istasyon")
    }

    // MARK: - İstasyonlar

    @Test("En zayıf istasyon, en uzun süren değil, referansından en çok sapan")
    func weakestStationIsRelativeNotAbsolute() {
        let output = analyse()
        // Sled push 260 sn ile en uzun *ve* referansından en çok sapan.
        #expect(output.weakestStation == .sledPush)

        // Burpee 200 sn — sled pull ile aynı süre, ama referans payı daha yüksek olduğu için
        // sapması daha düşük. Mutlak süreye bakan bir model ikisini eşit sayardı.
        let burpee = output.stationSplits.first { $0.station == .burpeeBroadJump }
        let sledPull = output.stationSplits.first { $0.station == .sledPull }
        #expect((burpee?.deviationFromReference ?? 0) < (sledPull?.deviationFromReference ?? 0))
    }

    @Test("İstasyon payları toplamda bire yakınsar")
    func stationSharesSumToOne() {
        let output = analyse()
        expectClose(
            output.stationSplits.map(\.shareOfStationTime).reduce(0, +),
            1.0,
            tolerance: 1e-9,
            "pay toplamı"
        )
    }

    @Test("Kas : kardiyo oranı")
    func systemRatio() throws {
        let output = analyse()
        let ratio = try #require(output.muscularToCardiovascularRatio)
        // Kas: sled push 260 + sled pull 200 = 460. Kardiyo: ski 180 + row 160 = 340.
        expectClose(ratio, 1.352941, tolerance: 0.000005, "oran")
    }

    @Test("İstasyonların baskın sistemleri doğru sınıflandırılmış")
    func dominantSystems() {
        #expect(HyroxStation.skiErg.dominantSystem == .cardiovascular)
        #expect(HyroxStation.rowing.dominantSystem == .cardiovascular)
        #expect(HyroxStation.sledPush.dominantSystem == .muscular)
        #expect(HyroxStation.farmersCarry.dominantSystem == .muscular)
        #expect(HyroxStation.wallBalls.dominantSystem == .mixed)
    }

    @Test("Referans paylar toplamda bire yakın")
    func referenceSharesAreCoherent() {
        let total = HybridEngine.referenceStationShare.values.reduce(0, +)
        expectClose(total, 1.0, tolerance: 0.001, "referans pay toplamı")
        #expect(HybridEngine.referenceStationShare.count == HyroxStation.allCases.count)
    }

    // MARK: - Kas yükü

    @Test("Her istasyon kendi kas satırını yükler")
    func muscleImpactsPerStation() {
        let output = analyse()
        let impacts = HybridEngine.muscleImpacts(
            for: output,
            sessionIdentifier: UUID(),
            performedAt: start,
            sessionLoad: 60
        )
        #expect(impacts.count == 5)

        // Sled push quads yükler, sled pull lats. İkisini aynı satıra koymak yanlış olurdu.
        let push = impacts.first { if case .hybridStation(_, let s) = $0.source { return s == .sledPush } else { return false } }
        let pull = impacts.first { if case .hybridStation(_, let s) = $0.source { return s == .sledPull } else { return false } }
        #expect((push?.involvement[.quads] ?? 0) > 0.7)
        #expect((pull?.involvement[.lats] ?? 0) > 0.7)
        #expect(push?.involvement[.lats] == nil)
    }

    @Test("İstasyon kas satırları aralıkta")
    func stationInvolvementRowsInRange() {
        for station in HyroxStation.allCases {
            let row = MuscleInvolvementMatrix.involvement(for: station)
            #expect(!row.isEmpty, "\(station.rawValue) satırı boş olmamalı")
            for (muscle, value) in row {
                #expect(value > 0 && value <= 1, "\(station.rawValue) → \(muscle.rawValue)")
            }
        }
    }

    // MARK: - Yönlendirme

    @Test("Yönlendirme en büyük sorunu adlandırır ve antrenman dilinde kalır")
    func guidanceNamesTheBiggestProblem() {
        let guidance = HybridEngine.guidance(for: analyse())
        #expect(guidance.contains("kompanse"))
        // §12: sağlık iddiası yok.
        #expect(!guidance.lowercased().contains("sakat"))
        #expect(!guidance.lowercased().contains("hastalık"))
    }

    @Test("Boş seans çökmez")
    func emptySession() {
        let output = HybridEngine.analyse(
            HybridSessionInput(
                segments: [],
                freshPaceSecondsPerKilometre: nil,
                restingHeartRate: 50,
                maxHeartRate: 190,
                performedAt: start
            )
        )
        #expect(output.totalDurationSeconds == 0)
        #expect(output.compromisedRunning == nil)
        #expect(output.weakestStation == nil)
        #expect(output.roxzoneShare == 0)
    }
}
