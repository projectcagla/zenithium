//
//  ScientificBoundaryRegistry.swift
//  Zenithium
//
//  Central scientific boundary registry and epistemic invariants.
//  Documents and enforces peer-reviewed physiological limits across all 29 engines.
//

import Foundation

struct ScientificBoundary: Sendable, Equatable, Identifiable {
    let id: String
    let engineName: String
    let physiologicalModel: String
    let primaryCitation: String
    let documentedLimitations: [String]
    let nonCausalityDisclaimer: String

    init(
        id: String,
        engineName: String,
        physiologicalModel: String,
        primaryCitation: String,
        documentedLimitations: [String],
        nonCausalityDisclaimer: String
    ) {
        self.id = id
        self.engineName = engineName
        self.physiologicalModel = physiologicalModel
        self.primaryCitation = primaryCitation
        self.documentedLimitations = documentedLimitations
        self.nonCausalityDisclaimer = nonCausalityDisclaimer
    }
}

enum ScientificBoundaryRegistry {

    static let boundaries: [String: ScientificBoundary] = [
        "Recovery": ScientificBoundary(
            id: "RECOVERY-1",
            engineName: "RecoveryEngine",
            physiologicalModel: "Multi-biometric exponential moving z-score with individualized baselines (HRV, RHR, Temp, Sleep)",
            primaryCitation: "Plews et al. (2013), 'Training adaptation and heart rate variability in elite endurance athletes'",
            documentedLimitations: [
                "Requires minimum 4 nights of nocturnal HRV data for non-population scoring",
                "Cannot differentiate psychological acute stress from physical training fatigue",
                "Wrist temperature depends on Apple Watch Series 8+ / Ultra sensor hardware"
            ],
            nonCausalityDisclaimer: "Toparlanma skoru otonom sinir sistemi dengesini yansıtan bir gözlemdir; bu bir teşhis değil, antrenman hazırbulunuşluk kılavuzudur."
        ),
        "TrainingLoad": ScientificBoundary(
            id: "LOAD-1",
            engineName: "TrainingLoadEngine",
            physiologicalModel: "Exponentially weighted Banister impulse-response model (Acute: 7d, Chronic: 28d, ACWR)",
            primaryCitation: "Banister EW (1991), 'Modeling Elite Athletic Performance'; Gabbett TJ (2016), 'The training—injury prevention paradox'",
            documentedLimitations: [
                "Non-cardio sessions (e.g. isometric strength) underestimate metabolic strain via HR alone",
                "Requires continuous RPE logging for non-wearable strength sessions",
                "ACWR is a load monitoring heuristic, not a guaranteed injury predictor"
            ],
            nonCausalityDisclaimer: "Antrenman yükü ve ACWR, aşırı yüklenme riskini yönetmek için bir kılavuzdur; doğrudan yaralanma tahmini yapmaz."
        ),
        "SleepScore": ScientificBoundary(
            id: "SLEEP-1",
            engineName: "SleepScoreEngine",
            physiologicalModel: "Multi-component sleep architecture (Duration, Efficiency, Restorative % (Deep+REM), Midpoint Consistency)",
            primaryCitation: "Hirshkowitz et al. (2015), 'National Sleep Foundation sleep time duration recommendations'",
            documentedLimitations: [
                "Optical PPG sleep staging has ~75-85% concordance with polysomnography (PSG)",
                "Unstaged sleep data renormalizes without Restorative component"
            ],
            nonCausalityDisclaimer: "Uyku skoru dinlenme kalitesini değerlendirir; bu bir teşhis değil, toparlanma rehberidir."
        ),
        "Fatigue": ScientificBoundary(
            id: "FATIGUE-1",
            engineName: "FatigueEngine",
            physiologicalModel: "Muscle-specific exponential fatigue superposition with sleep-score recovery half-life modulation",
            primaryCitation: "Morton RH (1997), 'Modeling training and overtraining'; Muscle fiber mass-class decay rates",
            documentedLimitations: [
                "Involvement matrix is an anatomical model approximation per movement pattern",
                "Does not account for nutritional glycogen repletion rates directly"
            ],
            nonCausalityDisclaimer: "Kas yorgunluk projeksiyonu tahmini bir iyileşme modelidir; bu bir teşhis değil, yük dağılım kılavuzudur."
        ),
        "VitalsDeviation": ScientificBoundary(
            id: "VITALS-1",
            engineName: "VitalsEngine",
            physiologicalModel: "Multi-signal co-moving anomaly detection (HRV, RHR, Respiratory Rate, Wrist Temp)",
            primaryCitation: "Smarr et al. (2020), 'Feasibility of continuous physiological monitoring for early infection detection'",
            documentedLimitations: [
                "Co-movement indicates systemic physiological shift, not specific etiology",
                "Sensitive to environmental heat, alcohol intake, travel, and altitude"
            ],
            nonCausalityDisclaimer: "Sapma skoru fizyolojik taban çizgisindeki değişimi yansıtır; bu bir teşhis değil, bir gözlemdir — kendini nasıl hissettiğine bak, bir şikâyetin varsa hekimine danış."
        )
    ]

    static func boundary(for engine: String) -> ScientificBoundary? {
        boundaries[engine]
    }
}
