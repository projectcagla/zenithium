//
//  Biomarker.swift
//  Zenithium
//
//  The biomarker catalogue. Faz 23: the five hand-written markers became a fifty-marker
//  panel set so a laboratory PDF can be matched against something real.
//
//  Three things live here that the old five-case enum could not carry:
//
//  * **Synonyms.** A Turkish laboratory prints "Hemoglobin (HGB)", an English one prints
//    "Haemoglobin". Both must land on the same definition, so every marker carries the
//    names it is actually printed under.
//  * **Sex-specific ranges.** Haemoglobin, haematocrit, ferritin, creatinine and the
//    transaminases all have different reference bands by sex. Showing one band to everybody
//    was wrong.
//  * **Units.** The same marker arrives as ng/mL or nmol/L depending on the laboratory, so
//    each definition names its canonical unit and the factor every accepted unit converts by.
//
//  Spec §12 still governs everything downstream: ranges and trends only. Nothing in this
//  file interprets a value, and `contextNote` is written to describe how a number behaves in
//  training, never what to do about it.
//

import Foundation

/// A numeric range, either of which bound may be open.
struct MarkerRange: Sendable, Equatable, Hashable, Codable {

    let minimum: Double?
    let maximum: Double?

    init(minimum: Double?, maximum: Double?) {
        self.minimum = minimum
        self.maximum = maximum
    }

    /// The empty range, bounded on neither side.
    static let unbounded = MarkerRange(minimum: nil, maximum: nil)

    /// Whether the range constrains anything at all.
    var isBounded: Bool { minimum != nil || maximum != nil }

    /// Whether a value sits inside the range. An open bound never excludes.
    func contains(_ value: Double) -> Bool {
        if let minimum, value < minimum { return false }
        if let maximum, value > maximum { return false }
        return true
    }

    /// Where a value sits across the range, 0…1, or `nil` when the range is not bounded on
    /// both sides. Used to position a marker dot; never to judge the value.
    func normalizedPosition(of value: Double) -> Double? {
        guard let minimum, let maximum, maximum > minimum else { return nil }
        let position = (value - minimum) / (maximum - minimum)
        return min(max(position, 0), 1)
    }
}

/// Which laboratory panel a marker belongs to. Drives grouping in the picker and the
/// completeness read-out ("you have ferritin but no transferrin saturation").
enum BiomarkerPanel: String, Sendable, Codable, Hashable, CaseIterable {

    case lipid
    case hematology
    case iron
    case thyroid
    case metabolic
    case organ
    case hormone
    case micronutrient
    case inflammation

    var displayName: String {
        switch self {
        case .lipid: return "Lipit"
        case .hematology: return "Hematoloji"
        case .iron: return "Demir ve B vitaminleri"
        case .thyroid: return "Tiroit"
        case .metabolic: return "Metabolik"
        case .organ: return "Karaciğer ve böbrek"
        case .hormone: return "Hormon"
        case .micronutrient: return "Mineral ve vitamin"
        case .inflammation: return "İltihap ve kas hasarı"
        }
    }

    /// Display order, which is the order a laboratory report usually prints them in.
    var order: Int {
        switch self {
        case .lipid: return 0
        case .hematology: return 1
        case .iron: return 2
        case .thyroid: return 3
        case .metabolic: return 4
        case .organ: return 5
        case .hormone: return 6
        case .micronutrient: return 7
        case .inflammation: return 8
        }
    }
}

/// One unit a marker can be reported in, and the factor that converts it to the marker's
/// canonical unit. `factorToCanonical` is 1 for the canonical unit itself.
struct BiomarkerUnit: Sendable, Equatable, Hashable {

    let symbol: String

    /// Multiply a value in this unit by this to reach the canonical unit.
    let factorToCanonical: Double

    /// Spellings a laboratory might print instead of `symbol`, already normalised-ish.
    /// Matching goes through `BiomarkerCatalog.normalize`, so case and punctuation are free.
    let aliases: [String]

    init(symbol: String, factorToCanonical: Double, aliases: [String] = []) {
        self.symbol = symbol
        self.factorToCanonical = factorToCanonical
        self.aliases = aliases
    }

    /// The value expressed in the marker's canonical unit.
    func canonicalValue(of value: Double) -> Double {
        value * factorToCanonical
    }

    /// Whether a printed unit string names this unit.
    func matches(_ printed: String) -> Bool {
        let normalized = BiomarkerCatalog.normalize(printed)
        guard !normalized.isEmpty else { return false }
        if BiomarkerCatalog.normalize(symbol) == normalized { return true }
        return aliases.contains { BiomarkerCatalog.normalize($0) == normalized }
    }
}

/// A reference band that may differ by sex.
///
/// `shared` covers markers where it does not; `male`/`female` cover the ones where it does.
/// Users who have not disclosed a sex get the wider of the two bands, so nothing is flagged
/// as outside a range that might not apply to them.
struct SexSpecificRange: Sendable, Equatable, Hashable {

    private let shared: MarkerRange?
    private let male: MarkerRange?
    private let female: MarkerRange?

    init(shared: MarkerRange) {
        self.shared = shared
        self.male = nil
        self.female = nil
    }

    init(male: MarkerRange, female: MarkerRange) {
        self.shared = nil
        self.male = male
        self.female = female
    }

    private init() {
        self.shared = nil
        self.male = nil
        self.female = nil
    }

    /// No published band for this marker.
    static let none = SexSpecificRange()

    /// Whether the marker has any band at all.
    var exists: Bool { shared != nil || male != nil }

    /// Whether the two sexes are given different bands.
    var isSexSpecific: Bool { shared == nil && male != nil }

    /// The band to show a given user.
    func range(for sex: BiologicalSexValue) -> MarkerRange {
        if let shared { return shared }
        guard let male, let female else { return .unbounded }
        switch sex {
        case .male: return male
        case .female: return female
        case .other, .notSet: return SexSpecificRange.widest(male, female)
        }
    }

