//
//  OvernightData.swift
//  Zenithium
//
//  One night's ingest bundle. Spec §8 (`fetchOvernightBiometrics(for:)`), §4.3 (a metric
//  that is absent is dropped, never substituted with zero), §5.6 (edge cases).
//

import Foundation

/// Everything read for a single night, before any scoring.
///
/// Every biometric is optional. A `nil` means "not available", which the engines translate
/// into a dropped term plus renormalized weights (§4.3) — never into a zero.
struct OvernightData: Sendable, Equatable, Hashable {

    /// The sleep opportunity window the values were read for.
    let night: DateInterval

    /// The identifier of the time zone in effect at `night.start` (§5.6).
    let timeZoneIdentifier: String

    /// Heart rate variability, SDNN, milliseconds.
    let heartRateVariability: Double?

    /// Resting heart rate, beats per minute.
    let restingHeartRate: Double?

    /// Sleeping wrist temperature, degrees Celsius, absolute (ASSUMPTION BASE-3).
    let wristTemperature: Double?

    /// Respiratory rate, breaths per minute.
    let respiratoryRate: Double?

    /// Blood oxygen, fraction 0…1. Displayed only, never scored (§3).
    let oxygenSaturation: Double?

    /// Every sleep segment overlapping the night, including `.inBed` and `.awake`.
    let sleepSegments: [SleepSegment]

    /// Naps recorded elsewhere in the surrounding day, feeding `napCredit` (§5.2).
    let napSegments: [SleepSegment]

    /// Whether this device/watch pair can produce wrist temperature at all (ASSUMPTION API-1).
    ///
    /// Distinguishes "Series 6, will never have it" from "Series 9, wasn't worn last night",
    /// which the UI phrases differently even though both drop `Z_Temp`.
    let wristTemperatureSupported: Bool

    init(
        night: DateInterval,
        timeZoneIdentifier: String = "UTC",
        heartRateVariability: Double? = nil,
        restingHeartRate: Double? = nil,
        wristTemperature: Double? = nil,
        respiratoryRate: Double? = nil,
        oxygenSaturation: Double? = nil,
        sleepSegments: [SleepSegment] = [],
        napSegments: [SleepSegment] = [],
        wristTemperatureSupported: Bool = true
    ) {
        self.night = night
        self.timeZoneIdentifier = timeZoneIdentifier
        self.heartRateVariability = heartRateVariability
        self.restingHeartRate = restingHeartRate
        self.wristTemperature = wristTemperature
        self.respiratoryRate = respiratoryRate
        self.oxygenSaturation = oxygenSaturation
        self.sleepSegments = sleepSegments
        self.napSegments = napSegments
        self.wristTemperatureSupported = wristTemperatureSupported
    }

    /// An empty night — the watch was not worn (§5.6). Baselines must not advance for it.
    static func empty(night: DateInterval, timeZoneIdentifier: String) -> OvernightData {
        OvernightData(
            night: night,
            timeZoneIdentifier: timeZoneIdentifier,
            heartRateVariability: nil,
            restingHeartRate: nil,
            wristTemperature: nil,
            respiratoryRate: nil,
            oxygenSaturation: nil,
            sleepSegments: [],
            napSegments: [],
            wristTemperatureSupported: false
        )
    }

    /// True when nothing at all was recorded — the "No overnight data" state (§5.6).
    var isEmpty: Bool {
        heartRateVariability == nil
            && restingHeartRate == nil
            && wristTemperature == nil
            && respiratoryRate == nil
            && sleepSegments.isEmpty
    }

    /// The value of a baselined metric, or `nil` when it was not recorded.
    func value(for metric: MetricKind) -> Double? {
        switch metric {
        case .heartRateVariability: return heartRateVariability
        case .restingHeartRate: return restingHeartRate
        case .wristTemperature: return wristTemperature
        case .respiratoryRate: return respiratoryRate
        }
    }

    /// The quality reasons implied by what is missing, before sleep length is checked.
    var missingMetricReasons: [DataQualityReason] {
        var reasons: [DataQualityReason] = []
        if heartRateVariability == nil { reasons.append(.heartRateVariabilityMissing) }
        if restingHeartRate == nil { reasons.append(.restingHeartRateMissing) }
        if wristTemperature == nil { reasons.append(.wristTemperatureMissing) }
        if respiratoryRate == nil { reasons.append(.respiratoryRateMissing) }
        if !sleepSegments.hasStageDetail && !sleepSegments.isEmpty {
            reasons.append(.sleepStagesMissing)
        }
        return reasons
    }
}
