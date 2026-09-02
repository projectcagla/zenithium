//
//  RecommendationEngine.swift
//  Zenithium
//
//  Where the app decides what it is entitled to say. Faz 34.
//
//  This engine computes no physiology. Every number it reads has already been produced by
//  one of the thirty engines around it; what it adds is the step none of them take alone —
//  attaching literature to a number, measuring how far that literature sits from this
//  particular user, and letting the result decide the grammar of the sentence.
//
//  ## The pipeline, once, for every rule
//
//  1. A rule fires on the user's own data and names the sources it leans on.
//  2. Confidence starts at data quality × baseline maturity, then is multiplied by how
//     well the cited samples match the user (`PopulationTransfer`).
//  3. `ClaimStrength.resolve` reads the weakest source design and that confidence, demotes
//     for contradiction, and caps for unverified sources.
//  4. The rule writes its headline *for the strength it was granted* — not one sentence
//     softened afterwards, which is how hedging becomes decorative.
//
//  ## Why so much lands on `.observation`
//
//  Because the literature genuinely supports less than fitness software usually implies.
//  The acute:chronic workload ratio is the clearest case: it is widely used, and the
//  objection that its numerator sits inside its denominator is unanswered. Zenithium
//  reports the ratio and declines to instruct on it. That is the honest reading, and a
//  card that says so is worth more than a confident one that cannot be defended.
//
//  Spec §12 is upstream of all of it: nothing here names a condition, a cause, a
//  supplement or a dose, and no rule may produce a health claim — only training,
//  sleep, circadian, environmental and measurement statements.
//

import Foundation

/// Everything the recommendation layer reads, as plain values.
///
/// Deliberately not a bundle of the engines' own output types. Those change shape as their
/// engines evolve, and a layer whose job is to be auditable should not break when an
/// unrelated struct gains a field.
struct RecommendationInput: Sendable, Equatable {

    let now: Date

    let recoveryScore: Double?
    let recoveryBand: RecoveryBand?

    /// Hours of accumulated sleep debt, positive meaning owed.
    let sleepDebtHours: Double?

    let lastNightSleepHours: Double?

    let acuteLoad: Double?
    let chronicLoad: Double?
    let acwr: Double?

    /// Position of the user's VO₂max in their age and sex band, 0…100.
    let vo2MaxPercentile: Double?

    /// Difference between free-day and work-day sleep midpoints, in hours.
    let socialJetlagHours: Double?

    let dataQuality: DataQualityAssessment
    let calibration: CalibrationState

    let userAge: Int?
    let userSex: BiologicalSexValue
    let userStatus: TrainingStatus
    let lens: TrainingLens

    init(
        now: Date,
        recoveryScore: Double? = nil,
        recoveryBand: RecoveryBand? = nil,
        sleepDebtHours: Double? = nil,
        lastNightSleepHours: Double? = nil,
        acuteLoad: Double? = nil,
        chronicLoad: Double? = nil,
        acwr: Double? = nil,
        vo2MaxPercentile: Double? = nil,
        socialJetlagHours: Double? = nil,
        dataQuality: DataQualityAssessment,
        calibration: CalibrationState,
        userAge: Int? = nil,
        userSex: BiologicalSexValue = .notSet,
        userStatus: TrainingStatus = .recreational,
        lens: TrainingLens = .endurance
    ) {
        self.now = now
        self.recoveryScore = recoveryScore
        self.recoveryBand = recoveryBand
        self.sleepDebtHours = sleepDebtHours
        self.lastNightSleepHours = lastNightSleepHours
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.acwr = acwr
        self.vo2MaxPercentile = vo2MaxPercentile
        self.socialJetlagHours = socialJetlagHours
        self.dataQuality = dataQuality
        self.calibration = calibration
        self.userAge = userAge
        self.userSex = userSex
        self.userStatus = userStatus
        self.lens = lens
    }
}

enum RecommendationEngine {

    // MARK: - Thresholds

    /// Sleep debt below this is inside night-to-night noise and produces no card.
    static let sleepDebtThresholdHours = 1.0

    /// Load ratio above which the acute block is called elevated.
    static let acwrElevatedThreshold = 1.45

    /// Load ratio below which the acute block is called light against the chronic base.
    static let acwrLightThreshold = 0.80

    /// Social jetlag below this is not worth a card.
    static let socialJetlagThresholdHours = 1.5