    /// The union of two bands — the conservative choice when sex is unknown.
    private static func widest(_ a: MarkerRange, _ b: MarkerRange) -> MarkerRange {
        let minimum: Double?
        switch (a.minimum, b.minimum) {
        case (let x?, let y?): minimum = Swift.min(x, y)
        default: minimum = nil
        }
        let maximum: Double?
        switch (a.maximum, b.maximum) {
        case (let x?, let y?): maximum = Swift.max(x, y)
        default: maximum = nil
        }
        return MarkerRange(minimum: minimum, maximum: maximum)
    }
}

/// Everything Zenithium knows about one biomarker.
struct BiomarkerDefinition: Sendable, Equatable, Hashable, Identifiable {

    /// Stable persistence key. Never localised, never renamed.
    let key: String

    let displayName: String
    let accessibilityName: String
    let panel: BiomarkerPanel

    /// Accepted units, canonical first.
    let units: [BiomarkerUnit]

    let referenceRange: SexSpecificRange
    let optimalRange: SexSpecificRange
    let fractionDigits: Int

    /// How long a value stays informative, in months. Drives the "this is getting old"
    /// prompt — not a recommendation to test, just an age read-out.
    let retestMonths: Int

    /// Names this marker is printed under on a laboratory report, Turkish and English.
    let synonyms: [String]

    /// How the number behaves in a training context. Never advice, never a target.
    let contextNote: String?

    var id: String { key }

    var canonicalUnit: BiomarkerUnit { units[0] }

    /// Whether a printed unit is one this marker accepts.
    func unit(matching printed: String) -> BiomarkerUnit? {
        units.first { $0.matches(printed) }
    }
}

enum BiomarkerCatalog {

