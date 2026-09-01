//
//  StoreSnapshots.swift
//  Zenithium
//
//  The `Sendable` value types the `@ModelActor` store returns and accepts.
//
//  ASSUMPTION STORE-1: no `PersistentModel` instance ever crosses the store's boundary.
//  SwiftData models are not `Sendable`, and handing one to a view model would be a data race
//  the moment the model context mutated it. Every read returns one of these snapshots and
//  every write takes one.
//

import Foundation

/// A day's computed state, as the UI and the widget need it.
struct BiometricDaySnapshot: Sendable, Equatable, Identifiable, Hashable, Codable {

    var id: Date { dayStart }

    let dayStart: Date
    let timeZoneIdentifier: String

    let heartRateVariability: Double?
    let restingHeartRate: Double?
    let wristTemperatureDelta: Double?
    let respiratoryRate: Double?
    let oxygenSaturation: Double?

    let recoveryScore: Double?
    let recoveryConfidence: Double
    let recoveryZTotal: Double?

    let dayStrain: Double
    let targetCeiling: Double?
    let trimp: Double
    let zoneSeconds: [Double]
    let maxHeartRateUsed: Double?

    let sleepDurationSeconds: Double
    let sleepScore: Double?
    let sleepEfficiency: Double?
    let deepSeconds: Double
    let remSeconds: Double
    let coreSeconds: Double
    let awakeSeconds: Double
    let timeInBedSeconds: Double
    let sleepMidpointMinutes: Double?
    let sleepStart: Date?
    let wakeTime: Date?
    let napSeconds: Double

    let dataQuality: DataQuality
    let dataQualityReasons: [DataQualityReason]
    let computedAt: Date
    let engineVersion: Int

    var recoveryBand: RecoveryBand? {
        recoveryScore.map(RecoveryBand.band(forScore:))
    }

    /// The night's shortfall against a need, in hours, for the sleep-debt window (§5.2).
    func sleepShortfallHours(against need: Double) -> Double {
        max(0, need - TimeConversion.hours(fromSeconds: sleepDurationSeconds))
    }
}

/// Everything a recalculation writes for one day.
///
/// Optional fields are genuinely optional: `nil` means "not computed this pass" and leaves
/// the stored value alone, which is what lets a strain-only refresh run without clobbering
/// the morning's recovery score.
struct DayRecordWrite: Sendable, Equatable {

    let dayStart: Date
    let timeZoneIdentifier: String
    let computedAt: Date
    let engineVersion: Int

    var heartRateVariability: Double?
    var restingHeartRate: Double?
    var wristTemperatureDelta: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double?

    var recoveryScore: Double?
    var recoveryConfidence: Double?
    var recoveryZTotal: Double?

    var dayStrain: Double?
    var targetCeiling: Double?
    var trimp: Double?
    var strainAnchorTRIMP: Double?
    var strainAnchorThrough: Date?
    var zoneSeconds: [Double]?
    var maxHeartRateUsed: Double?

    var sleepDurationSeconds: Double?
    var sleepScore: Double?
    var sleepEfficiency: Double?
    var deepSeconds: Double?
    var remSeconds: Double?
    var coreSeconds: Double?
    var awakeSeconds: Double?
    var timeInBedSeconds: Double?
    var sleepMidpointMinutes: Double?
    var sleepStart: Date?
    var wakeTime: Date?
    var napSeconds: Double?

    var dataQuality: DataQuality?
    var dataQualityReasons: [DataQualityReason]?

    /// Whether the overnight block should be cleared rather than left alone.
    ///
    /// Needed for the deletion path (§5.6): when HealthKit reports that last night's samples
    /// were deleted, leaving the previous values in place would show a score for data that no
    /// longer exists.
    var clearsOvernightValues: Bool

    init(
        dayStart: Date,
        timeZoneIdentifier: String,
        computedAt: Date,
        engineVersion: Int,
        clearsOvernightValues: Bool = false
    ) {
        self.dayStart = dayStart
        self.timeZoneIdentifier = timeZoneIdentifier
        self.computedAt = computedAt
        self.engineVersion = engineVersion
        self.clearsOvernightValues = clearsOvernightValues
    }
}

/// The user's profile, as a value.
struct UserProfileSnapshot: Sendable, Equatable, Hashable {

    let dateOfBirth: Date?
    let biologicalSex: BiologicalSexValue
    let maxHeartRateOverride: Double?
    let baselineSleepNeedHours: Double
    let dayBoundary: DayBoundary
    let unitPreference: UnitPreference
    let trainingLens: TrainingLens
    let appearance: AppearancePreference
    let tracksMenstrualCycle: Bool
    let hasCompletedOnboarding: Bool
    let disclaimerAcknowledgedAt: Date?

    var hasAcknowledgedDisclaimer: Bool { disclaimerAcknowledgedAt != nil }

    var characteristics: UserCharacteristics {
        UserCharacteristics(
            dateOfBirth: dateOfBirth,
            biologicalSex: biologicalSex,
            maxHeartRateOverride: maxHeartRateOverride
        )
    }

    /// The profile a first launch starts from.
    static let empty = UserProfileSnapshot(
        dateOfBirth: nil,
        biologicalSex: .notSet,
        maxHeartRateOverride: nil,
        baselineSleepNeedHours: EngineConstants.Sleep.defaultBaselineNeedHours,
        dayBoundary: DayBoundary.default,
        unitPreference: .metric,
        trainingLens: .endurance,
        appearance: .default,
        tracksMenstrualCycle: false,
        hasCompletedOnboarding: false,
        disclaimerAcknowledgedAt: nil
    )
}

/// The fields a profile edit may change. `nil` leaves a field alone.
struct UserProfileWrite: Sendable, Equatable {
    var dateOfBirth: Date??
    var biologicalSex: BiologicalSexValue?
    var maxHeartRateOverride: Double??
    var baselineSleepNeedHours: Double?
    var dayBoundary: DayBoundary?
    var unitPreference: UnitPreference?
    var trainingLens: TrainingLens?
    var appearance: AppearancePreference?
    var tracksMenstrualCycle: Bool?
    var hasCompletedOnboarding: Bool?
    var disclaimerAcknowledgedAt: Date??

    init() {}
}

/// A logged strength session, as a value.
struct StrengthSessionSnapshot: Sendable, Equatable, Identifiable, Hashable, Codable {
    let id: UUID
    let performedAt: Date
    let timeZoneIdentifier: String
    let pattern: MovementPattern
    let entries: [StrengthEntry]
    let sessionLoad: Double
    let note: String
    let engineVersion: Int
}

/// A recorded blood marker, as a value.
struct BloodMarkerSnapshot: Sendable, Equatable, Identifiable, Hashable, Codable {
    let id: UUID
    let marker: BloodMarkerKind
    let value: Double
    let unitSymbol: String
    let referenceRange: MarkerRange
    let optimalRange: MarkerRange
    let drawnAt: Date
    let note: String

    var positionInReferenceRange: Double? {
        referenceRange.normalizedPosition(of: value)
    }
}

/// A cached muscle projection, as a value.
struct MuscleFatigueSnapshotRecord: Sendable, Equatable, Codable {
    let computedAt: Date
    let fatigueValues: [Double]
    let halfLifeHours: [Double]
    let sleepScoreUsed: Double
    let engineVersion: Int

    func fatigue(for muscle: MuscleGroup) -> Double {
        guard muscle.storageIndex < fatigueValues.count else { return 0 }
        return fatigueValues[muscle.storageIndex]
    }

    func readiness(for muscle: MuscleGroup) -> Double {
        min(max(100 - fatigue(for: muscle), 0), 100)
    }
}
