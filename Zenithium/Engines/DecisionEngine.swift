//
//  DecisionEngine.swift
//  Zenithium
//
//  The top-level athletic decision engine.
//  Deterministically translates recovery, load, muscle readiness, and data quality
//  into an actionable, evidence-backed training prescription with full decision trace.
//

import Foundation

struct DecisionInput: Sendable {
    let recoveryScore: Double?
    let recoveryBand: RecoveryBand?
    let sleepScore: Double?
    let acuteLoad: Double?
    let chronicLoad: Double?
    let acwr: Double?
    let muscleReadiness: [MuscleGroup: MuscleReadiness]
    let dataQuality: DataQualityAssessment
    let calibration: CalibrationState
    let lens: TrainingLens
    let clinical: ClinicalContext
    let preference: DecisionPreference
    let evaluatedAt: Date
    let personalContexts: [PersonalContextEntry]

    init(
        recoveryScore: Double?,
        recoveryBand: RecoveryBand?,
        sleepScore: Double?,
        acuteLoad: Double? = nil,
        chronicLoad: Double? = nil,
        acwr: Double? = nil,
        muscleReadiness: [MuscleGroup: MuscleReadiness] = [:],
        dataQuality: DataQualityAssessment,
        calibration: CalibrationState,
        lens: TrainingLens = .endurance,
        clinical: ClinicalContext = .neutral,
        preference: DecisionPreference = .progressive,
        evaluatedAt: Date = Date(),
        personalContexts: [PersonalContextEntry] = []
    ) {
        self.recoveryScore = recoveryScore
        self.recoveryBand = recoveryBand
        self.sleepScore = sleepScore
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.acwr = acwr
        self.muscleReadiness = muscleReadiness
        self.dataQuality = dataQuality
        self.calibration = calibration
        self.lens = lens
        self.clinical = clinical
        self.preference = preference
        self.evaluatedAt = evaluatedAt
        self.personalContexts = personalContexts
    }
}

enum DecisionEngine {

