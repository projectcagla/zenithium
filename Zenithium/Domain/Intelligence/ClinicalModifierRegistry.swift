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

    static let hemoglobinLow = ClinicalModifier(
        id: "clinical.hemoglobin.low",
        title: "Düşük Hemoglobin Güven Düzeltmesi",
        targetMarkerKey: "hemoglobin",
        multiplier: 0.85,
        rationale: "Oksijen taşıma kapasitesi düşükken aynı iş daha yüksek nabızla yapılır; nabza dayalı yük tahmini bu dönemde sistematik olarak yüksek çıkabilir.",
        limitationCode: "CLINICAL-HEMOGLOBIN-LOW",
        validityMonths: 3
    )

    static let ferritinLow = ClinicalModifier(
        id: "clinical.ferritin.low",
        title: "Düşük Ferritin Güven Düzeltmesi",
        targetMarkerKey: "ferritin",
        multiplier: 0.88,
        rationale: "Oksijen taşıma ve hücresel enerji kapasitesi düşükken aynı iş daha yüksek kardiyovasküler stresle karşılanır; yük tahmini sistematik olarak yüksek çıkabilir.",
        limitationCode: "CLINICAL-FERRITIN-LOW",
        validityMonths: 3
    )

    static let tshShift = ClinicalModifier(
        id: "clinical.tsh.shift",
        title: "Tiroit Taban Çizgisi Kayması",
        targetMarkerKey: "tsh",
        multiplier: 0.85,
        rationale: "Tiroit durumu dinlenik nabız ve HRV taban çizgilerini kaydırır; bu dönemin tabanı öncekiyle doğrudan kıyaslanamaz.",
        limitationCode: "CLINICAL-TSH-SHIFT",
        validityMonths: 6
    )

    static let hsCRPElevated = ClinicalModifier(
        id: "clinical.hscrp.elevated",
        title: "Sistemik İnflamasyon HRV Baskılanması",
        targetMarkerKey: "highSensitivityCRP",
        multiplier: 0.90,
        rationale: "Sistemik inflamasyon HRV'yi antrenman yükünden bağımsız olarak baskılar.",
        limitationCode: "CLINICAL-HSCRP-ELEVATED",
        validityMonths: 1
    )

    static let creatineKinaseSevere = ClinicalModifier(
        id: "clinical.ck.severe",
        title: "Aşırı Yüksek Kreatin Kinaz",
        targetMarkerKey: "creatineKinase",
        multiplier: 1.0,
        rationale: "Kas toparlanma modeli normal klerens varsayar; aşırı yüksek CK değerinde toparlanma süresi uzayabilir.",
        limitationCode: "CLINICAL-CK-SEVERE",
        validityMonths: 1
    )

    static let ecgAtrialFibrillation = ClinicalModifier(
        id: "clinical.ecg.afib",
        title: "Atriyal Fibrilasyon Ritim Uyarısı",
        targetECGClassification: .atrialFibrillation,
        multiplier: 1.0,
        rationale: "Atriyal fibrilasyon sırasında HRV otonom tonusu değil ritim düzensizliğini ölçer; bu kayıt geçerliyken HRV'den toparlanma skoru üretilmez.",
        limitationCode: "CLINICAL-ECG-AF",
        validityMonths: 1,
        suppressesHRVRecovery: true,
        isBlockingLimitation: true
    )

    static let ecgPoorReading = ClinicalModifier(
        id: "clinical.ecg.poorReading",
        title: "Zayıf Elektrot Teması",
        targetECGClassification: .inconclusivePoorReading,
        multiplier: 0.95,
        rationale: "Elektrot teması zayıf; aynı bilekten alınan optik ölçümler de gürültülü olabilir.",
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

    // MARK: - User Defaults Storage for Disabled Modifiers

    private static let disabledModifiersDefaultsKey = "zenithium.clinical.disabledModifiers"

    private static var userDefaults: UserDefaults {
        AppGroup.defaults ?? UserDefaults.standard
    }

    static func disabledModifierIDs() -> Set<String> {
        let array = userDefaults.stringArray(forKey: disabledModifiersDefaultsKey) ?? []
        return Set(array)
    }

    static func setModifier(id: String, isEnabled: Bool) {
        var set = disabledModifierIDs()
        if isEnabled {
            set.remove(id)
        } else {
            set.insert(id)
        }
        userDefaults.set(Array(set), forKey: disabledModifiersDefaultsKey)
    }
}