    // MARK: - Entry point

    /// Everything the app is entitled to say today, strongest claims first.
    ///
    /// When the night's data cannot support a recovery reading, this returns exactly one
    /// card — the one naming what is missing. Producing training advice on top of unusable
    /// biometrics would be the single most damaging thing this layer could do, so the gate
    /// is here rather than inside each rule where one could forget it.
    static func recommendations(input: RecommendationInput) -> [Recommendation] {
        guard input.dataQuality.isUsableForRecovery else {
            return [dataQualityCard(input: input)]
        }

        let candidates: [Recommendation?] = [
            sleepDebtCard(input: input),
            autonomicCard(input: input),
            loadRatioCard(input: input),
            cardiorespiratoryCard(input: input),
            circadianCard(input: input)
        ]

        return candidates.compactMap { $0 }.sorted { lhs, rhs in
            if lhs.strength != rhs.strength { return lhs.strength > rhs.strength }
            if lhs.confidence.value != rhs.confidence.value {
                return lhs.confidence.value > rhs.confidence.value
            }
            return lhs.id < rhs.id
        }
    }

    // MARK: - Confidence

    /// The confidence a claim starts with, before its literature is considered.
    ///
    /// Two independent things have to be true for a claim to be trustworthy: the sensors
    /// had enough to work with last night, and the user's own baseline is old enough to
    /// compare against. They multiply because either one failing is enough to undermine
    /// the claim, and averaging would let a mature baseline paper over a bad night.
    static func baseConfidence(input: RecommendationInput) -> Double {
        MathSupport.clamp(
            input.dataQuality.confidenceFactor * input.calibration.tier.confidenceMultiplier,
            0,
            1
        )
    }

    // MARK: - Rule assembly

    /// Runs the shared pipeline for one rule.
    ///
    /// `maximumStrength` lets a rule declare that its own sources, read honestly, do not
    /// support the strength the arithmetic would grant — the recovery card uses it because
    /// `PLEWS-2013` explicitly argues against reading a single night. The reason is
    /// recorded as a limitation rather than applied silently.
    private static func assemble(
        id: String,
        domain: RecommendationDomain,
        referenceIDs: [String],
        input: RecommendationInput,
        evidence: [EvidenceNode],
        extraLimitations: [ScientificLimitation] = [],
        maximumStrength: ClaimStrength? = nil,
        capReason: String? = nil,
        wouldChangeIf: [String],
        disclaimerTier: DisclaimerTier,
        copy: (ClaimStrength) -> (headline: String, body: String)
    ) -> Recommendation {
        let fit = PopulationTransfer.combinedFit(
            of: referenceIDs,
            userAge: input.userAge,
            userSex: input.userSex,
            userStatus: input.userStatus
        )

        var penalties: [String] = []
        let base = baseConfidence(input: input)
        if input.dataQuality.confidenceFactor < 1 {
            penalties.append("Veri kalitesi: \(input.dataQuality.grade.rawValue).")
        }
        if input.calibration.tier.confidenceMultiplier < 1 {
            penalties.append("Taban çizgisi olgunluğu: \(input.calibration.tier.title).")
        }
        penalties.append(contentsOf: fit.reasons)

        let confidence = ConfidenceScore(value: base * fit.factor, penaltyReasons: penalties)

        var limitations = extraLimitations
        var strength = ClaimStrength.resolve(
            lowestGrade: EvidenceLibrary.lowestGrade(among: referenceIDs),
            confidence: confidence.value,
            hasContradiction: EvidenceLibrary.hasContradiction(among: referenceIDs),
            allSourcesVerified: EvidenceLibrary.allVerified(referenceIDs)
        )

        if let maximumStrength, strength > maximumStrength {
            strength = maximumStrength
            if let capReason {
                limitations.append(
                    ScientificLimitation(code: "SOURCE-SCOPE", explanation: capReason)
                )
            }
        }

        for (first, second) in EvidenceLibrary.contradictions(among: referenceIDs) {
            limitations.append(
                ScientificLimitation(
                    code: "EVIDENCE-CONFLICT",
                    explanation: "Bu konuda literatür hemfikir değil. \(first.authors) (\(first.year)) ile "
                        + "\(second.authors) (\(second.year)) farklı sonuçlara varıyor; iddia bir kademe zayıflatıldı."
                )
            )
        }

        for reference in EvidenceLibrary.resolve(referenceIDs) where reference.needsVerification {
            limitations.append(
                ScientificLimitation(
                    code: "SOURCE-UNVERIFIED",
                    explanation: "\(reference.id) kaynağının künyesi henüz doğrulanmadı; bu iddia tavsiye seviyesine yükseltilmiyor."
                )
            )
        }

        let text = copy(strength)

        return Recommendation(
            id: id,
            domain: domain,
            strength: strength,
            headline: text.headline,
            body: text.body,
            confidence: confidence,
            evidence: evidence,
            referenceIDs: referenceIDs,
            limitations: limitations,
            wouldChangeIf: wouldChangeIf,
            disclaimerTier: disclaimerTier,
            populationNote: fit.note
        )
    }

