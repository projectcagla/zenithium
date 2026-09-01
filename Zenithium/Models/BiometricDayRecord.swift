//
//  BiometricDayRecord.swift
//  Zenithium
//
//  The daily record. Spec §7 lists the stored fields; §5.6 requires the time zone in effect
//  at the record's date to be stored on the record.
//

import Foundation
import SwiftData

@Model
final class BiometricDayRecord {

    /// Local midnight of the calendar day the record is filed under. Unique (§7).
    @Attribute(.unique) var dayStart: Date

    /// The identifier of the time zone in effect at `dayStart` (§5.6).
    var timeZoneIdentifier: String

    // MARK: - Raw biometrics

    /// HRV SDNN, milliseconds.
    var hrvSDNN: Double?

    /// Resting heart rate, bpm.
    var restingHR: Double?

    /// Wrist temperature deviation from baseline, °C (ASSUMPTION BASE-3).
    var wristTempDelta: Double?

    /// Respiratory rate, breaths per minute.
    var respiratoryRate: Double?

    /// Blood oxygen, fraction 0…1. Displayed only, never scored (§3).
    var oxygenSaturation: Double?

    // MARK: - Recovery

    /// Recovery, 1…100 (§5.1). `nil` when suppressed or still calibrating.
    var recoveryScore: Double?

    /// `w = min(n/14, 1)` (§4.2.4).
    var recoveryConfidence: Double

    /// `Z_total` (§5.1), kept so the drivers view can be rebuilt without recomputation.
    var recoveryZTotal: Double?

    // MARK: - Strain

    /// Day strain, 0…21 (§5.3).
    var dayStrain: Double

    /// `Ceiling = 21 · (Recovery/100)^0.65` (§5.3).
    var targetCeiling: Double?

    /// Accumulated Banister TRIMP (§5.3).
    var trimp: Double

    /// TRIMP already folded in, for the incremental monotonic recompute (ASSUMPTION STRAIN-1).
    var strainAnchorTRIMP: Double

    /// The timestamp `strainAnchorTRIMP` runs through.
    var strainAnchorThrough: Date?

    /// Seconds in each of the six %HRR zones, positionally (§7, ASSUMPTION ZONE-1).
    var zoneSecondsRaw: [Int]

    /// `HRmax` used for the day, so a later change to the estimate is visible in history.
    var maxHeartRateUsed: Double?

    // MARK: - Sleep

    var sleepDurationSeconds: Double
    var sleepScore: Double?
    var sleepEfficiency: Double?
    var deepSeconds: Double
    var remSeconds: Double
    var coreSeconds: Double
    var awakeSeconds: Double
    var timeInBedSeconds: Double

    /// Sleep midpoint in minutes from local midnight, for the 14-day consistency mean
    /// (§5.2, ASSUMPTION SLEEP-5).
    var sleepMidpointMinutes: Double?

    /// Start of the scored night's longest contiguous asleep block (§5.5).
    var sleepStart: Date?

    /// End of that block — wake time, which anchors the physiological day (ASSUMPTION DAY-1).
    var wakeTime: Date?

    /// Nap seconds recorded during the day, feeding the next night's credit (§5.2).
    var napSeconds: Double

    // MARK: - Quality and provenance

    /// `DataQuality.rawValue` (§7).
    var dataQualityRawValue: String

    /// `DataQualityReason.rawValue` list, so the UI can say what is missing.
    var dataQualityReasonsRaw: [String]

    /// When the record was last computed.
    var computedAt: Date

    /// Stamped so a formula change can trigger a backfill (§7).
    var engineVersion: Int

    init(
        dayStart: Date,
        timeZoneIdentifier: String,
        computedAt: Date,
        engineVersion: Int
    ) {
        self.dayStart = dayStart
        self.timeZoneIdentifier = timeZoneIdentifier
        self.hrvSDNN = nil
        self.restingHR = nil
        self.wristTempDelta = nil
        self.respiratoryRate = nil
        self.oxygenSaturation = nil
        self.recoveryScore = nil
        self.recoveryConfidence = 0
        self.recoveryZTotal = nil
        self.dayStrain = 0
        self.targetCeiling = nil
        self.trimp = 0
        self.strainAnchorTRIMP = 0
        self.strainAnchorThrough = nil
        self.zoneSecondsRaw = Array(repeating: 0, count: HeartRateZone.allCases.count)
        self.maxHeartRateUsed = nil
        self.sleepDurationSeconds = 0
        self.sleepScore = nil
        self.sleepEfficiency = nil
        self.deepSeconds = 0
        self.remSeconds = 0
        self.coreSeconds = 0
        self.awakeSeconds = 0
        self.timeInBedSeconds = 0
        self.sleepMidpointMinutes = nil
        self.sleepStart = nil
        self.wakeTime = nil
        self.napSeconds = 0
        self.dataQualityRawValue = DataQuality.good.rawValue
        self.dataQualityReasonsRaw = []
        self.computedAt = computedAt
        self.engineVersion = engineVersion
    }

    // MARK: - Typed accessors

    var dataQuality: DataQuality {
        get { DataQuality(rawValue: dataQualityRawValue) ?? .partial }
        set { dataQualityRawValue = newValue.rawValue }
    }

    var dataQualityReasons: [DataQualityReason] {
        get { dataQualityReasonsRaw.compactMap { DataQualityReason(rawValue: $0) } }
        set { dataQualityReasonsRaw = newValue.map(\.rawValue) }
    }

    var recoveryBand: RecoveryBand? {
        guard let recoveryScore else { return nil }
        return RecoveryBand.band(forScore: recoveryScore)
    }

    /// The time zone the day was bucketed in, falling back to UTC for an unknown identifier.
    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0) ?? .gmt
    }

    /// Seconds in one zone.
    func zoneSeconds(_ zone: HeartRateZone) -> Double {
        guard zone.index < zoneSecondsRaw.count else { return 0 }
        return Double(zoneSecondsRaw[zone.index])
    }

    /// Replaces the zone durations from an engine result.
    func setZoneSeconds(_ seconds: [Double]) {
        var raw = Array(repeating: 0, count: HeartRateZone.allCases.count)
        for (index, value) in seconds.enumerated() where index < raw.count {
            raw[index] = Int(value.rounded())
        }
        zoneSecondsRaw = raw
    }

    /// The persisted strain anchor, when one exists (ASSUMPTION STRAIN-1).
    var strainAnchor: StrainAnchor? {
        guard let strainAnchorThrough else { return nil }
        return StrainAnchor(
            trimp: strainAnchorTRIMP,
            throughTimestamp: strainAnchorThrough,
            zoneSeconds: zoneSecondsRaw.map(Double.init)
        )
    }

    /// Whether the record was computed by an older engine and needs a backfill (§7).
    func needsBackfill(currentEngineVersion: Int) -> Bool {
        engineVersion < currentEngineVersion
    }

    /// Total asleep seconds derived from the stage breakdown, for cross-checking the stored
    /// duration when a source writes stages but no summary.
    var stagedAsleepSeconds: Double {
        deepSeconds + remSeconds + coreSeconds
    }
}
