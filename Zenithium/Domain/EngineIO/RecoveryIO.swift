//
//  RecoveryIO.swift
//  Zenithium
//
//  Recovery engine input and output. Spec §5.1 in full, §4.2.4 (cold start), §4.3 (missing
//  metric renormalization), §9 (outputs carry the explanation, not just the number).
//

import Foundation

/// One of the five weighted terms in `Z_total` (§5.1).
enum RecoveryDriver: String, Sendable, Codable, CaseIterable, Hashable {

    /// `Z_HRV = (HRV − μ) / σ`, weight 0.40.
    case heartRateVariability

    /// `Z_RHR = −(RHR − μ) / σ`, weight 0.25.
    case restingHeartRate

    /// `SleepNorm = clamp((SleepScore − 70) / 15, −3, +3)`, weight 0.20.
    case sleep

    /// `Z_Temp = −|ΔT / σ|`, weight 0.10.
    case temperature

    /// `Z_Resp = −(BR − μ) / σ`, weight 0.05.
    case respiratory

    /// Spec §5.1 weights.
    var specWeight: Double {
        switch self {
        case .heartRateVariability: return 0.40
        case .restingHeartRate: return 0.25
        case .sleep: return 0.20
        case .temperature: return 0.10
        case .respiratory: return 0.05
        }
    }

    /// Whether recovery is suppressed entirely when this driver is missing (§4.3).
    var isRequired: Bool {
        switch self {
        case .heartRateVariability, .restingHeartRate: return true
        case .sleep, .temperature, .respiratory: return false
        }
    }

    /// The baselined metric behind the driver, when there is one.
    var metric: MetricKind? {
        switch self {
        case .heartRateVariability: return .heartRateVariability
        case .restingHeartRate: return .restingHeartRate
        case .temperature: return .wristTemperature
        case .respiratory: return .respiratoryRate
        case .sleep: return nil
        }
    }

    var displayName: String {
        switch self {
        case .heartRateVariability: return "HRV"
        case .restingHeartRate: return "İstirahat nabzı"
        case .sleep: return "Uyku"
        case .temperature: return "Bilek sıcaklığı"
        case .respiratory: return "Solunum"
        }
    }

    var accessibilityName: String {
        switch self {
        case .heartRateVariability: return "Kalp atış hızı değişkenliği"
        case .restingHeartRate: return "İstirahat kalp atış hızı"
        case .sleep: return "Uyku puanı"
        case .temperature: return "Bilek sıcaklığı"
        case .respiratory: return "Solunum hızı"
        }
    }

    /// Plain-language phrasing for a driver pushing recovery up.
    ///
    /// Training-directive only, per §12 — nothing here describes a health status.
    var positivePhrase: String {
        switch self {
        case .heartRateVariability: return "HRV'n taban çizginin üstünde"
        case .restingHeartRate: return "istirahat nabzın taban çizginin altında"
        case .sleep: return "iyi uyudun"
        case .temperature: return "bilek sıcaklığın taban çizgine yakın"
        case .respiratory: return "solunum hızın taban çizginin altında"
        }
    }

    /// Plain-language phrasing for a driver pushing recovery down.
    var negativePhrase: String {
        switch self {
        case .heartRateVariability: return "HRV'n taban çizginin altında"
        case .restingHeartRate: return "istirahat nabzın taban çizginin üstünde"
        case .sleep: return "ihtiyacından az uyudun"
        case .temperature: return "bilek sıcaklığın taban çizginden sapmış"
        case .respiratory: return "solunum hızın taban çizginin üstünde"
        }
    }
}

/// One driver's contribution to `Z_total` (§5.1, required UI output).
struct DriverContribution: Sendable, Equatable, Hashable, Identifiable {

    let driver: RecoveryDriver

    /// `Z_i`, already clamped to `[−3, +3]`.
    let zScore: Double

    /// `w_i` — the weight actually applied, after any renormalization (§4.3).
    let weight: Double

    /// `c_i = w_i · Z_i`.
    let contribution: Double

