//
//  ScientificBoundaryTests.swift
//  ZenithiumTests
//
//  The three numbers this app's credibility rests on, pinned against their sources. Adım 6.
//
//  Each of these was already documented somewhere — the strain scale's calibration anchors
//  in `StrainEngine`'s header, the cold-start gate in §4.2.4, the shape of the Minetti curve
//  in `EnduranceEngine`'s. Documented and untested is the state where a comment slowly stops
//  describing the code, which is exactly what happened to the Minetti comment: it named a
//  turning point at −10% for a curve that turns at −18.1%.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Strain scale calibration anchors")
struct StrainScaleAnchorTests {

    /// The five anchors `StrainEngine`'s header commits to, ±0.1.
    ///
    /// They are the contract between the strain number and everything downstream: the live
    /// session screen inverts this scale, the prescription engine sets a ceiling on it, and
    /// the watch draws it. A change here is a change to every one of those at once, which is
    /// why it is worth a test that fails loudly rather than a comment that quietly ages.
    @Test("TRIMP → zorlanma çıpaları", arguments: [
        (65.0, 7.2), (135.0, 12.3), (200.0, 15.3), (365.0, 19.0), (500.0, 20.2)
    ])
    func calibrationAnchorsHold(anchor: (trimp: Double, strain: Double)) {
        let produced = StrainScale.strain(forTRIMP: anchor.trimp)
        #expect(
            abs(produced - anchor.strain) <= 0.1,
            "TRIMP \(anchor.trimp) → \(produced), beklenen \(anchor.strain) ±0,1"
        )
    }

    @Test("Ölçek sıfırdan başlıyor ve tavanı aşmıyor")
    func theScaleIsBounded() {
        #expect(StrainScale.strain(forTRIMP: 0) == 0)
        #expect(StrainScale.strain(forTRIMP: 10_000) <= EngineConstants.Strain.scaleMax)
        #expect(StrainScale.strain(forTRIMP: -50) >= 0)
    }

    @Test("Ölçek TRIMP'te monoton artıyor")
    func theScaleIsMonotonic() {
        var previous = -1.0
        for trimp in stride(from: 0.0, through: 800.0, by: 5.0) {
            let strain = StrainScale.strain(forTRIMP: trimp)
            #expect(strain >= previous)
            previous = strain
        }
    }

    /// The inversion the live session depends on: impulse adds, strain does not.
    @Test("Ters dönüşüm çıpaları geri veriyor", arguments: [65.0, 135.0, 200.0, 365.0])
    func theInverseReturnsTheImpulse(trimp: Double) throws {
        let strain = StrainScale.strain(forTRIMP: trimp)
        let recovered = try #require(StrainScale.trimp(forStrain: strain))
        #expect(abs(recovered - trimp) < 0.001)
    }

    /// Adding two sessions' *strain* would double-count the flat part of the curve. The
    /// live session engine adds impulse instead, and this is the arithmetic that says why.
    @Test("Zorlanma toplanamaz, impuls toplanır")
    func strainDoesNotAddButImpulseDoes() throws {
        let first = StrainScale.strain(forTRIMP: 200)
        let second = StrainScale.strain(forTRIMP: 200)
        let naive = first + second

        let correct = StrainScale.strain(forTRIMP: 400)
        #expect(naive > correct, "doyan bir ölçekte toplama üstten sapmalı")
        #expect(correct < EngineConstants.Strain.scaleMax)
        // The gap is not academic: two identical hard sessions read 30.6 added naively and
        // 19.4 done correctly, and only one of those fits on a 21-point scale.
        #expect(naive - correct > 5)
    }
}

@Suite("Baseline cold start gate")
struct ColdStartGateTests {

