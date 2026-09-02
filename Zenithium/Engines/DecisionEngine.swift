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
        clinical: ClinicalContext = .neutral
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
                inputDescription: "Gece Takma: \(MathSupport.decimal(input.dataQuality.nocturnalWearHours)) sa, Kalibrasyon: \(input.calibration.tier.title)",
                outputDescription: "Veri Kalitesi: \(input.dataQuality.grade.rawValue) (Güven: %\(Int(input.dataQuality.confidenceFactor * 100)))",
                physiologicalImpact: input.dataQuality.isUsableForRecovery ? "Biyometrik sinyaller toparlanma hesaplaması için yeterli." : "Yetersiz gece saati verisi nedeniyle kararlar sınırlandırıldı."
            )
        )
        stepCounter += 1

        // Ingest clinical evidence and limitations
        evidence.append(contentsOf: input.clinical.evidence)
        limitations.append(contentsOf: input.clinical.limitations)

        if !input.dataQuality.isUsableForRecovery || input.calibration.tier == .coldStart || input.clinical.suppressesHRVRecovery {
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
        let recovery = input.recoveryScore ?? 50.0
        let band = input.recoveryBand ?? RecoveryBand.band(forScore: recovery)

        evidence.append(
            EvidenceNode(
                sourceCategory: "Toparlanma",
                summary: "Toparlanma Skoru: \(Int(recovery)) (\(band.displayName))",
                weight: 0.40,
                timestamp: Date()
            )
        )

        steps.append(
            TraceStep(
                stepNumber: stepCounter,
                engineName: "RecoveryEngine",
                inputDescription: "Gecelik HRV ve RHR z-skor dağılımı",
                outputDescription: "Toparlanma Skoru: \(Int(recovery)) (\(band.displayName))",
                physiologicalImpact: "Günlük otonom sinir sistemi hazırbulunuşluğu belirlendi."
            )
        )
        stepCounter += 1

        if let sleep = input.sleepScore {
            evidence.append(
                EvidenceNode(
                    sourceCategory: "Uyku",
                    summary: "Uyku Skoru: \(Int(sleep))",
                    weight: 0.20,
                    timestamp: Date()
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
                    timestamp: Date()
                )
            )
            steps.append(
                TraceStep(
                    stepNumber: stepCounter,
                    engineName: "TrainingLoadEngine",
                    inputDescription: "Akut (7g): \(MathSupport.decimal(input.acuteLoad ?? 0, digits: 1)), Kronik (28g): \(MathSupport.decimal(input.chronicLoad ?? 0, digits: 1))",
                    outputDescription: "ACWR: \(MathSupport.decimal(acwr, digits: 2)) (\(loadBand.displayName))",
                    physiologicalImpact: (loadBand == .productive || loadBand == .maintaining) ? "Yük artış hızı güvenli aralıkta." : "Aşırı yüklenme riski nedeniyle tavan sınırlandırıldı."
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
                    timestamp: Date()
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
                    inputDescription: "Klinik Çarpan: ×\(MathSupport.decimal(input.clinical.confidenceMultiplier, digits: 2))",
                    outputDescription: input.clinical.penaltyReasons.joined(separator: "; "),
                    physiologicalImpact: "Biyobelirteç ve EKG bağlamı karar güvenine ve hata payına yansıtıldı."
                )
            )
            stepCounter += 1
        }

        // Step 5: Final Deterministic Synthesis
        let action: DecisionAction
        let headline: String
        let rationale: String
        let activities: [WorkoutActivity]

        switch band {
        case .green:
            let target = RecoveryEngine.targetCeiling(forRecovery: recovery)
            action = .push(targetStrain: target)
            headline = "Yüksek Adaptasyon Kapasitesi"
            rationale = "Otonom sinir sisteminiz ve toparlanma değerleriniz yüksek zorlanmayı karşılamaya hazır. Hedef antrenman yükü: \(MathSupport.decimal(target))."
            activities = [.running, .cycling, .highIntensityIntervalTraining, .functionalStrengthTraining]

        case .yellow:
            let target = RecoveryEngine.targetCeiling(forRecovery: recovery)
            action = .maintain(targetStrain: target)
            headline = "Dengeli Antrenman Günü"
            rationale = "Temel kardiyovasküler kapasite stabil. Aşırı yüklenmeden kaçınarak planlı antrenmanınıza devam edebilirsiniz (Tavan: \(MathSupport.decimal(target)))."
            activities = [.running, .functionalStrengthTraining, .swimming, .rowing]

        case .red:
            action = .recover
            headline = "Fizyolojik Toparlanma Önceliği"
            rationale = "Toparlanma skorunuz baskılanmış durumda. Ağır antrenmanlar yerine aktif toparlanma, mobilite veya dinlenme önerilir."
            activities = [.walking, .coreTraining, .functionalStrengthTraining]
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
}
