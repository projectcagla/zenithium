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
    let referenceIDs: [String]
    let documentedLimitations: [String]
    let nonCausalityDisclaimer: String

    init(
        id: String,
        engineName: String,
        physiologicalModel: String,
        primaryCitation: String,
        referenceIDs: [String] = [],
        documentedLimitations: [String],
        nonCausalityDisclaimer: String
    ) {
        self.id = id
        self.engineName = engineName
        self.physiologicalModel = physiologicalModel
        self.primaryCitation = primaryCitation
        self.referenceIDs = referenceIDs
        self.documentedLimitations = documentedLimitations
        self.nonCausalityDisclaimer = nonCausalityDisclaimer
    }
}

enum ScientificBoundaryRegistry {

    static let boundaries: [String: ScientificBoundary] = [
        "Recovery": ScientificBoundary(
            id: "RECOVERY-1",
            engineName: "RecoveryEngine",
            physiologicalModel: "Kişiselleştirilmiş taban çizgileriyle çoklu biyometrik üstel hareketli z-skoru (HRV, Dinlenik Nabız, Sıcaklık, Uyku)",
            primaryCitation: "Plews et al. (2013), 'Training adaptation and heart rate variability in elite endurance athletes'",
            referenceIDs: ["PLEWS-2013", "BUCHHEIT-2014"],
            documentedLimitations: [
                "Topluluk dışı kişisel puanlama için en az 4 gecelik uyku HRV verisi gerektirir",
                "Akut psikolojik stres ile fiziksel antrenman yorgunluğunu birbirinden ayıramaz",
                "Bilek sıcaklığı Apple Watch Series 8+ / Ultra sensör donanımına bağlıdır"
            ],
            nonCausalityDisclaimer: "Toparlanma skoru otonom sinir sistemi dengesini yansıtan bir gözlemdir; bu bir teşhis değil, antrenman hazırbulunuşluk kılavuzudur."
        ),
        "TrainingLoad": ScientificBoundary(
            id: "LOAD-1",
            engineName: "TrainingLoadEngine",
            physiologicalModel: "Üstel ağırlıklı Banister etki-tepki modeli (Akut: 7 gün, Kronik: 28 gün, ACWR)",
            primaryCitation: "Banister EW (1991), 'Modeling Elite Athletic Performance'; Gabbett TJ (2016), 'The training—injury prevention paradox'",
            referenceIDs: [
                "BANISTER-1991",
                "FOSTER-1998",
                "IMPELLIZZERI-2019",
                "GABBETT-2016",
                "HULIN-2016",
                "LOLLI-2019"
            ],
            documentedLimitations: [
                "Kardiyo dışı seanslar (ör. izometrik kuvvet) yalnızca nabız üzerinden metabolik zorlanmayı eksik tahmin edebilir",
                "Giyilebilir cihazsız kuvvet seansları için kesintisiz RPE kaydı gerektirir",
                "ACWR bir yük izleme yöntemidir; mutlak yaralanma tahmincisi değildir"
            ],
            nonCausalityDisclaimer: "Antrenman yükü ve ACWR, aşırı yüklenme riskini yönetmek için bir kılavuzdur; doğrudan yaralanma tahmini yapmaz."
        ),
        "SleepScore": ScientificBoundary(
            id: "SLEEP-1",
            engineName: "SleepScoreEngine",
            physiologicalModel: "Çok bileşenli uyku mimarisi (Süre, Verimlilik, Onarıcı Uyku % (Derin+REM), Orta Nokta Tutarlılığı)",
            primaryCitation: "Hirshkowitz et al. (2015), 'National Sleep Foundation sleep time duration recommendations'",
            referenceIDs: [
                "WATSON-2015",
                "HIRSHKOWITZ-2015",
                "ROENNEBERG-2003"
            ],
            documentedLimitations: [
                "Optik PPG uyku evrelemesi polisomnografi (PSG) ile yaklaşık %75-85 uyuma sahiptir",
                "Evrelenmemiş ham uyku verisi onarıcı uyku bileşeni olmadan yeniden normalize edilir"
            ],
            nonCausalityDisclaimer: "Uyku skoru dinlenme kalitesini değerlendirir; bu bir teşhis değil, toparlanma rehberidir."
        ),
        "Fatigue": ScientificBoundary(
            id: "FATIGUE-1",
            engineName: "FatigueEngine",
            physiologicalModel: "Uyku puanı toparlanma yarı ömür modülasyonu ile kasa özgü üstel yorgunluk süperpozisyonu",
            primaryCitation: "Morton RH (1997), 'Modeling training and overtraining'; Muscle fiber mass-class decay rates",
            referenceIDs: ["MORTON-1997"],
            documentedLimitations: [
                "Katılım matrisi hareket paterni başına anatomik model yaklaşımıdır",
                "Beslenme kaynaklı glikojen yenilenme hızlarını doğrudan hesaba katmaz"
            ],
            nonCausalityDisclaimer: "Kas yorgunluk projeksiyonu tahmini bir iyileşme modelidir; bu bir teşhis değil, yük dağılım kılavuzudur."
        ),
        "VitalsDeviation": ScientificBoundary(
            id: "VITALS-1",
            engineName: "VitalsEngine",
            physiologicalModel: "Çoklu sinyal eş-hareketli anomali tespiti (HRV, Dinlenik Nabız, Solunum Hızı, Bilek Sıcaklığı)",
            primaryCitation: "Smarr et al. (2020), 'Feasibility of continuous physiological monitoring for early infection detection'",
            referenceIDs: ["SMARR-2020"],
            documentedLimitations: [
                "Eş-hareket sistemik fizyolojik değişimi gösterir; spesifik bir etiyoloji belirtmez",
                "Çevresel sıcaklık, alkol tüketimi, seyahat ve irtifaya karşı duyarlıdır"
            ],
            nonCausalityDisclaimer: "Sapma skoru fizyolojik taban çizgisindeki değişimi yansıtır; bu bir teşhis değil, bir gözlemdir — kendini nasıl hissettiğine bak, bir şikâyetin varsa hekimine danış."
        ),
        "ClinicalContext": ScientificBoundary(
            id: "CLINICAL-1",
            engineName: "ClinicalContextEngine",
            physiologicalModel: "Doğrulanmış laboratuvar belirteçleri ve Apple Watch EKG sinyallerinden türetilen çarpımsal epistemik güven çarpanları",
            primaryCitation: "Calbet et al. (2006); Peeling et al. (2008); Sassi et al. (2015) 'Advances in Heart Rate Variability Signal Analysis and AF Invalidation'",
            referenceIDs: ["KAMINSKY-2015"],
            documentedLimitations: [
                "Yalnızca güven ve ölçüm hata payı terimlerini etkiler; tıbbi teşhis koymaz",
                "Geçerlilik süresi içinde güncel tahlil/EKG kayıtları gerektirir; süresi dolan kayıtlar nötr duruma döner"
            ],
            nonCausalityDisclaimer: "Klinik bağlam bir teşhis değildir ve tıbbi iddia içermez; yalnızca biyometrik yük ve toparlanma ölçümlerinin güvenilirlik derecesini ayarlar."
        ),
        "LocomotionCost": ScientificBoundary(
            id: "LOCOMOTION-1",
            engineName: "EnduranceEngine",
            physiologicalModel: "Eğim koşu maliyeti polinom modeli (±%30 aralığında J/kg/m)",
            primaryCitation: "Minetti AE, et al. (2002), 'Energy cost of walking and running at extreme uphill and downhill slopes'",
            referenceIDs: ["MINETTI-2002"],
            documentedLimitations: [
                "Koşu bandında 10 koşucu ile ölçülmüştür; zemin ve arazi değişkenliği sonucu etkileyebilir",
                "Eğim ±%30 sınırının ötesinde ekstrapolasyon yapılmaz"
            ],
            nonCausalityDisclaimer: "Eğim düzeltmeli tempo mekanik bir enerji harcama tahminidir; fizyolojik yorgunluk ve glikojen tükenmesini doğrudan ölçmez."
        )
    ]

    static func boundary(for engine: String) -> ScientificBoundary? {
        boundaries[engine]
    }
}
