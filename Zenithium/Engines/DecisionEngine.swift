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
        lens: TrainingLens = .endurance
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
                inputDescription: "Gece Takma: \(String(format: "%.1f", input.dataQuality.nocturnalWearHours)) sa, Kalibrasyon: \(input.calibration.tier.title)",
                outputDescription: "Veri Kalitesi: \(input.dataQuality.grade.rawValue) (Güven: %\(Int(input.dataQuality.confidenceFactor * 100)))",
                physiologicalImpact: input.dataQuality.isUsableForRecovery ? "Biyometrik sinyaller toparlanma hesaplaması için yeterli." : "Yetersiz gece saati verisi nedeniyle kararlar sınırlandırıldı."
            )
        )
        stepCounter += 1

        if !input.dataQuality.isUsableForRecovery || input.calibration.tier == .coldStart {
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

            let decision = AthleticDecision(
                action: .calibrate,
                headline: "Taban Çizgisi Oluşturuluyor",
                primaryRationale: "Kişiselleştirilmiş antrenman önerileri için saatinizi gece uyurken takmaya devam edin.",
                suggestedActivities: [.walking],
                confidence: ConfidenceScore(value: input.dataQuality.confidenceFactor, penaltyReasons: input.dataQuality.qualityIssues),
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
                summary: "Toparlanma Skoru: %\(Int(recovery)) (\(band.displayName))",
                weight: 0.40,
                timestamp: Date()
            )
        )

        steps.append(
            TraceStep(
                stepNumber: stepCounter,
                engineName: "RecoveryEngine",
                inputDescription: "HRV & RHR z-skorları ve uyku kalitesi",
                outputDescription: "Toparlanma %\(Int(recovery)) (\(band.displayName))",
                physiologicalImpact: "Otonom sinir sistemi ve kardiyovasküler hazırbulunuşluk seviyesi belirlendi."
            )
        )
        stepCounter += 1

        // Step 3: Sleep Synthesis
        if let sleep = input.sleepScore {
            evidence.append(
                EvidenceNode(
                    sourceCategory: "Uyku",
                    summary: "Uyku Skoru: %\(Int(sleep))",
                    weight: 0.25,
                    timestamp: Date()
                )
            )
            steps.append(
                TraceStep(
                    stepNumber: stepCounter,
                    engineName: "SleepScoreEngine",
                    inputDescription: "Uyku süresi ve verimlilik analizi",
                    outputDescription: "Uyku Skoru %\(Int(sleep))",
                    physiologicalImpact: "Hücresel onarım ve merkezi sinir sistemi dinlenme durumu doğrulandı."
                )
            )
            stepCounter += 1
        }

        // Step 4: Fatigue & Muscle Readiness
        let mostFatigued = input.muscleReadiness.values.sorted { $0.readiness < $1.readiness }.first
        if let fatigued = mostFatigued, fatigued.readiness < 50 {
            evidence.append(
                EvidenceNode(
                    sourceCategory: "Kas Hazırlığı",
                    summary: "\(fatigued.muscle.displayName) %\(Int(fatigued.readiness)) hazır",
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
            rationale = "Otonom sinir sisteminiz ve toparlanma değerleriniz yüksek zorlanmayı karşılamaya hazır. Hedef antrenman yükü: \(String(format: "%.1f", target))."
            activities = [.running, .cycling, .highIntensityIntervalTraining, .functionalStrengthTraining]

        case .yellow:
            let target = RecoveryEngine.targetCeiling(forRecovery: recovery)
            action = .maintain(targetStrain: target)
            headline = "Dengeli Antrenman Günü"
            rationale = "Temel kardiyovasküler kapasite stabil. Aşırı yüklenmeden kaçınarak planlı antrenmanınıza devam edebilirsiniz (Tavan: \(String(format: "%.1f", target)))."
            activities = [.running, .functionalStrengthTraining, .swimming, .rowing]

        case .red:
            action = .recover
            headline = "Fizyolojik Toparlanma Önceliği"
            rationale = "Toparlanma skorunuz baskılanmış durumda. Ağır antrenmanlar yerine aktif toparlanma, mobilite veya dinlenme önerilir."
            activities = [.walking, .coreTraining, .functionalStrengthTraining]
        }

        let confidenceScore = ConfidenceScore(
            value: input.dataQuality.confidenceFactor,
            penaltyReasons: input.dataQuality.missingSensors.map { "\($0) sensörü eksik" }
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