    static func decide(input: DecisionInput) -> EngineResult<AthleticDecision> {
        var steps: [TraceStep] = []
        var evidence: [EvidenceNode] = []
        var limitations: [ScientificLimitation] = []
        var stepCounter = 1

        // Step 1: Data Quality & Calibration Gating
        steps.append(
            TraceStep(
                stepNumber: stepCounter,
                engineName: "DataQualityEngine",
                inputDescription: "Kayıtlı uyku: \(MathSupport.decimal(input.dataQuality.nocturnalWearHours)) sa, Kalibrasyon: \(input.calibration.tier.title)",
                outputDescription: "Veri Kalitesi: \(input.dataQuality.grade.rawValue) (Güven: %\(Int(input.dataQuality.confidenceFactor * 100)))",
                physiologicalImpact: input.dataQuality.isUsableForRecovery ? "Biyometrik sinyaller toparlanma hesaplaması için yeterli." : "Yetersiz gece saati verisi nedeniyle kararlar sınırlandırıldı."
            )
        )
        stepCounter += 1

        // Ingest clinical evidence and limitations
        evidence.append(contentsOf: input.clinical.evidence)
        limitations.append(contentsOf: input.clinical.limitations)

        let hasRecovery = input.recoveryScore.map { $0.isFinite && (0...100).contains($0) } ?? false
        if !hasRecovery || !input.dataQuality.isUsableForRecovery || input.calibration.tier == .coldStart || input.clinical.suppressesHRVRecovery {
            if input.calibration.tier == .coldStart {
                limitations.append(
                    ScientificLimitation(
                        code: "COLD-START",
                        explanation: "Bireysel taban çizgisi henüz tamamlanmadı (\(input.calibration.recordedDaysCount)/4 gün).",
                        isBlocking: false
                    )
                )
            }
            if !input.dataQuality.isUsableForRecovery {
                limitations.append(
                    ScientificLimitation(
                        code: "DATA-INSUFFICIENT",
                        explanation: "Gece biyometrik kayıtları yetersiz (\(input.dataQuality.qualityIssues.joined(separator: ", "))).",
                        isBlocking: true
                    )
                )
            }
            if input.clinical.suppressesHRVRecovery {
                limitations.append(
                    ScientificLimitation(
                        code: "CLINICAL-AF-SUPPRESSED",
                        explanation: "Atriyal fibrilasyon ritim düzensizliği nedeniyle HRV toparlanma skoru geçersiz kılındı.",
                        isBlocking: true
                    )
                )
            }

            let penalties = input.dataQuality.qualityIssues + input.clinical.penaltyReasons
            let confVal = MathSupport.clamp(input.dataQuality.confidenceFactor * input.clinical.confidenceMultiplier, 0.0, 1.0)
            
            let decision = AthleticDecision(
                action: .calibrate,
                headline: input.clinical.suppressesHRVRecovery ? "Ritim Düzensizliği Kaydedildi" : "Taban Çizgisi Oluşturuluyor",
                primaryRationale: input.clinical.suppressesHRVRecovery ? "Atriyal fibrilasyon kaydı varken HRV otonom tonusu yansıtmaz; toparlanma skoru geçici olarak askıya alındı." : "Kişiselleştirilmiş antrenman önerileri için saatinizi gece uyurken takmaya devam edin.",
                suggestedActivities: [.walking],
                confidence: ConfidenceScore(value: confVal, penaltyReasons: penalties),
                evidence: evidence,
                traceSteps: steps,
                limitations: limitations
            )

            return EngineResult(
                value: decision,
                confidence: decision.confidence,
                evidence: evidence,
                limitations: limitations,
                calculationSteps: steps.map { "Adım \($0.stepNumber): \($0.engineName) -> \($0.outputDescription)" }
            )
        }

        // Step 2: Recovery Assessment
        let recovery = input.recoveryScore ?? 0
        let band = RecoveryBand.band(forScore: recovery)

        evidence.append(
            EvidenceNode(
                sourceCategory: "Toparlanma",
                summary: "Toparlanma Skoru: \(Int(recovery)) (\(band.displayName))",
                weight: 0.40,
                timestamp: input.evaluatedAt
            )
        )

        steps.append(
            TraceStep(
                stepNumber: stepCounter,
                engineName: "RecoveryEngine",
                inputDescription: "Gecelik HRV ve RHR z-skor dağılımı",
                outputDescription: "Toparlanma Skoru: \(Int(recovery)) (\(band.displayName))",
                physiologicalImpact: "Kişisel tabana göre biyometrik değişim özetlendi; performans kapasitesi ölçülmedi."
            )
        )
        stepCounter += 1

        if let sleep = input.sleepScore {
            evidence.append(
                EvidenceNode(
                    sourceCategory: "Uyku",
                    summary: "Uyku Skoru: \(Int(sleep))",
                    weight: 0.20,
                    timestamp: input.evaluatedAt
                )
            )
            steps.append(
                TraceStep(
                    stepNumber: stepCounter,
                    engineName: "SleepScoreEngine",
                    inputDescription: "Gecelik uyku süresi ve mimarisi",
                    outputDescription: "Uyku Skoru: \(Int(sleep))",
                    physiologicalImpact: "Toparlanmayı destekleyen uyku kalitesi ve restoratif süre değerlendirildi."
                )
            )
            stepCounter += 1
        }

        // Step 3: Training Load & ACWR Gating
        if let acwr = input.acwr {
            let loadBand = LoadBand.band(forRatio: acwr)
            evidence.append(
                EvidenceNode(
                    sourceCategory: "Yük Dengesi",
                    summary: "ACWR: \(MathSupport.decimal(acwr, digits: 2)) (\(loadBand.displayName))",
                    weight: 0.30,
                    timestamp: input.evaluatedAt
                )
            )
            steps.append(
                TraceStep(
                    stepNumber: stepCounter,
                    engineName: "TrainingLoadEngine",
                    inputDescription: "Akut (7g): \(MathSupport.decimal(input.acuteLoad ?? 0, digits: 1)), Kronik (28g): \(MathSupport.decimal(input.chronicLoad ?? 0, digits: 1))",
                    outputDescription: "ACWR: \(MathSupport.decimal(acwr, digits: 2)) (\(loadBand.displayName))",
                    physiologicalImpact: (loadBand == .productive || loadBand == .maintaining) ? "Son haftanın yükü uzun dönem yüküne yakın; bu bir güvenlik sınırı değildir." : "Yakın dönemde yük değişmiş; günlük plan ihtiyatla sınırlandırıldı."
                )
            )
            stepCounter += 1
        }

        // Step 4: Muscle Fatigue Screening
        let fatiguedMuscles = input.muscleReadiness.values.filter { $0.band == .red }
        if let fatigued = fatiguedMuscles.first {
            evidence.append(
                EvidenceNode(
                    sourceCategory: "Kas Yorgunluğu",
                    summary: "\(fatigued.muscle.displayName) toparlanma sürecinde (%\(Int(fatigued.readiness)))",
                    weight: 0.20,
                    timestamp: input.evaluatedAt
                )
            )
            steps.append(
                TraceStep(
                    stepNumber: stepCounter,
                    engineName: "FatigueEngine",
                    inputDescription: "Son antrenmanların kas bazlı yük süperpozisyonu",
                    outputDescription: "\(fatigued.muscle.displayName) yorgunluk tavanında (\(Int(fatigued.fatigue)) puan)",
                    physiologicalImpact: "Bu kas grubunu içeren yoğun hareketlerin sınırlanması önerildi."
                )
            )
            stepCounter += 1
        }
        
        // Clinical Context Step (if active)
        if input.clinical != .neutral {
            steps.append(
                TraceStep(
                    stepNumber: stepCounter,
                    engineName: "ClinicalContextEngine",
                    inputDescription: "Kayıtlı tahlil ve EKG bağlamı",
                    outputDescription: input.clinical.penaltyReasons.joined(separator: "; "),
                    physiologicalImpact: "Tahliller bağlam ve sınırlama olarak gösterilir; doğrulanmamış sayısal ceza uygulanmaz. Yakın tarihli ritim kaydı varsa HRV yorumu ihtiyaten durdurulur."
                )
            )
            stepCounter += 1
        }

        // Step 5: Final Deterministic Synthesis
        var action: DecisionAction
        var headline: String
        var rationale: String
        var activities: [WorkoutActivity]

        switch band {
        case .green:
            let target = RecoveryEngine.targetCeiling(forRecovery: recovery)
            action = .push(targetStrain: target)
            headline = "Daha yoğun bir gün düşünülebilir"
            rationale = "Toparlanma göstergelerin kişisel tabanına göre yüksek. Kendini iyi hissediyorsan planladığın antrenmanı değerlendirebilirsin."
            activities = [.running, .cycling, .highIntensityIntervalTraining, .functionalStrengthTraining]

        case .yellow:
            let target = RecoveryEngine.targetCeiling(forRecovery: recovery)
            action = .maintain(targetStrain: target)
            headline = "Planını koruyabilirsin"
            rationale = "Toparlanma göstergelerin orta bantta. Bugünkü planını nasıl hissettiğinle birlikte değerlendir."
            activities = [.running, .functionalStrengthTraining, .swimming, .rowing]

        case .red:
            action = .recover
            headline = "Toparlanmaya alan aç"
            rationale = "Toparlanma skorunuz baskılanmış durumda. Ağır antrenmanlar yerine aktif toparlanma, mobilite veya dinlenme önerilir."
            activities = [.walking, .coreTraining, .functionalStrengthTraining]
        }

        // ACWR Safety Gating (Spike Guard)
        if let acwr = input.acwr, acwr >= 1.50 {
            let cappedTarget = min(RecoveryEngine.targetCeiling(forRecovery: recovery), 12.0)
            if case .push = action {
                action = .maintain(targetStrain: cappedTarget)
            } else if case .maintain = action {
                action = .maintain(targetStrain: cappedTarget)
            }
            headline = "Yüksek Akut Yük Koruması"
            rationale = "Toparlanmanız \(band.displayName.lowercased()) bantta olsa da son haftalık akut yükünüz belirgin yükseldi (ACWR: \(MathSupport.decimal(acwr, digits: 2))). Planlama önlemi olarak günlük zorlanma tavanı \(MathSupport.decimal(cappedTarget)) ile sınırlandırıldı."
        }

        if input.preference == .cautious, recovery < input.preference.pushThreshold, case .push = action {
            let cap = min(RecoveryEngine.targetCeiling(forRecovery: recovery), 14)
            action = .maintain(targetStrain: cap)
            headline = "Bugün planını koru"
            rationale = "İhtiyatlı tercihin, yüksek yük için daha güçlü toparlanma bekliyor. Bu bir planlama sınırıdır; ölçülen puanını değiştirmez."
        }
        if case .push = action { activities = activitiesForLens(input.lens) }
        if case .maintain = action { activities = activitiesForLens(input.lens) }
        let activeContexts = input.personalContexts.filter { $0.isActive(at: input.evaluatedAt) }
        if !activeContexts.isEmpty {
            if activeContexts.contains(where: { $0.kind == .illness }) {
                action = .recover
                headline = "Bugün dinlenmeye alan aç"
                rationale = "Kendini hasta hissettiğini belirttin. Toparlanma puanın yüksek olsa da yoğun antrenman önerilmiyor. Bu kayıt bir tanı değildir."
                activities = [.walking]
            } else if case .push(let target) = action {
                action = .maintain(targetStrain: min(target, 14))
                headline = "Değişen düzenine alan bırak"
                rationale = "Kaydettiğin bağlam nedeniyle bugün yük artışı sınırlandı. Bu, bildirdiğin koşullara dayalı bir planlama tercihidir; fizyolojik etki tahmini değildir."
            }
            steps.append(TraceStep(stepNumber: stepCounter, engineName: "DecisionEngine",
                inputDescription: activeContexts.map { $0.kind.title }.joined(separator: ", "),
                outputDescription: "Kullanıcının etkin tarihli bağlamı günlük planı sınırlandırdı.",
                physiologicalImpact: "Ölçülen puan ve kişisel taban değiştirilmedi; bağlamdan hastalık veya etki büyüklüğü çıkarılmaz."))
            stepCounter += 1
        }
        steps.append(TraceStep(stepNumber: stepCounter, engineName: "DecisionEngine",
            inputDescription: "\(input.preference.title) · \(input.lens.displayName)",
            outputDescription: "Yüksek yük için toparlanma eşiği: \(Int(input.preference.pushThreshold))",
            physiologicalImpact: "Kullanıcının planlama tercihi; doğrulanmış bir risk sınırı değil."))

        // Muscle Fatigue Screening
        if !fatiguedMuscles.isEmpty {
            let redGroups = Set(fatiguedMuscles.map(\.muscle))
            let safeActivities = activities.filter { activity in
                let row = MuscleInvolvementMatrix.involvement(for: activity)
                return !redGroups.contains { group in (row[group] ?? 0) >= 0.40 }
            }
            if !safeActivities.isEmpty {
                activities = safeActivities
            } else {
                activities = [.walking, .coreTraining]
            }
        }

        let finalConfidenceValue = MathSupport.clamp(input.dataQuality.confidenceFactor * input.clinical.confidenceMultiplier, 0.0, 1.0)
        let combinedPenalties = input.dataQuality.missingSensors.map { "\($0) sensörü eksik" } + input.clinical.penaltyReasons

        let confidenceScore = ConfidenceScore(
            value: finalConfidenceValue,
            penaltyReasons: combinedPenalties
        )

        let decision = AthleticDecision(
            action: action,
            headline: headline,
            primaryRationale: rationale,
            suggestedActivities: activities,
            confidence: confidenceScore,
            evidence: evidence,
            traceSteps: steps,
            limitations: limitations
        )

        return EngineResult(
            value: decision,
            confidence: confidenceScore,
            evidence: evidence,
            limitations: limitations,
            calculationSteps: steps.map { "Adım \($0.stepNumber): \($0.engineName) -> \($0.outputDescription)" }
        )
    }
    private static func activitiesForLens(_ lens: TrainingLens) -> [WorkoutActivity] {
        switch lens {
        case .endurance: return [.running, .cycling, .swimming]
        case .strength: return [.traditionalStrengthTraining, .functionalStrengthTraining]
        case .hybrid: return [.functionalStrengthTraining, .running, .rowing]
        case .health: return [.walking]
        }
    }

}