    // MARK: - Rules

    /// What is missing when the night cannot support a reading.
    ///
    /// Phrased descriptively throughout: at `.observation` the grammar contract forbids
    /// telling the user what to do, and stating what the calculation needs carries the
    /// same information without breaking it.
    static func dataQualityCard(input: RecommendationInput) -> Recommendation {
        let missing = input.dataQuality.missingSensors
        let detail = missing.isEmpty
            ? "Gece boyunca yeterli kayıt oluşmamış."
            : "Eksik olan: \(missing.joined(separator: ", "))."

        return Recommendation(
            id: "measurement.dataQuality",
            domain: .measurement,
            strength: .observation,
            headline: "Gece biyometrisi bugünkü hesaplama için yetersiz",
            body: "\(detail) Toparlanma skoru gece HRV ve dinlenik nabız kaydına dayanır; "
                + "bu iki sinyal olmadan üretilen bir skor, ölçüme değil varsayıma dayanırdı. "
                + "Zenithium bugün için antrenman önerisi vermiyor.",
            confidence: ConfidenceScore(
                value: 0,
                penaltyReasons: input.dataQuality.qualityIssues
            ),
            evidence: [
                EvidenceNode(
                    sourceCategory: "Sensör kapsamı",
                    summary: "Gece takma süresi: \(MathSupport.decimal(input.dataQuality.nocturnalWearHours)) saat",
                    timestamp: input.now
                )
            ],
            limitations: [
                ScientificLimitation(
                    code: "DATA-INSUFFICIENT",
                    explanation: "Gece biyometrik kayıtları yetersiz.",
                    isBlocking: true
                )
            ],
            wouldChangeIf: [
                "Saat gece boyunca takılı kaldığında ve HRV ile dinlenik nabız kaydedildiğinde bu kart yerini günlük değerlendirmeye bırakır."
            ],
            disclaimerTier: .none
        )
    }

    /// Accumulated sleep debt against the consensus adult range.
    ///
    /// The one rule that regularly reaches `.recommendation`: two consensus statements,
    /// no contradiction between them, and both bibliographically confirmed.
    static func sleepDebtCard(input: RecommendationInput) -> Recommendation? {
        guard let debt = input.sleepDebtHours, debt >= sleepDebtThresholdHours else { return nil }

        let minutes = Int((debt * 60).rounded())
        let debtText = "\(MathSupport.decimal(debt)) saat"

        return assemble(
            id: "sleep.debt",
            domain: .sleep,
            referenceIDs: ["WATSON-2015", "HIRSHKOWITZ-2015"],
            input: input,
            evidence: [
                EvidenceNode(
                    sourceCategory: "Uyku",
                    summary: "Birikmiş uyku borcu: \(debtText)",
                    timestamp: input.now
                )
            ],
            wouldChangeIf: [
                "İki gece üst üste kendi ortalamanın üzerinde uyursan borç kapanır ve bu kart kalkar.",
                "Uyku kaydı olmayan bir gece borcun hesaplanmasını durdurur."
            ],
            disclaimerTier: .training
        ) { strength in
            switch strength {
            case .recommendation:
                return (
                    "Bu gece \(minutes) dakika daha uzun uyu",
                    "Son günlerde \(debtText) uyku borcu birikti. Yetişkinler için ortak uzmanlık "
                        + "bildirileri düzenli olarak 7 saatin altında kalmamayı öneriyor; borcu tek gecede "
                        + "değil birkaç geceye yayarak kapatmak daha gerçekçi."
                )
            case .suggestion:
                return (
                    "Uyku borcun \(debtText)",
                    "Önümüzdeki birkaç gecede uykunu uzatmak bu farkı kapatabilir. Ortak uzmanlık "
                        + "bildirileri yetişkinler için düzenli 7 saatin altını önermiyor."
                )
            case .observation:
                return (
                    "Birikmiş uyku borcun \(debtText)",
                    "Bu sayı, son gecelerin uyku sürelerinin kendi ortalamana göre farkından geliyor."
                )
            }
        }
    }

