//
//  HealthDataKind.swift
//  Zenithium
//
//  The Sendable identity of every HealthKit type Zenithium reads, with no HealthKit import.
//  Spec §3 (glossary), §8 (the actor maps HealthKit types to Sendable DTOs).
//

import Foundation

/// A HealthKit data category, named in domain terms so that `Domain`, `Engines`,
/// `Orchestration` and `Views` can talk about health data without importing HealthKit.
///
/// `Health/HealthKitTypeCatalog.swift` owns the one-way mapping to `HKObjectType`.
enum HealthDataKind: String, Sendable, Codable, CaseIterable, Hashable {

    /// `.heartRateVariabilitySDNN`, milliseconds.
    case heartRateVariability

    /// `.restingHeartRate`, beats per minute.
    case restingHeartRate

    /// `.heartRate`, beats per minute, intraday series.
    case heartRate

    /// `.respiratoryRate`, breaths per minute.
    case respiratoryRate

    /// `.appleSleepingWristTemperature`, degrees Celsius.
    case wristTemperature

    /// `.oxygenSaturation`, fraction 0…1. Displayed only, never scored (§3).
    case oxygenSaturation

    /// `.sleepAnalysis` category samples.
    case sleepAnalysis

    /// `HKWorkoutType.workoutType()`.
    case workout

    var displayName: String {
        switch self {
        case .heartRateVariability:
            return "kalp atış hızı değişkenliği"
        case .restingHeartRate:
            return "dinlenik nabız"
        case .heartRate:
            return "nabız"
        case .respiratoryRate:
            return "solunum hızı"
        case .wristTemperature:
            return "bilek sıcaklığı"
        case .oxygenSaturation:
            return "kandaki oksijen"
        case .sleepAnalysis:
            return "uyku analizi"
        case .workout:
            return "antrenmanlar"
        }
    }

    /// Whether Zenithium can produce a recovery score at all without this category.
    ///
    /// Spec §4.3: recovery is suppressed entirely if HRV **or** RHR is missing.
    var isRequiredForRecovery: Bool {
        switch self {
        case .heartRateVariability, .restingHeartRate:
            return true
        case .heartRate, .respiratoryRate, .wristTemperature,
             .oxygenSaturation, .sleepAnalysis, .workout:
            return false
        }
    }

    /// Whether a change in this category should trigger a recalculation.
    var triggersRecalculation: Bool {
        switch self {
        case .oxygenSaturation:
            return false
        case .heartRateVariability, .restingHeartRate, .heartRate, .respiratoryRate,
             .wristTemperature, .sleepAnalysis, .workout:
            return true
        }
    }
}