    /// §4.2.4: below five days there is no score, whatever the numbers look like.
    ///
    /// The gate is the difference between "we do not know yet" and a confident wrong answer
    /// on somebody's first week, which is the week they decide whether to keep the app.
    @Test("Beş günün altında skor üretilmiyor", arguments: [0, 1, 2, 3, 4])
    func belowFiveDaysThereIsNoScore(days: Int) {
        let state = calibrated(days: days)
        #expect(!state.isScorable, "\(days) günle puanlanabilir görünüyor")
    }

    @Test("Beşinci günden itibaren skor üretiliyor", arguments: [5, 6, 10, 14, 30])
    func fromTheFifthDayOnwardsThereIsAScore(days: Int) {
        #expect(calibrated(days: days).isScorable)
    }

    @Test("Güven n/14 ve on dördüncü günde doyuyor")
    func confidenceSaturatesAtFourteenDays() {
        #expect(abs(calibrated(days: 5).confidence - 5.0 / 14.0) < 0.001)
        #expect(abs(calibrated(days: 10).confidence - 10.0 / 14.0) < 0.001)
        #expect(abs(calibrated(days: 13).confidence - 13.0 / 14.0) < 0.001)
        #expect(calibrated(days: 14).confidence == 1)
        #expect(calibrated(days: 40).confidence == 1)
    }

    @Test("Güven gün sayısında monoton")
    func confidenceNeverFallsAsDaysAccumulate() {
        var previous = -1.0
        for days in 0...30 {
            let confidence = calibrated(days: days).confidence
            #expect(confidence >= previous)
            previous = confidence
        }
    }

    /// Runs a baseline with `days` folded in through the real gate.
    ///
    /// Built from `BaselineSnapshot` and passed through `scoringBaseline(from:)` rather than
    /// constructing a `ScoringBaseline` directly, so the test exercises the rule instead of
    /// restating it.
    private func calibrated(days: Int) -> ScoringBaseline {
        BaselineEngine.scoringBaseline(
            from: BaselineSnapshot(
                metric: .heartRateVariability,
                mean: 55,
                variance: 64,
                sampleCount: days,
                lastUpdated: Date(timeIntervalSince1970: 1_760_000_000),
                seedValues: []
            )
        )
    }
}

@Suite("Minetti grade cost curve")
struct MinettiCurveTests {

    /// The comment said the curve turns at about −10%. It turns at −18.1%, which is where a
    /// reader looking for the braking transition should be sent.
    @Test("Eğri minimumu −%18 civarında")
    func theCurveTurnsAroundMinusEighteenPercent() {
        var minimumGradient = -0.30
        var minimumCost = Double.greatestFiniteMagnitude
        for step in 0...6_000 {
            let gradient = -0.30 + Double(step) * 0.0001
            let cost = EnduranceEngine.gradeCostRatio(gradient: gradient)
            if cost < minimumCost {
                minimumCost = cost
                minimumGradient = gradient
            }
        }
        #expect(
            (-0.21...(-0.15)).contains(minimumGradient),
            "minimum \(minimumGradient) bulundu, −0,21…−0,15 bekleniyordu"
        )
        // Descending at the cheapest gradient costs about half of level ground.
        #expect((0.45...0.55).contains(minimumCost))
    }

    @Test("Minimumun üstünde iniş ucuzluyor, altında pahalılaşıyor")
    func costFallsTowardTheMinimumAndRisesBelowIt() {
        let shallow = EnduranceEngine.gradeCostRatio(gradient: -0.05)
        let atMinimum = EnduranceEngine.gradeCostRatio(gradient: -0.18)
        let steep = EnduranceEngine.gradeCostRatio(gradient: -0.28)

        #expect(atMinimum < shallow, "iniş minimuma doğru ucuzlamalı")
        #expect(atMinimum < steep, "minimumun altında tekrar pahalılaşmalı")
    }

    @Test("Düz zemin tam olarak 1")
    func levelGroundIsExactlyOne() {
        #expect(abs(EnduranceEngine.gradeCostRatio(gradient: 0) - 1) < 1e-9)
    }

    @Test("Yokuş maliyeti eğimle monoton artıyor")
    func climbingCostRisesMonotonically() {
        var previous = 0.0
        for step in 0...30 {
            let cost = EnduranceEngine.gradeCostRatio(gradient: Double(step) * 0.01)
            #expect(cost > previous)
            previous = cost
        }
    }

    @Test("Eğim ±%30'a kırpılıyor")
    func theGradientIsClamped() {
        #expect(EnduranceEngine.gradeCostRatio(gradient: 0.90) == EnduranceEngine.gradeCostRatio(gradient: 0.30))
        #expect(EnduranceEngine.gradeCostRatio(gradient: -0.90) == EnduranceEngine.gradeCostRatio(gradient: -0.30))
    }
}