    /// Autonomic state from the night's biometrics.
    ///
    /// Capped at `.suggestion` on purpose. `PLEWS-2013` is the source this rule leans on
    /// hardest, and what that paper actually argues for is weekly averaging — reading a
    /// single night as a verdict is the thing it warns against. Letting the arithmetic
    /// grant a recommendation here would be citing a paper against itself.
    static func autonomicCard(input: RecommendationInput) -> Recommendation? {
        guard let band = input.recoveryBand, let score = input.recoveryScore else { return nil }
        guard band != .green else { return nil }

        let scoreText = "\(Int(score.rounded()))"

        return assemble(
            id: "recovery.autonomic",
            domain: .recovery,
            referenceIDs: ["PLEWS-2013", "BUCHHEIT-2014"],
            input: input,
            evidence: [
                EvidenceNode(
                    sourceCategory: "Otonom sinir sistemi",
                    summary: "Toparlanma skoru: \(scoreText)",
                    timestamp: input.now
                )
            ],
            maximumStrength: .suggestion,
            capReason: "Dayanılan çalışma tek bir gecenin değil, haftalık ortalamaların takibini savunuyor. "
                + "Tek gecelik bir değer bu yüzden tavsiye değil öneri seviyesinde kalıyor.",
            wouldChangeIf: [
                "Yarın gece HRV'n 7 günlük ortalamana dönerse bu kart kalkar.",
                "Aynı bandın üç gece sürmesi, tek gecelik dalgalanma açıklamasını geçersiz kılar."
            ],
            disclaimerTier: .training
        ) { strength in
            switch strength {
            case .recommendation, .suggestion:
                let intensity = band == .red ? "belirgin biçimde" : "bir miktar"
                return (
                    "Toparlanma \(scoreText) — bugünü hafif tutmayı düşünebilirsin",
                    "Gece biyometrilerin taban çizginin \(intensity) altında. Bu tek gecelik bir "
                        + "sapma olabilir; birden çok gün süren bir eğilim daha anlamlıdır."
                )
            case .observation:
                return (
                    "Toparlanma skorun \(scoreText)",
                    "Gece biyometrilerin kendi taban çizginin altında. Bu sayı bugünkü kapasiteni değil, "
                        + "gece ölçülen otonom dengeni betimler."
                )
            }
        }
    }

    /// The acute block against the chronic base.
    ///
    /// This card is where the evidence machinery earns its place. The ratio is widely
    /// used and widely criticised, the two positions are recorded as contradicting each
    /// other, and the demotion that follows leaves the app reporting the number and
    /// declining to instruct on it. Fitness software normally resolves this by picking
    /// the flattering side.
    static func loadRatioCard(input: RecommendationInput) -> Recommendation? {
        guard let ratio = input.acwr, ratio.isFinite, ratio > 0 else { return nil }
        guard ratio >= acwrElevatedThreshold || ratio <= acwrLightThreshold else { return nil }

        let isElevated = ratio >= acwrElevatedThreshold
        let percent = Int(((ratio - 1) * 100).rounded())
        // One digit, not two. `MathSupport.decimal` does not zero-pad the fraction, so at
        // two digits a ratio of 1.05 would render "1,5" — see the note filed against that
        // helper. One digit is enough resolution for a load ratio and cannot hit the bug.
        let ratioText = MathSupport.decimal(ratio, digits: 1)

        var evidence: [EvidenceNode] = [
            EvidenceNode(
                sourceCategory: "Antrenman yükü",
                summary: "Akut:kronik oran \(ratioText)",
                timestamp: input.now
            )
        ]
        if let acute = input.acuteLoad, let chronic = input.chronicLoad {
            evidence.append(
                EvidenceNode(
                    sourceCategory: "Antrenman yükü",
                    summary: "Akut \(MathSupport.decimal(acute)) / kronik \(MathSupport.decimal(chronic))",
                    timestamp: input.now
                )
            )
        }

        return assemble(
            id: "training.loadRatio",
            domain: .training,
            referenceIDs: ["GABBETT-2016", "HULIN-2016", "LOLLI-2019"],
            input: input,
            evidence: evidence,
            wouldChangeIf: [
                "Oran 0,80–1,45 aralığına döndüğünde bu kart kalkar.",
                "Kronik taban dört haftadan kısaysa oranın kendisi güvenilir değildir."
            ],
            disclaimerTier: .training
        ) { strength in
            let direction = isElevated
                ? "kronik ortalamanın %\(abs(percent)) üstünde"
                : "kronik ortalamanın %\(abs(percent)) altında"

            switch strength {
            case .recommendation, .suggestion:
                return (
                    "Akut yükün \(direction)",
                    "Bu aralıkta yükü kademeli değiştirmek, sıçrama yapmaktan daha güvenli kabul edilir — "
                        + "ancak oranın kendisi tartışmalıdır."
                )
            case .observation:
                return (
                    "Akut yükün \(direction)",
                    "Oran \(ratioText). Bu ölçütün sakatlıkla ilişkisi literatürde tartışmalı: akut değer "
                        + "kronik değerin içinde yer aldığı için, gerçek bir ilişki olmasa bile korelasyon "
                        + "üretebiliyor. Zenithium bu yüzden sayıyı gösteriyor ve üzerine talimat vermiyor."
                )
            }
        }
    }

