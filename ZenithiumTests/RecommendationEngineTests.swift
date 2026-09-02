//
//  RecommendationEngineTests.swift
//  ZenithiumTests
//
//  What the app is allowed to say, and when it must stay quiet. Faz 34.
//
//  The most important test in this file is the first one. Producing training advice on top
//  of biometrics that cannot support a recovery reading is the single most damaging thing
//  this layer could do, and it is the failure mode that arrives quietly — one rule forgets
//  the gate, and the app confidently instructs someone whose watch was on the nightstand.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Öneri motoru")
struct RecommendationEngineTests {

    // MARK: - Fixtures

    static let referenceDate = Date(timeIntervalSince1970: 1_760_000_000)

    static func quality(
        usable: Bool = true,
        confidence: Double = 1.0
    ) -> DataQualityAssessment {
        DataQualityAssessment(
            grade: usable ? .excellent : .unusable,
            wearHours: usable ? 22 : 4,
            nocturnalWearHours: usable ? 7.5 : 0.5,
            hasNocturnalHRV: usable,
            hasNocturnalRHR: usable,
            hasWristTemperature: usable,
            hasSleepStages: usable,
            confidenceFactor: confidence,
            missingSensors: usable ? [] : ["Gece HRV (Kalp Hızı Değişkenliği)"],
            qualityIssues: usable ? [] : ["Otonom sinir sistemi dengesi için gece HRV ölçümü eksik."]
        )
    }

    static func input(
        usable: Bool = true,
        confidence: Double = 1.0,
        recordedDays: Int = 60,
        recoveryScore: Double? = nil,
        recoveryBand: RecoveryBand? = nil,
        sleepDebtHours: Double? = nil,
        acwr: Double? = nil,
        vo2MaxPercentile: Double? = nil,
        socialJetlagHours: Double? = nil,
        userSex: BiologicalSexValue = .male,
        userStatus: TrainingStatus = .trained
    ) -> RecommendationInput {
        RecommendationInput(
            now: referenceDate,
            recoveryScore: recoveryScore,
            recoveryBand: recoveryBand,
            sleepDebtHours: sleepDebtHours,
            acwr: acwr,
            vo2MaxPercentile: vo2MaxPercentile,
            socialJetlagHours: socialJetlagHours,
            dataQuality: quality(usable: usable, confidence: confidence),
            calibration: CalibrationState(recordedDaysCount: recordedDays),
            userAge: 34,
            userSex: userSex,
            userStatus: userStatus
        )
    }

    // MARK: - The gate

    @Test("Veri yetersizken hiçbir öneri üretilmiyor")
    func unusableDataProducesOnlyTheMissingDataCard() {
        let results = RecommendationEngine.recommendations(
            input: Self.input(
                usable: false,
                confidence: 0.1,
                recoveryScore: 30,
                recoveryBand: .red,
                sleepDebtHours: 4,
                acwr: 1.9
            )
        )

        #expect(results.count == 1)
        #expect(results.first?.id == "measurement.dataQuality")
        #expect(results.first?.strength == .observation)
        #expect(results.first?.limitations.contains { $0.isBlocking } == true)
    }

    @Test("Eksik veri kartı ne eksik olduğunu söylüyor")
    func theMissingDataCardNamesWhatIsMissing() {
        let results = RecommendationEngine.recommendations(input: Self.input(usable: false))
        let card = results.first
        #expect(card != nil)
        #expect(card?.body.contains("Gece HRV") == true)
        #expect(card?.wouldChangeIf.isEmpty == false)
    }

    // MARK: - Universal invariants

    /// A system that cannot say what would change its mind is predicting, not advising.
    @Test("Her öneri fikrini neyin değiştireceğini söylüyor")
    func everyRecommendationSaysWhatWouldChangeIt() {
        let results = RecommendationEngine.recommendations(
            input: Self.input(
                recoveryScore: 38,
                recoveryBand: .red,
                sleepDebtHours: 2.5,
                acwr: 1.7,
                vo2MaxPercentile: 62,
                socialJetlagHours: 2.1
            )
        )
        #expect(!results.isEmpty)
        for recommendation in results {
            #expect(!recommendation.wouldChangeIf.isEmpty, "\(recommendation.id)")
        }
    }