    /// `|c_i| / Σ|c_j|`, 0…1.
    let share: Double

    /// The observed value, in the driver's canonical unit, for the detail row.
    let observedValue: Double

    /// The baseline mean the value was compared against.
    let baselineMean: Double

    /// The σ actually divided by, after flooring and prior blending.
    let baselineStandardDeviation: Double

    init(
        driver: RecoveryDriver,
        zScore: Double,
        weight: Double,
        contribution: Double,
        share: Double,
        observedValue: Double,
        baselineMean: Double,
        baselineStandardDeviation: Double
    ) {
        self.driver = driver
        self.zScore = zScore
        self.weight = weight
        self.contribution = contribution
        self.share = share
        self.observedValue = observedValue
        self.baselineMean = baselineMean
        self.baselineStandardDeviation = baselineStandardDeviation
    }

    var id: RecoveryDriver { driver }

    /// Whether the driver pushed recovery up.
    var isPositive: Bool { contribution > 0 }

    /// Plain-language phrasing for this contribution's direction (§5.1).
    var phrase: String {
        isPositive ? driver.positivePhrase : driver.negativePhrase
    }
}

/// Why recovery could not be scored.
enum RecoveryUnavailableReason: String, Sendable, Codable, Equatable, Hashable {

    /// The watch was not worn overnight (§5.6).
    case noOvernightData

    /// HRV is missing — recovery is suppressed entirely (§4.3).
    case heartRateVariabilityMissing

    /// Resting heart rate is missing — recovery is suppressed entirely (§4.3).
    case restingHeartRateMissing

    /// The night was under 2 h or over 14 h, so the record is `.suspect` (§5.6).
    case sleepImplausible

    var displayName: String {
        switch self {
        case .noOvernightData: return "Gece verisi yok"
        case .heartRateVariabilityMissing: return "HRV kaydı yok"
        case .restingHeartRateMissing: return "İstirahat nabzı kaydı yok"
        case .sleepImplausible: return "Dün geceki uyku güvenilir görünmüyor"
        }
    }

    /// Training-directive explanation, never health-status language (§12).
    var explanation: String {
        switch self {
        case .noOvernightData:
            return "Saatini gece takarak yat, yarın sabah puanını vereyim."
        case .heartRateVariabilityMissing:
            return "Toparlanma için gece HRV'si gerekiyor. Saatinde Uyku'nun açık olduğundan emin ol."
        case .restingHeartRateMissing:
            return "Toparlanma için istirahat nabzı gerekiyor. Saatinde Uyku'nun açık olduğundan emin ol."
        case .sleepImplausible:
            return "2 saatten kısa ya da 14 saatten uzun geceleri atlıyorum."
        }
    }
}

/// Whether a recovery score exists, is still calibrating, or is suppressed.
enum RecoveryAvailability: Sendable, Equatable, Hashable {

    /// A score is available.
    case scored

    /// `n < 5` valid baseline days — no score, progress shown as `n/14` (§4.2.4).
    case calibrating(daysCollected: Int, daysRequired: Int)

    /// A required input was missing or implausible.
    case unavailable(RecoveryUnavailableReason)

    var isScored: Bool {
        if case .scored = self { return true }
        return false
    }
}

/// Everything the recovery engine needs.
///
/// Every optional is genuinely optional: a `nil` drops the term and renormalizes the
/// surviving weights to sum to 1.0 (§4.3). Nothing is ever substituted with zero.
struct RecoveryInput: Sendable, Equatable {

    /// HRV against its yesterday-baseline. Required (§4.3).
    let heartRateVariability: MetricObservation?

    /// Resting heart rate against its yesterday-baseline. Required (§4.3).
    let restingHeartRate: MetricObservation?

    /// Wrist temperature against its yesterday-baseline. `scoredQuantity` is `ΔT`.
    let wristTemperature: MetricObservation?

    /// Respiratory rate against its yesterday-baseline.
    let respiratoryRate: MetricObservation?

