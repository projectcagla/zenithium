//
//  DataQuality.swift
//  Zenithium
//
//  Per-record data quality. Spec §5.6 (sleep <2 h or >14 h is `.suspect`), §7 (`dataQuality`
//  is persisted on every `BiometricDayRecord`).
//

import Foundation

/// Why a record is less than fully trustworthy. Persisted alongside the quality verdict so
/// the UI can say what is missing rather than showing an unexplained asterisk.
enum DataQualityReason: String, Sendable, Codable, CaseIterable, Hashable {

    /// No overnight wear detected at all (§5.6).
    case noOvernightWear

    /// Sleep shorter than the minimum plausible night (§5.6).
    case sleepTooShort

    /// Sleep longer than the maximum plausible night (§5.6).
    case sleepTooLong

    /// Sleep was recorded but without stage detail, so `Restorative` was dropped (§5.2).
    case sleepStagesMissing

    /// Wrist temperature unsupported or unavailable, so `Z_Temp` was dropped (§4.3).
    case wristTemperatureMissing

    /// Respiratory rate unavailable, so `Z_Resp` was dropped (§4.3).
    case respiratoryRateMissing

    /// HRV missing — recovery is suppressed entirely (§4.3).
    case heartRateVariabilityMissing

    /// Resting heart rate missing — recovery is suppressed entirely (§4.3).
    case restingHeartRateMissing

    /// Fewer than 14 baseline days, so the score is blended toward the population prior (§4.2.4).
    case baselineStillCalibrating

    /// Intraday heart rate had gaps long enough to suppress strain segments (§5.3).
    case intradayHeartRateSparse

    var displayName: String {
        switch self {
        case .noOvernightWear: return "Gece verisi yok"
        case .sleepTooShort: return "Uyku 2 saatin altında"
        case .sleepTooLong: return "Uyku 14 saatin üstünde"
        case .sleepStagesMissing: return "Uyku evresi yok"
        case .wristTemperatureMissing: return "Bilek sıcaklığı yok"
        case .respiratoryRateMissing: return "Solunum hızı yok"
        case .heartRateVariabilityMissing: return "HRV yok"
        case .restingHeartRateMissing: return "İstirahat nabzı yok"
        case .baselineStillCalibrating: return "Taban çizgisi hâlâ kuruluyor"
        case .intradayHeartRateSparse: return "Nabız kaydı seyrek"
        }
    }

    /// Reasons that make the whole record suspect rather than merely partial.
    var impliesSuspect: Bool {
        switch self {
        case .sleepTooShort, .sleepTooLong, .noOvernightWear:
            return true
        case .sleepStagesMissing, .wristTemperatureMissing, .respiratoryRateMissing,
             .heartRateVariabilityMissing, .restingHeartRateMissing,
             .baselineStillCalibrating, .intradayHeartRateSparse:
            return false
        }
    }
}

/// The verdict for a day's record.
enum DataQuality: String, Sendable, Codable, CaseIterable, Hashable {

    /// Every scored input was present and plausible.
    case good

    /// One or more optional inputs were missing; weights were renormalized (§4.3).
    case partial

    /// An input was present but implausible; the record is stored but must not be scored (§5.6).
    case suspect

    /// Derives the verdict from the reasons recorded during ingest.
    static func verdict(for reasons: [DataQualityReason]) -> DataQuality {
        if reasons.contains(where: { $0.impliesSuspect }) { return .suspect }
        return reasons.isEmpty ? .good : .partial
    }

    var displayName: String {
        switch self {
        case .good: return "Tam"
        case .partial: return "Kısmi"
        case .suspect: return "Güvenilmez"
        }
    }

    /// Whether a score derived from this record may be shown.
    var isScorable: Bool {
        self != .suspect
    }
}