@Suite("Reference norms verification gate")
struct ReferenceNormsVerificationTests {

    /// ASSUMPTION NORM-1 was checked in Adım 6 and did not hold. Until the table is
    /// transcribed from the published PDF, the screen shows no comparison.
    @Test("Doğrulanmamış tablo ekranda karşılaştırma üretmiyor")
    func anUnverifiedTableShowsNoComparison() {
        let day = Date(timeIntervalSince1970: 1_760_000_000)
        let sample = VitalSample(sign: .vo2Max, dayStart: day, value: 44)
        let readings = [
            VitalReading(
                sign: .vo2Max,
                latest: sample,
                baselineMean: 43,
                baselineDeviation: 2,
                zScore: 0.5,
                history: [sample]
            )
        ]
        let characteristics = UserCharacteristics(
            dateOfBirth: Calendar(identifier: .gregorian).date(from: DateComponents(year: 1986, month: 3, day: 1)),
            biologicalSex: .male,
            maxHeartRateOverride: nil
        )
        let norm = VitalsViewModel.vo2MaxNorm(
            readings: readings,
            characteristics: characteristics,
            now: day,
            calendar: Calendar(identifier: .gregorian)
        )

        if ReferenceNorms.isPublicationVerified {
            #expect(norm != nil, "tablo doğrulandıysa karşılaştırma görünmeli")
        } else {
            #expect(norm == nil, "doğrulanmamış tablodan karşılaştırma sızıyor")
        }
    }

    /// The table was removed in v0.1 rather than shipped wrong — see `ReferenceNorms`. What
    /// survives here is the check that its absence is complete: no age, no sex and no value
    /// produces a comparison while the flag is down.
    @Test("Doğrulanmamış tablo hiçbir girdide bant üretmiyor")
    func anUnverifiedTableProducesNoBand() {
        guard !ReferenceNorms.isPublicationVerified else { return }
        #expect(ReferenceNorms.maleTreadmill.isEmpty)
        #expect(ReferenceNorms.femaleTreadmill.isEmpty)
        for age in [20, 35, 55, 75, 85] {
            #expect(ReferenceNorms.vo2MaxBand(age: age, biologicalSex: .male) == nil)
            #expect(ReferenceNorms.vo2MaxBand(age: age, biologicalSex: .female) == nil)
        }
    }

    /// The anchors the table will have to reproduce once somebody transcribes it. Recorded
    /// as a test so the next transcription is checked rather than trusted.
    @Test("Yayımlanmış çıpalar kayıtlı ve iki yayın da ayrı tutuluyor")
    func thePublishedAnchorsAreOnRecord() throws {
        let fifteen = try #require(ReferenceNorms.publishedMedians["Kaminsky 2015"])
        #expect(fifteen[20]?.male == 48.0)
        #expect(fifteen[20]?.female == 37.6)
        #expect(fifteen[70]?.male == 24.4)
        #expect(fifteen[70]?.female == 18.3)

        // The 2022 update reports a materially different figure for the same cell, which is
        // why the source has to be named alongside the numbers.
        let twentyTwo = try #require(ReferenceNorms.publishedMedians["Kaminsky 2022"])
        #expect(twentyTwo[70]?.male == 30.8)
        #expect(fifteen[70]?.male != twentyTwo[70]?.male)
    }
}