    /// The night's sleep score, 0…100, or `nil` when the night could not be scored.
    let sleepScore: Double?

    /// Whether the night produced any data at all (§5.6).
    let hasOvernightData: Bool

    /// Whether last night's sleep was rejected as implausible (§5.6).
    let sleepWasImplausible: Bool

    init(
        heartRateVariability: MetricObservation?,
        restingHeartRate: MetricObservation?,
        wristTemperature: MetricObservation?,
        respiratoryRate: MetricObservation?,
        sleepScore: Double?,
        hasOvernightData: Bool,
        sleepWasImplausible: Bool
    ) {
        self.heartRateVariability = heartRateVariability
        self.restingHeartRate = restingHeartRate
        self.wristTemperature = wristTemperature
        self.respiratoryRate = respiratoryRate
        self.sleepScore = sleepScore
        self.hasOvernightData = hasOvernightData
        self.sleepWasImplausible = sleepWasImplausible
    }

    /// The observation backing a driver, when there is one.
    func observation(for driver: RecoveryDriver) -> MetricObservation? {
        switch driver {
        case .heartRateVariability: return heartRateVariability
        case .restingHeartRate: return restingHeartRate
        case .temperature: return wristTemperature
        case .respiratory: return respiratoryRate
        case .sleep: return nil
        }
    }
}

/// The recovery engine's result.
///
/// Spec §9: the output carries the explanation, so the UI never recomputes maths to explain
/// a score.
struct RecoveryOutput: Sendable, Equatable {

    /// Whether a score exists.
    let availability: RecoveryAvailability

    /// The 1…100 score, non-`nil` exactly when `availability` is `.scored`.
    let score: Double?

    /// The band, non-`nil` exactly when `score` is non-`nil`.
    let band: RecoveryBand?

    /// `Ceiling = 21 · (Recovery/100)^0.65` (§5.3), non-`nil` exactly when `score` is.
    let targetStrainCeiling: Double?

    /// `Z_total`, non-`nil` exactly when `score` is.
    let zTotal: Double?

    /// `w = min(n/14, 1)` across the scored drivers — the score's confidence (§4.2.4).
    let confidence: Double

    /// Every scored driver, ordered by descending `|contribution|`.
    let drivers: [DriverContribution]

    /// Drivers dropped because their input was unavailable (§4.3).
    let missingDrivers: [RecoveryDriver]

    /// Whether the surviving weights were renormalized.
    var weightsWereRenormalized: Bool { !missingDrivers.isEmpty }

    /// The strongest positive contribution, when any driver was positive.
    let topPositiveDriver: DriverContribution?

    /// The strongest negative contribution, when any driver was negative.
    let topNegativeDriver: DriverContribution?

    /// Plain-language summary of the strongest positive driver (§5.1).
    let topPositiveSummary: String?

    /// Plain-language summary of the strongest negative driver (§5.1).
    let topNegativeSummary: String?

    init(
        availability: RecoveryAvailability,
        score: Double?,
        band: RecoveryBand?,
        targetStrainCeiling: Double?,
        zTotal: Double?,
        confidence: Double,
        drivers: [DriverContribution],
        missingDrivers: [RecoveryDriver],
        topPositiveDriver: DriverContribution?,
        topNegativeDriver: DriverContribution?,
        topPositiveSummary: String?,
        topNegativeSummary: String?
    ) {
        self.availability = availability
        self.score = score
        self.band = band
        self.targetStrainCeiling = targetStrainCeiling
        self.zTotal = zTotal
        self.confidence = confidence
        self.drivers = drivers
        self.missingDrivers = missingDrivers
        self.topPositiveDriver = topPositiveDriver
        self.topNegativeDriver = topNegativeDriver
        self.topPositiveSummary = topPositiveSummary
        self.topNegativeSummary = topNegativeSummary
    }

    /// The contribution for one driver, when it was scored.
    func contribution(for driver: RecoveryDriver) -> DriverContribution? {
        drivers.first { $0.driver == driver }
    }
}