    /// The contract that stops a copy edit from promoting an observation into an order.
    @Test("Her öneri dil sözleşmesine uyuyor")
    func everyRecommendationHonoursItsGrammar() {
        let inputs = [
            Self.input(recoveryScore: 38, recoveryBand: .red, sleepDebtHours: 3.0, acwr: 1.8,
                       vo2MaxPercentile: 40, socialJetlagHours: 2.0),
            Self.input(confidence: 0.5, recordedDays: 5, recoveryScore: 55, recoveryBand: .yellow,
                       sleepDebtHours: 1.5, acwr: 0.6),
            Self.input(confidence: 0.35, recordedDays: 2, recoveryScore: 45, recoveryBand: .yellow,
                       sleepDebtHours: 6.0, acwr: 2.4, vo2MaxPercentile: 88, socialJetlagHours: 3.3),
            Self.input(usable: false)
        ]

        for input in inputs {
            for recommendation in RecommendationEngine.recommendations(input: input) {
                #expect(
                    recommendation.honoursLanguageContract,
                    "\(recommendation.id) @ \(recommendation.strength): \(recommendation.headline)"
                )
            }
        }
    }

    @Test("Her önerinin kaynakları çözümlenebiliyor")
    func everyCitedSourceResolves() {
        let results = RecommendationEngine.recommendations(
            input: Self.input(recoveryScore: 40, recoveryBand: .red, sleepDebtHours: 2,
                              acwr: 1.6, vo2MaxPercentile: 50, socialJetlagHours: 2)
        )
        for recommendation in results {
            #expect(
                recommendation.references.count == recommendation.referenceIDs.count,
                "\(recommendation.id): kırık atıf"
            )
        }
    }

    // MARK: - Sleep debt: the rule that can reach the imperative

    @Test("Sağlam kanıt ve yüksek güven tavsiye üretiyor")
    func strongEvidenceProducesARealRecommendation() {
        let results = RecommendationEngine.recommendations(input: Self.input(sleepDebtHours: 2.0))
        let card = results.first { $0.id == "sleep.debt" }

        #expect(card?.strength == .recommendation)
        #expect(card?.disclaimerTier == .training)
        #expect(card?.headline.contains("uyu") == true)
    }

    @Test("Aynı kural düşük güvende emir kipini bırakıyor")
    func theSameRuleDropsTheImperativeWhenConfidenceFalls() {
        let weak = RecommendationEngine.recommendations(
            input: Self.input(confidence: 0.55, recordedDays: 5, sleepDebtHours: 2.0)
        ).first { $0.id == "sleep.debt" }

        #expect(weak?.strength != .recommendation)
        #expect(weak?.honoursLanguageContract == true)
        let stems = ClaimLanguage.imperativeStems(in: weak?.headline ?? "")
        #expect(stems.isEmpty)
    }

    @Test("Eşiğin altındaki uyku borcu kart üretmiyor")
    func sleepDebtBelowThresholdIsSilent() {
        let results = RecommendationEngine.recommendations(input: Self.input(sleepDebtHours: 0.4))
        #expect(!results.contains { $0.id == "sleep.debt" })
    }

    // MARK: - Autonomic: capped by what its own source argues

    /// `PLEWS-2013` argues for weekly averaging. Letting a single night license an
    /// instruction would be citing that paper against itself.
    @Test("Toparlanma kartı kaynağının kapsamıyla sınırlı")
    func theAutonomicCardIsCappedByItsOwnSource() {
        let card = RecommendationEngine.recommendations(
            input: Self.input(recoveryScore: 30, recoveryBand: .red)
        ).first { $0.id == "recovery.autonomic" }

        #expect(card != nil)
        #expect(card?.strength == .suggestion)
        #expect(card?.limitations.contains { $0.code == "SOURCE-SCOPE" } == true)
    }

    @Test("Yeşil bantta toparlanma kartı yok")
    func aGreenMorningProducesNoRecoveryCard() {
        let results = RecommendationEngine.recommendations(
            input: Self.input(recoveryScore: 82, recoveryBand: .green)
        )
        #expect(!results.contains { $0.id == "recovery.autonomic" })
    }

    // MARK: - Load ratio: where the disputed literature shows through

    @Test("Tartışmalı literatür kartı gözleme indiriyor")
    func disputedLiteratureDemotesTheCard() {
        let card = RecommendationEngine.recommendations(
            input: Self.input(acwr: 1.8)
        ).first { $0.id == "training.loadRatio" }

        #expect(card != nil)
        #expect(card?.strength == .observation)
        #expect(card?.limitations.contains { $0.code == "EVIDENCE-CONFLICT" } == true)
        #expect(card?.contradictions.isEmpty == false)
    }

    @Test("Doğrulanmamış kaynak kartta işaretleniyor")
    func anUnverifiedSourceIsSurfaced() {
        let card = RecommendationEngine.recommendations(
            input: Self.input(acwr: 1.8)
        ).first { $0.id == "training.loadRatio" }

        #expect(card?.limitations.contains { $0.code == "SOURCE-UNVERIFIED" } == true)
    }

    @Test("Normal aralıktaki yük oranı kart üretmiyor")
    func aNormalLoadRatioIsSilent() {
        let results = RecommendationEngine.recommendations(input: Self.input(acwr: 1.05))
        #expect(!results.contains { $0.id == "training.loadRatio" })
    }

    @Test("Düşük yük oranı da kart üretiyor")
    func aLightBlockAlsoProducesACard() {
        let results = RecommendationEngine.recommendations(input: Self.input(acwr: 0.6))
        #expect(results.contains { $0.id == "training.loadRatio" })
    }

    // MARK: - Observational rules stay observational

    @Test("Kesitsel referans kaydı yalnızca gözlem üretiyor")
    func crossSectionalReferenceDataStaysDescriptive() {
        let card = RecommendationEngine.recommendations(
            input: Self.input(vo2MaxPercentile: 62)
        ).first { $0.id == "measurement.cardiorespiratory" }

        #expect(card?.strength == .observation)
        #expect(card?.headline.contains("%62") == true)
    }

    @Test("Sirkadiyen kart gözlem seviyesinde kalıyor")
    func theCircadianCardStaysDescriptive() {
        let card = RecommendationEngine.recommendations(
            input: Self.input(socialJetlagHours: 2.1)
        ).first { $0.id == "circadian.socialJetlag" }

        #expect(card?.strength == .observation)
        #expect(card?.disclaimerTier == DisclaimerTier.none)
    }

    // MARK: - Population transfer reaches the cards

    @Test("Uzak popülasyon karta not olarak yansıyor")
    func aDistantPopulationLeavesANoteOnTheCard() {
        let card = RecommendationEngine.recommendations(
            input: Self.input(acwr: 1.8, userSex: .female, userStatus: .recreational)
        ).first { $0.id == "training.loadRatio" }

        #expect(card?.populationNote != nil)
        #expect(card?.confidence.penaltyReasons.isEmpty == false)
    }

    @Test("Olgunlaşmamış taban çizgisi güveni düşürüyor")
    func animmatureBaselineLowersConfidence() {
        let mature = RecommendationEngine.recommendations(
            input: Self.input(recordedDays: 60, sleepDebtHours: 2)
        ).first { $0.id == "sleep.debt" }

        let cold = RecommendationEngine.recommendations(
            input: Self.input(recordedDays: 2, sleepDebtHours: 2)
        ).first { $0.id == "sleep.debt" }

        #expect((mature?.confidence.value ?? 0) > (cold?.confidence.value ?? 1))
    }

    // MARK: - Ordering

    @Test("Kartlar güçten zayıfa sıralanıyor")
    func cardsAreOrderedByStrength() {
        let results = RecommendationEngine.recommendations(
            input: Self.input(recoveryScore: 40, recoveryBand: .red, sleepDebtHours: 2.5,
                              acwr: 1.8, vo2MaxPercentile: 55, socialJetlagHours: 2.2)
        )
        let strengths = results.map(\.strength)
        #expect(strengths == strengths.sorted(by: >))
    }

    @Test("Aynı girdi aynı çıktıyı veriyor")
    func theEngineIsDeterministic() {
        let input = Self.input(recoveryScore: 40, recoveryBand: .red, sleepDebtHours: 2.5, acwr: 1.8)
        let first = RecommendationEngine.recommendations(input: input)
        let second = RecommendationEngine.recommendations(input: input)

        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.map(\.headline) == second.map(\.headline))
        #expect(first.map(\.strength) == second.map(\.strength))
    }
}