    /// Where the user's cardiorespiratory fitness sits in their age and sex band.
    ///
    /// Reaches `.observation` and stops there, because the reference standards are
    /// cross-sectional: they say where a value ranks, never what changing it would do.
    static func cardiorespiratoryCard(input: RecommendationInput) -> Recommendation? {
        guard let percentile = input.vo2MaxPercentile, percentile.isFinite else { return nil }
        let position = Int(MathSupport.clamp(percentile, 0, 100).rounded())

        return assemble(
            id: "measurement.cardiorespiratory",
            domain: .measurement,
            referenceIDs: ["ROSS-2016", "KAMINSKY-2015"],
            input: input,
            evidence: [
                EvidenceNode(
                    sourceCategory: "Kardiyorespiratuar uygunluk",
                    summary: "Yaş ve cinsiyet grubunda yüzdelik konum: %\(position)",
                    timestamp: input.now
                )
            ],
            wouldChangeIf: [
                "Apple Watch yeni bir VO₂max tahmini yazdığında konum güncellenir.",
                "Yaş grubun değiştiğinde aynı değer farklı bir yüzdeliğe düşer."
            ],
            disclaimerTier: .training
        ) { _ in
            (
                "VO₂max konumun kendi yaş ve cinsiyet grubunda %\(position)",
                "Bu karşılaştırma laboratuvar ölçümlerinden oluşan bir referans kaydına dayanıyor. "
                    + "Senin değerin bilekten tahmin edilmiş bir sayı; iki yöntem aynı ölçek üzerinde "
                    + "olsa da aynı şey değildir."
            )
        }
    }

    /// The gap between free-day and work-day sleep timing.
    static func circadianCard(input: RecommendationInput) -> Recommendation? {
        guard let jetlag = input.socialJetlagHours, jetlag >= socialJetlagThresholdHours else {
            return nil
        }
        let text = MathSupport.decimal(jetlag)

        return assemble(
            id: "circadian.socialJetlag",
            domain: .circadian,
            referenceIDs: ["ROENNEBERG-2003"],
            input: input,
            evidence: [
                EvidenceNode(
                    sourceCategory: "Sirkadiyen ritim",
                    summary: "Serbest gün ve iş günü uyku ortası farkı: \(text) saat",
                    timestamp: input.now
                )
            ],
            wouldChangeIf: [
                "Serbest günlerdeki uyku ortan iş günlerine yaklaştığında fark küçülür ve bu kart kalkar."
            ],
            disclaimerTier: .none
        ) { _ in
            (
                "Serbest gün ve iş günü uyku ortan arasında \(text) saat fark var",
                "Bu farkın nüfusta yaygın olduğu ve kronotiple birlikte değiştiği biliniyor. "
                    + "Farkı kapatmanın ne getireceği ise bu kaynakta gösterilmiş değil — "
                    + "kaynak dağılımı betimliyor, bir müdahaleyi sınamıyor."
            )
        }
    }
}