    /// Every known marker, in panel order.
    static let all: [BiomarkerDefinition] = [
        BiomarkerDefinition(
            key: "totalCholesterol",
            displayName: "Total Kolesterol",
            accessibilityName: "Total kolesterol",
            panel: .lipid,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 38.67, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 200.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 180.0)),
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["total kolesterol", "kolesterol total", "kolesterol", "total cholesterol", "cholesterol total", "t kolesterol"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "ldlCholesterol",
            displayName: "LDL Kolesterol",
            accessibilityName: "Düşük yoğunluklu lipoprotein kolesterol",
            panel: .lipid,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 38.67, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 130.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 100.0)),
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["ldl kolesterol", "ldl c", "ldl cholesterol", "ldl", "ldl kolesterol hesaplanmis", "ldl kolesterol direkt"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "hdlCholesterol",
            displayName: "HDL Kolesterol",
            accessibilityName: "Yüksek yoğunluklu lipoprotein kolesterol",
            panel: .lipid,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 38.67, aliases: [])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 40.0, maximum: nil), female: MarkerRange(minimum: 50.0, maximum: nil)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 60.0, maximum: nil)),
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["hdl kolesterol", "hdl c", "hdl cholesterol", "hdl"],
            contextNote: "Dayanıklılık antrenmanı hacmiyle birlikte yükselme eğilimi gösteren tek lipit değeri."
        ),
        BiomarkerDefinition(
            key: "triglycerides",
            displayName: "Trigliserid",
            accessibilityName: "Trigliserid",
            panel: .lipid,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 88.57, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 150.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 100.0)),
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["trigliserid", "trigliserit", "triglycerides", "tg", "trigliserid duzeyi"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "apoB",
            displayName: "ApoB",
            accessibilityName: "Apolipoprotein B",
            panel: .lipid,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "g/L", factorToCanonical: 100.0, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 40.0, maximum: 125.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 40.0, maximum: 80.0)),
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["apo b", "apob", "apolipoprotein b", "apolipoprotein b 100"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "lipoproteinA",
            displayName: "Lp(a)",
            accessibilityName: "Lipoprotein küçük a",
            panel: .lipid,
            units: [
                BiomarkerUnit(symbol: "nmol/L", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 2.15, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 75.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 50.0)),
            fractionDigits: 0,
            retestMonths: 60,
            synonyms: ["lp a", "lipoprotein a", "lpa"],
            contextNote: "Büyük ölçüde kalıtsal; ömürde bir kez ölçülmesi genelde yeterli sayılır."
        ),
        BiomarkerDefinition(
            key: "nonHdlCholesterol",
            displayName: "Non-HDL Kolesterol",
            accessibilityName: "HDL dışı kolesterol",
            panel: .lipid,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 38.67, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 160.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 130.0)),
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["non hdl kolesterol", "non hdl", "nonhdl kolesterol"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "hemoglobin",
            displayName: "Hemoglobin",
            accessibilityName: "Hemoglobin",
            panel: .hematology,
            units: [
                BiomarkerUnit(symbol: "g/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "g/L", factorToCanonical: 0.1, aliases: [])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 13.5, maximum: 17.5), female: MarkerRange(minimum: 12.0, maximum: 15.5)),
            optimalRange: SexSpecificRange(male: MarkerRange(minimum: 14.0, maximum: 16.5), female: MarkerRange(minimum: 12.5, maximum: 15.0)),
            fractionDigits: 1,
            retestMonths: 6,
            synonyms: ["hemoglobin", "hgb", "hb", "haemoglobin", "hemoglobin hb"],
            contextNote: "Oksijen taşıma kapasitesinin doğrudan sınırı; dayanıklılık performansıyla ilişkisi en güçlü hematoloji değeri."
        ),
        BiomarkerDefinition(
            key: "hematocrit",
            displayName: "Hematokrit",
            accessibilityName: "Hematokrit",
            panel: .hematology,
            units: [
                BiomarkerUnit(symbol: "%", factorToCanonical: 1.0, aliases: ["yuzde"]),
                BiomarkerUnit(symbol: "L/L", factorToCanonical: 100.0, aliases: [])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 40.0, maximum: 52.0), female: MarkerRange(minimum: 36.0, maximum: 47.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 6,
            synonyms: ["hematokrit", "hct", "htc", "haematocrit"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "redBloodCells",
            displayName: "Eritrosit",
            accessibilityName: "Kırmızı kan hücresi sayısı",
            panel: .hematology,
            units: [
                BiomarkerUnit(symbol: "10⁶/µL", factorToCanonical: 1.0, aliases: ["10e6 ul", "milyon ul", "m ul", "x10 6 ul"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 4.5, maximum: 5.9), female: MarkerRange(minimum: 4.1, maximum: 5.1)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 2,
            retestMonths: 6,
            synonyms: ["eritrosit", "rbc", "kirmizi kan hucresi", "eritrosit sayisi"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "whiteBloodCells",
            displayName: "Lökosit",
            accessibilityName: "Beyaz kan hücresi sayısı",
            panel: .hematology,
            units: [
                BiomarkerUnit(symbol: "10³/µL", factorToCanonical: 1.0, aliases: ["10e3 ul", "bin ul", "k ul", "x10 3 ul"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 4.0, maximum: 10.5)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 6,
            synonyms: ["lokosit", "wbc", "beyaz kure", "beyaz kan hucresi", "lokosit sayisi"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "platelets",
            displayName: "Trombosit",
            accessibilityName: "Trombosit sayısı",
            panel: .hematology,
            units: [
                BiomarkerUnit(symbol: "10³/µL", factorToCanonical: 1.0, aliases: ["10e3 ul", "bin ul", "k ul"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 150.0, maximum: 400.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 6,
            synonyms: ["trombosit", "plt", "platelet", "trombosit sayisi"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "mcv",
            displayName: "MCV",
            accessibilityName: "Ortalama eritrosit hacmi",
            panel: .hematology,
            units: [
                BiomarkerUnit(symbol: "fL", factorToCanonical: 1.0, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 80.0, maximum: 100.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 6,
            synonyms: ["mcv", "ortalama eritrosit hacmi"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "rdw",
            displayName: "RDW",
            accessibilityName: "Eritrosit dağılım genişliği",
            panel: .hematology,
            units: [
                BiomarkerUnit(symbol: "%", factorToCanonical: 1.0, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 11.5, maximum: 14.5)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 6,
            synonyms: ["rdw", "rdw cv", "eritrosit dagilim genisligi"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "neutrophils",
            displayName: "Nötrofil",
            accessibilityName: "Nötrofil sayısı",
            panel: .hematology,
            units: [
                BiomarkerUnit(symbol: "10³/µL", factorToCanonical: 1.0, aliases: ["10e3 ul", "bin ul", "k ul"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 1.8, maximum: 7.7)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 6,
            synonyms: ["notrofil", "neu", "neut", "notrofil sayisi", "absolute neutrophil"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "lymphocytes",
            displayName: "Lenfosit",
            accessibilityName: "Lenfosit sayısı",
            panel: .hematology,
            units: [
                BiomarkerUnit(symbol: "10³/µL", factorToCanonical: 1.0, aliases: ["10e3 ul", "bin ul", "k ul"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 1.0, maximum: 4.8)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 6,
            synonyms: ["lenfosit", "lym", "lymph", "lenfosit sayisi"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "ferritin",
            displayName: "Ferritin",
            accessibilityName: "Ferritin",
            panel: .iron,
            units: [
                BiomarkerUnit(symbol: "ng/mL", factorToCanonical: 1.0, aliases: ["ug l", "µg/L", "mcg l"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 30.0, maximum: 400.0), female: MarkerRange(minimum: 15.0, maximum: 200.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 50.0, maximum: 150.0)),
            fractionDigits: 0,
            retestMonths: 6,
            synonyms: ["ferritin", "ferritin duzeyi", "serum ferritin"],
            contextNote: "Dayanıklılık sporcularında en sık düşük çıkan değer; demir depolarını yansıtır."
        ),
        BiomarkerDefinition(
            key: "serumIron",
            displayName: "Serum Demir",
            accessibilityName: "Serum demiri",
            panel: .iron,
            units: [
                BiomarkerUnit(symbol: "µg/dL", factorToCanonical: 1.0, aliases: ["ug dl", "mcg dl"]),
                BiomarkerUnit(symbol: "µmol/L", factorToCanonical: 5.587, aliases: ["umol l"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 60.0, maximum: 170.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 6,
            synonyms: ["serum demir", "demir", "iron", "serum demiri"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "tibc",
            displayName: "TDBK",
            accessibilityName: "Total demir bağlama kapasitesi",
            panel: .iron,
            units: [
                BiomarkerUnit(symbol: "µg/dL", factorToCanonical: 1.0, aliases: ["ug dl", "mcg dl"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 240.0, maximum: 450.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 6,
            synonyms: ["tdbk", "tibc", "total demir baglama kapasitesi", "demir baglama kapasitesi"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "transferrinSaturation",
            displayName: "Transferrin Satürasyonu",
            accessibilityName: "Transferrin satürasyonu",
            panel: .iron,
            units: [
                BiomarkerUnit(symbol: "%", factorToCanonical: 1.0, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 20.0, maximum: 50.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 25.0, maximum: 45.0)),
            fractionDigits: 0,
            retestMonths: 6,
            synonyms: ["transferrin saturasyonu", "transferrin satürasyon", "tsat", "satürasyon indeksi", "saturasyon indeksi"],
            contextNote: "Ferritin tek başına yanıltıcı olabilir; demir tablosunu bu ikisi birlikte anlatır."
        ),
        BiomarkerDefinition(
            key: "vitaminB12",
            displayName: "B12 Vitamini",
            accessibilityName: "B12 vitamini",
            panel: .iron,
            units: [
                BiomarkerUnit(symbol: "pg/mL", factorToCanonical: 1.0, aliases: ["ng l"]),
                BiomarkerUnit(symbol: "pmol/L", factorToCanonical: 1.355, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 200.0, maximum: 900.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 400.0, maximum: 900.0)),
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["b12", "vitamin b12", "b12 vitamini", "kobalamin", "vit b12"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "folate",
            displayName: "Folat",
            accessibilityName: "Folat",
            panel: .iron,
            units: [
                BiomarkerUnit(symbol: "ng/mL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "nmol/L", factorToCanonical: 0.4413, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 3.0, maximum: 20.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 8.0, maximum: 20.0)),
            fractionDigits: 1,
            retestMonths: 12,
            synonyms: ["folat", "folik asit", "folate", "vitamin b9"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "tsh",
            displayName: "TSH",
            accessibilityName: "Tiroit uyarıcı hormon",
            panel: .thyroid,
            units: [
                BiomarkerUnit(symbol: "mIU/L", factorToCanonical: 1.0, aliases: ["uiu ml", "µIU/mL", "miu l"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 0.4, maximum: 4.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 0.5, maximum: 2.5)),
            fractionDigits: 2,
            retestMonths: 12,
            synonyms: ["tsh", "tiroid stimulan hormon", "tiroit uyarici hormon", "thyrotropin"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "freeT4",
            displayName: "Serbest T4",
            accessibilityName: "Serbest tiroksin",
            panel: .thyroid,
            units: [
                BiomarkerUnit(symbol: "ng/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "pmol/L", factorToCanonical: 0.0777, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 0.8, maximum: 1.8)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 2,
            retestMonths: 12,
            synonyms: ["serbest t4", "st4", "ft4", "free t4", "serbest tiroksin", "t4 serbest"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "freeT3",
            displayName: "Serbest T3",
            accessibilityName: "Serbest triiyodotironin",
            panel: .thyroid,
            units: [
                BiomarkerUnit(symbol: "pg/mL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "pmol/L", factorToCanonical: 0.651, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 2.3, maximum: 4.2)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 2,
            retestMonths: 12,
            synonyms: ["serbest t3", "st3", "ft3", "free t3", "t3 serbest"],
            contextNote: "Uzun süreli düşük enerji alımında düşme eğilimi gösterir; antrenman yükünden çok beslenme yeterliliğiyle ilişkilendirilir."
        ),
        BiomarkerDefinition(
            key: "fastingGlucose",
            displayName: "Açlık Glukozu",
            accessibilityName: "Açlık kan şekeri",
            panel: .metabolic,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 18.016, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 70.0, maximum: 99.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 75.0, maximum: 90.0)),
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["aclik glukozu", "aclik kan sekeri", "glukoz", "glikoz", "fasting glucose", "kan sekeri", "aclik glukoz"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "hba1c",
            displayName: "HbA1c",
            accessibilityName: "Hemoglobin A1c",
            panel: .metabolic,
            units: [
                BiomarkerUnit(symbol: "%", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mmol/mol", factorToCanonical: 0.0915, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 4.0, maximum: 5.6)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 4.6, maximum: 5.3)),
            fractionDigits: 1,
            retestMonths: 12,
            synonyms: ["hba1c", "hb a1c", "glikozillenmis hemoglobin", "a1c", "hemoglobin a1c"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "fastingInsulin",
            displayName: "Açlık İnsülini",
            accessibilityName: "Açlık insülini",
            panel: .metabolic,
            units: [
                BiomarkerUnit(symbol: "µIU/mL", factorToCanonical: 1.0, aliases: ["uiu ml", "miu l"]),
                BiomarkerUnit(symbol: "pmol/L", factorToCanonical: 0.1443, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 2.0, maximum: 19.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 2.0, maximum: 6.0)),
            fractionDigits: 1,
            retestMonths: 12,
            synonyms: ["aclik insulini", "insulin", "aclik insulin", "fasting insulin"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "uricAcid",
            displayName: "Ürik Asit",
            accessibilityName: "Ürik asit",
            panel: .metabolic,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "µmol/L", factorToCanonical: 0.0168, aliases: ["umol l"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 3.4, maximum: 7.0), female: MarkerRange(minimum: 2.4, maximum: 6.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 12,
            synonyms: ["urik asit", "uric acid", "ürik asit"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "alt",
            displayName: "ALT",
            accessibilityName: "Alanin aminotransferaz",
            panel: .organ,
            units: [
                BiomarkerUnit(symbol: "U/L", factorToCanonical: 1.0, aliases: ["iu l"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: nil, maximum: 41.0), female: MarkerRange(minimum: nil, maximum: 33.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["alt", "sgpt", "alanin aminotransferaz", "alt sgpt"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "ast",
            displayName: "AST",
            accessibilityName: "Aspartat aminotransferaz",
            panel: .organ,
            units: [
                BiomarkerUnit(symbol: "U/L", factorToCanonical: 1.0, aliases: ["iu l"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: nil, maximum: 40.0), female: MarkerRange(minimum: nil, maximum: 32.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["ast", "sgot", "aspartat aminotransferaz", "ast sgot"],
            contextNote: "Ağır antrenmandan sonraki 48 saatte kas kaynaklı olarak yükselebilir; ölçüm zamanlaması önemlidir."
        ),
        BiomarkerDefinition(
            key: "ggt",
            displayName: "GGT",
            accessibilityName: "Gama glutamil transferaz",
            panel: .organ,
            units: [
                BiomarkerUnit(symbol: "U/L", factorToCanonical: 1.0, aliases: ["iu l"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 8.0, maximum: 61.0), female: MarkerRange(minimum: 5.0, maximum: 36.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["ggt", "gama glutamil transferaz", "g gt"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "creatinine",
            displayName: "Kreatinin",
            accessibilityName: "Kreatinin",
            panel: .organ,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "µmol/L", factorToCanonical: 0.0113, aliases: ["umol l"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 0.7, maximum: 1.3), female: MarkerRange(minimum: 0.6, maximum: 1.1)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 2,
            retestMonths: 12,
            synonyms: ["kreatinin", "creatinine", "serum kreatinin"],
            contextNote: "Kas kütlesiyle birlikte yükselir; sporcularda referans üstü çıkması tek başına böbrek göstergesi değildir."
        ),
        BiomarkerDefinition(
            key: "egfr",
            displayName: "eGFR",
            accessibilityName: "Tahmini glomerüler filtrasyon hızı",
            panel: .organ,
            units: [
                BiomarkerUnit(symbol: "mL/dk/1.73m²", factorToCanonical: 1.0, aliases: ["ml dk", "ml min 1 73", "ml min"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 90.0, maximum: nil)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["egfr", "gfr", "tahmini gfr", "glomeruler filtrasyon"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "bun",
            displayName: "Üre",
            accessibilityName: "Kan üre azotu",
            panel: .organ,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 7.0, maximum: 20.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["bun", "kan ure azotu", "ure azotu", "uree"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "albumin",
            displayName: "Albümin",
            accessibilityName: "Albümin",
            panel: .organ,
            units: [
                BiomarkerUnit(symbol: "g/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "g/L", factorToCanonical: 0.1, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 3.5, maximum: 5.2)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 12,
            synonyms: ["albumin", "albümin", "serum albumin"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "testosteroneTotal",
            displayName: "Total Testosteron",
            accessibilityName: "Total testosteron",
            panel: .hormone,
            units: [
                BiomarkerUnit(symbol: "ng/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "nmol/L", factorToCanonical: 28.84, aliases: []),
                BiomarkerUnit(symbol: "ng/mL", factorToCanonical: 100.0, aliases: [])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 300.0, maximum: 1000.0), female: MarkerRange(minimum: 15.0, maximum: 70.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["total testosteron", "testosteron", "testosterone", "testosteron total", "serbest testosteron disinda"],
            contextNote: "Uzun süreli yüksek yük ve düşük enerji alımı dönemlerinde düşme eğilimi gösterir."
        ),
        BiomarkerDefinition(
            key: "cortisolMorning",
            displayName: "Kortizol (sabah)",
            accessibilityName: "Sabah kortizolü",
            panel: .hormone,
            units: [
                BiomarkerUnit(symbol: "µg/dL", factorToCanonical: 1.0, aliases: ["ug dl", "mcg dl"]),
                BiomarkerUnit(symbol: "nmol/L", factorToCanonical: 0.0363, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 6.0, maximum: 23.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 12,
            synonyms: ["kortizol", "cortisol", "kortizol sabah", "sabah kortizol", "kortizol 08 00"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "shbg",
            displayName: "SHBG",
            accessibilityName: "Seks hormonu bağlayıcı globulin",
            panel: .hormone,
            units: [
                BiomarkerUnit(symbol: "nmol/L", factorToCanonical: 1.0, aliases: [])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 10.0, maximum: 57.0), female: MarkerRange(minimum: 18.0, maximum: 144.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["shbg", "seks hormon baglayici globulin"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "dheas",
            displayName: "DHEA-S",
            accessibilityName: "Dehidroepiandrosteron sülfat",
            panel: .hormone,
            units: [
                BiomarkerUnit(symbol: "µg/dL", factorToCanonical: 1.0, aliases: ["ug dl", "mcg dl"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 80.0, maximum: 560.0), female: MarkerRange(minimum: 35.0, maximum: 430.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["dhea s", "dheas", "dhea sulfat", "dehidroepiandrosteron"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "vitaminD",
            displayName: "D Vitamini",
            accessibilityName: "Yirmi beş hidroksi D vitamini",
            panel: .micronutrient,
            units: [
                BiomarkerUnit(symbol: "ng/mL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "nmol/L", factorToCanonical: 0.4006, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 30.0, maximum: 100.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 40.0, maximum: 60.0)),
            fractionDigits: 0,
            retestMonths: 6,
            synonyms: ["d vitamini", "vitamin d", "25 oh vitamin d", "25 hidroksi vitamin d", "vit d", "d vit", "25 oh d"],
            contextNote: "Kuzey enlemlerinde kış aylarında düşme eğilimi belirgindir; mevsimsel karşılaştırma anlamlıdır."
        ),
        BiomarkerDefinition(
            key: "magnesium",
            displayName: "Magnezyum",
            accessibilityName: "Magnezyum",
            panel: .micronutrient,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 2.43, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 1.7, maximum: 2.2)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 2,
            retestMonths: 12,
            synonyms: ["magnezyum", "magnesium"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "calcium",
            displayName: "Kalsiyum",
            accessibilityName: "Kalsiyum",
            panel: .micronutrient,
            units: [
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 4.008, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 8.6, maximum: 10.2)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 12,
            synonyms: ["kalsiyum", "calcium"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "sodium",
            displayName: "Sodyum",
            accessibilityName: "Sodyum",
            panel: .micronutrient,
            units: [
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 1.0, aliases: ["meq l"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 136.0, maximum: 145.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["sodyum", "sodium"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "potassium",
            displayName: "Potasyum",
            accessibilityName: "Potasyum",
            panel: .micronutrient,
            units: [
                BiomarkerUnit(symbol: "mmol/L", factorToCanonical: 1.0, aliases: ["meq l"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 3.5, maximum: 5.1)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 1,
            retestMonths: 12,
            synonyms: ["potasyum", "potassium"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "zinc",
            displayName: "Çinko",
            accessibilityName: "Çinko",
            panel: .micronutrient,
            units: [
                BiomarkerUnit(symbol: "µg/dL", factorToCanonical: 1.0, aliases: ["ug dl", "mcg dl"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 70.0, maximum: 120.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["cinko", "zinc"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "highSensitivityCRP",
            displayName: "hs-CRP",
            accessibilityName: "Yüksek duyarlıklı C reaktif protein",
            panel: .inflammation,
            units: [
                BiomarkerUnit(symbol: "mg/L", factorToCanonical: 1.0, aliases: []),
                BiomarkerUnit(symbol: "mg/dL", factorToCanonical: 10.0, aliases: [])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 3.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: nil, maximum: 1.0)),
            fractionDigits: 2,
            retestMonths: 12,
            synonyms: ["hs crp", "crp", "c reaktif protein", "yuksek duyarlikli crp", "hscrp", "hs c rp"],
            contextNote: "Ağır antrenmandan sonraki 72 saatte geçici olarak yükselir; ölçümü dinlenik bir güne denk getirmek gerekir."
        ),
        BiomarkerDefinition(
            key: "esr",
            displayName: "Sedimantasyon",
            accessibilityName: "Eritrosit sedimantasyon hızı",
            panel: .inflammation,
            units: [
                BiomarkerUnit(symbol: "mm/saat", factorToCanonical: 1.0, aliases: ["mm h", "mm hr", "mm saat"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: nil, maximum: 15.0), female: MarkerRange(minimum: nil, maximum: 20.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 12,
            synonyms: ["sedimantasyon", "sedim", "esr", "eritrosit sedimantasyon hizi"],
            contextNote: nil
        ),
        BiomarkerDefinition(
            key: "creatineKinase",
            displayName: "CK",
            accessibilityName: "Kreatin kinaz",
            panel: .inflammation,
            units: [
                BiomarkerUnit(symbol: "U/L", factorToCanonical: 1.0, aliases: ["iu l"])
            ],
            referenceRange: SexSpecificRange(male: MarkerRange(minimum: 39.0, maximum: 308.0), female: MarkerRange(minimum: 26.0, maximum: 192.0)),
            optimalRange: SexSpecificRange.none,
            fractionDigits: 0,
            retestMonths: 3,
            synonyms: ["ck", "cpk", "kreatin kinaz", "creatine kinase", "ck total"],
            contextNote: "Kas hasarının doğrudan göstergesi; ölçümden önceki 72 saatte yapılan antrenman kaydedilmeden yorumlanamaz."
        ),
        BiomarkerDefinition(
            key: "homocysteine",
            displayName: "Homosistein",
            accessibilityName: "Homosistein",
            panel: .inflammation,
            units: [
                BiomarkerUnit(symbol: "µmol/L", factorToCanonical: 1.0, aliases: ["umol l"])
            ],
            referenceRange: SexSpecificRange(shared: MarkerRange(minimum: 5.0, maximum: 15.0)),
            optimalRange: SexSpecificRange(shared: MarkerRange(minimum: 5.0, maximum: 9.0)),
            fractionDigits: 1,
            retestMonths: 24,
            synonyms: ["homosistein", "homocysteine", "hcy"],
            contextNote: nil
        )
    ]

    /// Key → definition, built once.
    private static let byKey: [String: BiomarkerDefinition] = {
        var table: [String: BiomarkerDefinition] = [:]
        table.reserveCapacity(all.count)
        for definition in all {
            table[definition.key] = definition
        }
        return table
    }()

    /// Normalised synonym → key. Longer synonyms are kept so the line matcher can prefer
    /// them; collisions resolve to the first definition in catalogue order, which is why
    /// generic strings like "kolesterol" sit on the marker that actually prints them.
    private static let synonymIndex: [String: String] = {
        var table: [String: String] = [:]
        for definition in all {
            for synonym in definition.synonyms {
                let normalized = normalize(synonym)
                guard !normalized.isEmpty, table[normalized] == nil else { continue }
                table[normalized] = definition.key
            }
            let name = normalize(definition.displayName)
            if table[name] == nil { table[name] = definition.key }
        }
        return table
    }()

    static func definition(forKey key: String) -> BiomarkerDefinition? {
        byKey[key]
    }

    static func definitions(in panel: BiomarkerPanel) -> [BiomarkerDefinition] {
        all.filter { $0.panel == panel }
    }

    /// Definitions grouped by panel, in panel order — what the picker renders.
    static var byPanel: [(panel: BiomarkerPanel, markers: [BiomarkerDefinition])] {
        BiomarkerPanel.allCases
            .sorted { $0.order < $1.order }
            .map { ($0, definitions(in: $0)) }
    }

    /// Exact match on a printed marker name.
    static func definition(matchingName name: String) -> BiomarkerDefinition? {
        guard let key = synonymIndex[normalize(name)] else { return nil }
        return byKey[key]
    }

    /// The best definition named anywhere inside a line of report text, with the number of
    /// matched tokens and where the name sat in the original string.
    ///
    /// Matching is token-based, not substring-based: "hb" must be its own word, otherwise
    /// every line containing "hba1c" would also look like haemoglobin. Longer synonyms win,
    /// which is what makes "hs crp" beat "crp" on a line that prints both.
    ///
    /// The returned range matters as much as the definition. "B12 Vitamini 350 pg/mL" has
    /// two numbers in it and only one of them is the result; the parser needs to know which
    /// characters belong to the marker's own name so it can ignore the digits inside them.
    static func bestMatch(inLine line: String) -> LabNameMatch? {
        bestMatch(in: normalizedMapping(line))
    }

    /// `bestMatch(inLine:)` against text that has already been normalised.
    ///
    /// The scan is driven by the *line's* tokens rather than by the catalogue: each token is
    /// looked up in `needleIndex`, which names only the synonyms that could start there. A
    /// line with eight tokens therefore considers a handful of candidates instead of all
    /// fifty definitions and every synonym under them. Yol haritası v4, A2.
    static func bestMatch(in normalized: NormalizedText) -> LabNameMatch? {
        let tokens = normalized.tokens
        guard !tokens.isEmpty else { return nil }
        let tokenTexts = tokens.map(\.text)

        if let exact = scan(
            tokens: tokens,
            tokenTexts: tokenTexts,
            in: normalized,
            index: needleIndex,
            optically: false
        ) {
            return exact
        }
        // Nothing matched cleanly. Optical recognition turns "1" into "l" and "0" into "O"
        // on exactly the marker names this catalogue is made of, so the same scan runs once
        // more over glyph-confusion classes before giving up. Adım 5.
        let folded = tokenTexts.map(opticallyFolded)
        return scan(
            tokens: tokens,
            tokenTexts: folded,
            in: normalized,
            index: opticalNeedleIndex,
            optically: true
        )
    }

    /// One pass of the matcher over a token list and an index.
    /// - Parameter optically: whether both sides have been folded across glyph confusions.
    ///   Passed rather than inferred, so the two passes cannot be told apart by accident.
    private static func scan(
        tokens: [NormalizedText.Token],
        tokenTexts: [String],
        in normalized: NormalizedText,
        index: [String: [SynonymNeedle]],
        optically: Bool
    ) -> LabNameMatch? {
        var best: LabNameMatch?
        var bestOrder = Int.max

        for position in tokenTexts.indices {
            guard let candidates = index[tokenTexts[position]] else { continue }
            for needle in candidates {
                guard position + needle.tokens.count <= tokenTexts.count else { continue }
                let needleTokens = optically ? needle.tokens.map(opticallyFolded) : needle.tokens
                guard matches(needleTokens, in: tokenTexts, at: position) else { continue }

                let first = tokens[position]
                let last = tokens[position + needle.tokens.count - 1]
                let candidate = LabNameMatch(
                    definition: needle.definition,
                    matchedTokens: needle.tokens.count,
                    matchedCharacters: needle.characterCount,
                    tokenPosition: position,
                    originalRange: normalized.originalIndex(at: first.start)..<normalized.originalIndex(after: last.end)
                )
                guard let current = best else {
                    best = candidate
                    bestOrder = needle.order
                    continue
                }
                // More tokens matched is a stronger claim; then more characters, which is
                // what separates "ldl kolesterol" from "ldl"; then the earlier match, because
                // laboratories print the marker's name before its value. `order` is the last
                // resort: it is the position this synonym had in the old catalogue-driven
                // scan, so a line that ties on everything else resolves exactly as before.
                let better: Bool
                if candidate.matchedTokens != current.matchedTokens {
                    better = candidate.matchedTokens > current.matchedTokens
                } else if candidate.matchedCharacters != current.matchedCharacters {
                    better = candidate.matchedCharacters > current.matchedCharacters
                } else if candidate.tokenPosition != current.tokenPosition {
                    better = candidate.tokenPosition < current.tokenPosition
                } else {
                    better = needle.order < bestOrder
                }
                if better {
                    best = candidate
                    bestOrder = needle.order
                }
            }
        }
        return best
    }

    /// One synonym, folded to tokens once rather than on every line.
    private struct SynonymNeedle: Sendable {

        let definition: BiomarkerDefinition

        /// The synonym's normalised tokens.
        let tokens: [String]

        /// Total characters across `tokens`, precomputed because it is a tie-break.
        let characterCount: Int

        /// Position in the catalogue-driven order the matcher used before the index existed.
        /// Kept so ties resolve identically.
        let order: Int
    }

    /// Every synonym in the catalogue, normalised once at first use.
    ///
    /// Before this existed, `normalize(synonym)` ran inside the matcher's inner loop: fifty
    /// definitions times roughly four synonyms meant about two hundred foldings *per line*,
    /// so a hundred-and-twenty-line report paid for some twenty-four thousand of them to
    /// produce a result that never changed.
    private static let needles: [SynonymNeedle] = {
        var built: [SynonymNeedle] = []
        var order = 0
        for definition in all {
            for synonym in definition.synonyms + [definition.displayName] {
                defer { order += 1 }
                let tokens = normalize(synonym).split(separator: " ").map(String.init)
                guard !tokens.isEmpty else { continue }
                built.append(
                    SynonymNeedle(
                        definition: definition,
                        tokens: tokens,
                        characterCount: tokens.reduce(0) { $0 + $1.count },
                        order: order
                    )
                )
            }
        }
        return built
    }()

    /// Needles grouped by their first token, longest first.
    ///
    /// Longest first matters: it is what lets "hs crp" be tested before "crp" on a line that
    /// prints both, without the matcher having to look at anything else.
    private static let needleIndex: [String: [SynonymNeedle]] = {
        var index: [String: [SynonymNeedle]] = [:]
        for needle in needles {
            guard let head = needle.tokens.first else { continue }
            index[head, default: []].append(needle)
        }
        for key in index.keys {
            index[key]?.sort { left, right in
                left.tokens.count == right.tokens.count
                    ? left.order < right.order
                    : left.tokens.count > right.tokens.count
            }
        }
        return index
    }()

    /// The same needles, keyed by the optically folded form of their first token.
    ///
    /// A second index rather than a looser primary one: the exact pass has to stay exact, or
    /// a report that reads cleanly starts resolving through a fuzzy rule it never needed.
    private static let opticalNeedleIndex: [String: [SynonymNeedle]] = {
        var index: [String: [SynonymNeedle]] = [:]
        for needle in needles {
            guard let head = needle.tokens.first else { continue }
            index[opticallyFolded(head), default: []].append(needle)
        }
        for key in index.keys {
            index[key]?.sort { left, right in
                left.tokens.count == right.tokens.count
                    ? left.order < right.order
                    : left.tokens.count > right.tokens.count
            }
        }
        return index
    }()

    /// How many synonyms the matcher examines for a line.
    ///
    /// Exists for the regression suite: the point of the index is that this number stays
    /// close to the line's token count rather than growing with the catalogue, and a count is
    /// something a test can assert on without measuring time. Yol haritası v4, A9.
    static func candidatesExamined(inLine line: String) -> Int {
        let tokenTexts = normalizedMapping(line).tokens.map(\.text)
        return tokenTexts.reduce(0) { $0 + (needleIndex[$1]?.count ?? 0) }
    }

    /// The total number of synonyms in the catalogue — what the old matcher walked per line.
    static var totalSynonymCount: Int { needles.count }

    /// Whether `needle` sits in `haystack` starting at `position`, without copying either.
    private static func matches(_ needle: [String], in haystack: [String], at position: Int) -> Bool {
        for offset in needle.indices where haystack[position + offset] != needle[offset] {
            return false
        }
        return true
    }

    /// Fold a printed string down to something comparable: lowercase, Turkish letters
    /// mapped to their ASCII partners, everything that is not a letter or digit becomes a
    /// space, runs of spaces collapse.
    static func normalize(_ text: String) -> String {
        normalizedMapping(text).string
    }

    /// `normalize`, but keeping a map back to the original string so a match found in
    /// normalised space can be located in the text the user actually sees.
    ///
    /// The Turkish map is explicit rather than done with `.diacriticInsensitive`, because
    /// dotless "ı" is a distinct letter and folding does not reliably reach it.
    static func normalizedMapping(_ text: String) -> NormalizedText {
        var characters: [Character] = []
        var origins: [String.Index] = []
        var lastWasSpace = true

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            // `lowercased()` can widen one character into several graphemes, so the first
            // one is taken rather than forcing a `Character` from the whole string.
            let folded = turkishFold[character] ?? character.lowercased().first ?? character
            if folded.isLetter || folded.isNumber {
                characters.append(folded)
                origins.append(index)
                lastWasSpace = false
            } else if !lastWasSpace {
                characters.append(" ")
                origins.append(index)
                lastWasSpace = true
            }
            index = text.index(after: index)
        }
        if characters.last == " " {
            characters.removeLast()
            origins.removeLast()
        }
        return NormalizedText(characters: characters, origins: origins, endIndex: text.endIndex)
    }

    private static let turkishFold: [Character: Character] = [
        "ı": "i", "İ": "i", "I": "i", "ş": "s", "Ş": "s", "ğ": "g", "Ğ": "g",
        "ü": "u", "Ü": "u", "ö": "o", "Ö": "o", "ç": "c", "Ç": "c",
        // The circumflexed vowels need both cases. With only the lowercase forms here, an
        // uppercase "Â" missed the map, fell through to `lowercased()` and came out as "â" —
        // so "ÂSİT" and "âsit" normalised to two different strings and only one of them
        // could ever match a synonym. Lab reports set marker names in capitals routinely.
        "â": "a", "Â": "a", "î": "i", "Î": "i", "û": "u", "Û": "u",
        "µ": "u"
    ]

    /// Glyph confusions optical recognition makes, folded to one representative each.
    ///
    /// Applied only to marker *names*, and only after an exact match has already failed —
    /// never to a value, where turning a "0" into an "o" would destroy the number the whole
    /// import exists to read.
    ///
    /// Checked against the catalogue rather than assumed safe: folding all 252 synonyms this
    /// way leaves 200 distinct names, exactly as many as normalisation alone produces. The
    /// fold therefore merges nothing that was previously distinguishable, which is the only
    /// property that makes a fuzzy pass safe to run at all.
    private static let opticalFold: [Character: Character] = [
        "0": "o",
        "1": "i", "l": "i", "|": "i",
        "5": "s",
        "8": "b",
        "2": "z"
    ]

    /// A normalised token, folded again across optical confusions.
    static func opticallyFolded(_ normalized: String) -> String {
        String(normalized.map { opticalFold[$0] ?? $0 })
    }
}

/// A marker name found inside a line, and where.
struct LabNameMatch: Sendable {

    let definition: BiomarkerDefinition

    /// How many whole tokens the synonym covered.
    let matchedTokens: Int

    /// How many characters those tokens held, which breaks ties between synonyms of equal
    /// token count.
    let matchedCharacters: Int

    /// Which token the match started at, counting from the start of the line.
    let tokenPosition: Int

    /// The span the name occupies in the *original* line.
    let originalRange: Range<String.Index>
}

/// A normalised string that remembers where each of its characters came from.
struct NormalizedText: Sendable {

    typealias Token = NormalizedToken

    /// The folded characters.
    let characters: [Character]

    /// `origins[i]` is the index in the original string that `characters[i]` was folded from.
    private let origins: [String.Index]

    /// The original string's end index, used when a match runs to the very end.
    private let endIndex: String.Index

    init(characters: [Character], origins: [String.Index], endIndex: String.Index) {
        self.characters = characters
        self.origins = origins
        self.endIndex = endIndex
    }

    var string: String { String(characters) }

    var isEmpty: Bool { characters.isEmpty }

    /// Whitespace-separated tokens, with their spans in normalised character offsets.
    var tokens: [NormalizedToken] {
        var result: [NormalizedToken] = []
        var start: Int?
        for (offset, character) in characters.enumerated() {
            if character == " " {
                if let begin = start {
                    result.append(NormalizedToken(text: String(characters[begin..<offset]), start: begin, end: offset))
                    start = nil
                }
            } else if start == nil {
                start = offset
            }
        }
        if let begin = start {
            result.append(NormalizedToken(text: String(characters[begin...]), start: begin, end: characters.count))
        }
        return result
    }

    /// The original index the normalised character at `offset` came from.
    func originalIndex(at offset: Int) -> String.Index {
        guard offset < origins.count else { return endIndex }
        return origins[offset]
    }

    /// The original index just past the normalised character before `offset` — the upper
    /// bound of a half-open range.
    func originalIndex(after offset: Int) -> String.Index {
        guard offset < origins.count else { return endIndex }
        return origins[offset]
    }
}

/// One whitespace-separated run inside a `NormalizedText`.
struct NormalizedToken: Sendable {
    let text: String
    let start: Int
    let end: Int
}
