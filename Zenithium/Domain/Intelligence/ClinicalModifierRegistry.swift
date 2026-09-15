//
//  ClinicalModifierRegistry.swift
//  Zenithium
//
//  Single source of truth for clinical confidence modifiers. Spec §12.
//  Enforces deterministic epistemic adjustments, strict staleness horizons, and no medical claims.
//

import Foundation

/// A single registered clinical modifier affecting engine confidence.
struct ClinicalModifier: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let targetMarkerKey: String?
    let targetECGClassification: ECGClassification?
    let multiplier: Double
    let rationale: String
    let limitationCode: String
    let validityMonths: Int
    let suppressesHRVRecovery: Bool
    let isBlockingLimitation: Bool

    init(
        id: String,
        title: String,
        targetMarkerKey: String? = nil,
        targetECGClassification: ECGClassification? = nil,
        multiplier: Double = 1.0,
        rationale: String,
        limitationCode: String,
        validityMonths: Int,
        suppressesHRVRecovery: Bool = false,
        isBlockingLimitation: Bool = false
    ) {
        self.id = id
        self.title = title
        self.targetMarkerKey = targetMarkerKey
        self.targetECGClassification = targetECGClassification
        self.multiplier = MathSupport.clamp(multiplier, 0.0, 1.0)
        self.rationale = rationale
        self.limitationCode = limitationCode
        self.validityMonths = validityMonths
        self.suppressesHRVRecovery = suppressesHRVRecovery
        self.isBlockingLimitation = isBlockingLimitation
    }
}

enum ClinicalModifierRegistry {

    // No validated conversion exists from one laboratory result to a recovery penalty.
    // Registry entries add descriptive context only; all numeric multipliers remain neutral.
    static let hemoglobinLow = ClinicalModifier(
        id: "clinical.hemoglobin.low",
        title: "Hemoglobin referansı",
        targetMarkerKey: "hemoglobin",
        multiplier: 1.0,
        rationale: "Hemoglobin, kayıttaki laboratuvar aralığının altında. Sonucu hekiminle değerlendir. Bu değer toparlanma puanına sayısal bir ceza eklemez.",
        limitationCode: "CLINICAL-HEMOGLOBIN-LOW",
        validityMonths: 3
    )

    static let ferritinLow = ClinicalModifier(
        id: "clinical.ferritin.low",
        title: "Ferritin referansı",
        targetMarkerKey: "ferritin",
        multiplier: 1.0,
        rationale: "Ferritin, kayıttaki laboratuvar aralığının altında. Sonucu hekiminle değerlendir. Tek başına bu ölçümden yük veya toparlanma düzeltmesi hesaplanmaz.",
        limitationCode: "CLINICAL-FERRITIN-LOW",
        validityMonths: 3
    )

    static let tshShift = ClinicalModifier(
        id: "clinical.tsh.shift",
        title: "TSH referansı",
        targetMarkerKey: "tsh",
        multiplier: 1.0,
        rationale: "TSH, kayıttaki laboratuvar aralığının dışında. Sonucu hekiminle değerlendir. Bunun nabız veya HRV değişiminin nedeni olduğu söylenemez.",
        limitationCode: "CLINICAL-TSH-SHIFT",
        validityMonths: 6
    )

    static let hsCRPElevated = ClinicalModifier(
        id: "clinical.hscrp.elevated",
        title: "hs-CRP referansı",
        targetMarkerKey: "highSensitivityCRP",
        multiplier: 1.0,
        rationale: "hs-CRP, kayıttaki laboratuvar aralığının üzerinde. Sonucu hekiminle değerlendir. HRV ile aynı zamanda değişmesi neden-sonuç ilişkisi göstermez.",
        limitationCode: "CLINICAL-HSCRP-ELEVATED",
        validityMonths: 1
    )

    static let creatineKinaseSevere = ClinicalModifier(
        id: "clinical.ck.severe",
        title: "CK referansı",
        targetMarkerKey: "creatineKinase",
        multiplier: 1.0,
        rationale: "CK, kayıttaki laboratuvar aralığının üzerinde. Sonucu ve ölçümden önceki antrenmanlarını hekiminle değerlendir. CK tek başına kasların toparlanma süresini vermez.",
        limitationCode: "CLINICAL-CK-SEVERE",
        validityMonths: 1
    )

    static let ecgAtrialFibrillation = ClinicalModifier(
        id: "clinical.ecg.afib",
        title: "Atriyal Fibrilasyon Ritim Uyarısı",
        targetECGClassification: .atrialFibrillation,
        multiplier: 1.0,
        rationale: "Son 24 saatteki EKG kaydı atriyal fibrilasyon olarak sınıflandırılmış. Bu bir tanı değildir; hekiminle değerlendir. Önlem olarak bugün HRV'ye dayalı antrenman kararı gösterilmez; bu, doğrulanmış bir 24 saatlik etki modeli değildir.",
        limitationCode: "CLINICAL-ECG-AF",
        validityMonths: 1,
        suppressesHRVRecovery: true,
        isBlockingLimitation: true
    )

    static let ecgPoorReading = ClinicalModifier(
        id: "clinical.ecg.poorReading",
        title: "Okunamayan EKG",
        targetECGClassification: .inconclusivePoorReading,
        multiplier: 1.0,
        rationale: "EKG kaydı sınıflandırılamamış. Apple'ın ölçüm yönergelerini izleyerek yeniden deneyebilirsin. Bu sonuç, optik nabız veya HRV ölçümlerinin de hatalı olduğunu göstermez.",
        limitationCode: "CLINICAL-ECG-POOR-READING",
        validityMonths: 1
    )

    /// The exact comprehensive catalogue of active modifiers.
    static let allModifiers: [ClinicalModifier] = [
        hemoglobinLow,
        ferritinLow,
        tshShift,
        hsCRPElevated,
        creatineKinaseSevere,
        ecgAtrialFibrillation,
        ecgPoorReading
    ]

    static func modifier(forID id: String) -> ClinicalModifier? {
        allModifiers.first { $0.id == id }
    }

    static func modifier(forMarkerKey key: String) -> ClinicalModifier? {
        allModifiers.first { $0.targetMarkerKey == key }
    }

}
