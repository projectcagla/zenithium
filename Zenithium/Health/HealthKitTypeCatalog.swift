//
//  HealthKitTypeCatalog.swift
//  Zenithium
//
//  The one place HealthKit identifiers, units and activity types are named. Spec §8.
//  Everything above this file speaks `HealthDataKind`, `MetricKind` and `WorkoutActivity`;
//  this catalogue is the only translation table.
//

import Foundation
import HealthKit

/// Query-shaping constants for the HealthKit boundary.
///
/// ASSUMPTION CONST-1: these are IO tuning values, so they are defined here and forwarded by
/// `EngineConstants` rather than duplicated.
enum HealthQueryTuning {

    /// Spec §8 — downsample intraday heart rate to at most one sample every 5 seconds
    /// before returning it from the actor. Defined in `EngineConstants` (ASSUMPTION CONST-2).
    static let intradayDownsampleSeconds: TimeInterval =
        EngineConstants.Orchestration.intradayDownsampleSeconds

    /// ASSUMPTION API-5 — background delivery frequency for the categories that support it.
    static let backgroundDeliveryFrequency: HKUpdateFrequency = .hourly

    /// ASSUMPTION HRMAX-2 — the percentile of daily maxima taken as the observed `HRmax`.
    static let observedMaxPercentile: Double = EngineConstants.Strain.observedMaxPercentile

    /// Spec §5.3 — how far back the observed `HRmax` looks.
    static let observedMaxLookbackDays: Int = EngineConstants.Strain.observedMaxLookbackDays

    /// Upper bound on samples returned by a single windowed query, so a pathological day
    /// cannot exhaust memory. A full day at one sample per second is 86 400.
    static let windowedQuerySampleLimit: Int = 100_000
}

/// The translation table between HealthKit and Zenithium's domain vocabulary.
enum HealthKitTypeCatalog {

    // MARK: - Object types

    /// The quantity type behind a `HealthDataKind`, when the kind is a quantity.
    static func quantityType(for kind: HealthDataKind) -> HKQuantityType? {
        switch kind {
        case .heartRateVariability: return HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .heartRate: return HKQuantityType(.heartRate)
        case .respiratoryRate: return HKQuantityType(.respiratoryRate)
        case .wristTemperature: return HKQuantityType(.appleSleepingWristTemperature)
        case .oxygenSaturation: return HKQuantityType(.oxygenSaturation)
        case .sleepAnalysis, .workout: return nil
        }
    }

    /// The quantity type behind a baselined metric.
    static func quantityType(for metric: MetricKind) -> HKQuantityType {
        switch metric {
        case .heartRateVariability: return HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .wristTemperature: return HKQuantityType(.appleSleepingWristTemperature)
        case .respiratoryRate: return HKQuantityType(.respiratoryRate)
        }
    }

    // MARK: - Vital signs (Faz 11)

    /// The quantity type behind a vital sign.
    ///
    /// Kept separate from `quantityType(for: MetricKind)` for the same reason `VitalSign` is
    /// a separate type: these are signals Zenithium *shows*, not signals it scores with.
    /// Nothing here feeds a recovery weight, so nothing here belongs in that table.
    static func quantityType(for sign: VitalSign) -> HKQuantityType {
        switch sign {
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .walkingHeartRate: return HKQuantityType(.walkingHeartRateAverage)
        case .heartRateRecovery: return HKQuantityType(.heartRateRecoveryOneMinute)
        case .vo2Max: return HKQuantityType(.vo2Max)
        case .heartRateVariability: return HKQuantityType(.heartRateVariabilitySDNN)
        case .respiratoryRate: return HKQuantityType(.respiratoryRate)
        case .oxygenSaturation: return HKQuantityType(.oxygenSaturation)
        case .sleepingBreathingDisturbance: return HKQuantityType(.appleSleepingBreathingDisturbances)
        case .walkingSpeed: return HKQuantityType(.walkingSpeed)
        case .walkingStepLength: return HKQuantityType(.walkingStepLength)
        case .walkingAsymmetry: return HKQuantityType(.walkingAsymmetryPercentage)
        case .walkingDoubleSupport: return HKQuantityType(.walkingDoubleSupportPercentage)
        case .walkingSteadiness: return HKQuantityType(.appleWalkingSteadiness)
        case .stairAscentSpeed: return HKQuantityType(.stairAscentSpeed)
        case .sixMinuteWalkDistance: return HKQuantityType(.sixMinuteWalkTestDistance)
        case .timeInDaylight: return HKQuantityType(.timeInDaylight)
        case .environmentalAudioExposure: return HKQuantityType(.environmentalAudioExposure)
        case .headphoneAudioExposure: return HKQuantityType(.headphoneAudioExposure)
        }
    }

    /// The unit a vital sign is read in. Must match `VitalSign.unitSymbol`.
    static func unit(for sign: VitalSign) -> HKUnit {
        switch sign {
        case .restingHeartRate, .walkingHeartRate, .heartRateRecovery:
            return HKUnit.count().unitDivided(by: .minute())
        case .vo2Max:
            return HKUnit(from: "ml/kg*min")
        case .heartRateVariability:
            return HKUnit.secondUnit(with: .milli)
        case .respiratoryRate:
            return HKUnit.count().unitDivided(by: .minute())
        case .oxygenSaturation, .walkingAsymmetry, .walkingDoubleSupport, .walkingSteadiness:
            return HKUnit.percent()
        case .sleepingBreathingDisturbance:
            return HKUnit.count()
        case .walkingSpeed, .stairAscentSpeed:
            return HKUnit.meter().unitDivided(by: .second())
        case .walkingStepLength:
            return HKUnit.meterUnit(with: .centi)
        case .sixMinuteWalkDistance:
            return HKUnit.meter()
        case .timeInDaylight:
            return HKUnit.minute()
        case .environmentalAudioExposure, .headphoneAudioExposure:
            return HKUnit.decibelAWeightedSoundPressureLevel()
        }
    }

    /// How a day's samples are collapsed into one value.
    ///
    /// Daylight is a duration, so it sums; everything else is a level, so it averages.
    /// Summing an average would be meaningless and averaging a duration would understate it.
    static func aggregationOption(for sign: VitalSign) -> HKStatisticsOptions {
        sign == .timeInDaylight ? .cumulativeSum : .discreteAverage
    }

    /// HealthKit reports percentages as fractions; the UI shows them as percentages.
    static func displayScale(for sign: VitalSign) -> Double {
        switch sign {
        case .oxygenSaturation, .walkingAsymmetry, .walkingDoubleSupport, .walkingSteadiness:
            return 100
        default:
            return 1
        }
    }

    /// The menstrual-flow category. Faz 12.
    static var menstrualFlowType: HKCategoryType {
        HKCategoryType(.menstrualFlow)
    }

    /// Every vital-sign type, for the authorization request.
    static var vitalReadTypes: Set<HKObjectType> {
        Set(VitalSign.allCases.map { quantityType(for: $0) as HKObjectType })
    }

    /// The category type behind a `HealthDataKind`, when the kind is a category.
    static func categoryType(for kind: HealthDataKind) -> HKCategoryType? {
        kind == .sleepAnalysis ? HKCategoryType(.sleepAnalysis) : nil
    }

    /// The object type behind any `HealthDataKind`.
    static func objectType(for kind: HealthDataKind) -> HKObjectType? {
        switch kind {
        case .sleepAnalysis: return categoryType(for: kind)
        case .workout: return HKObjectType.workoutType()
        case .heartRateVariability, .restingHeartRate, .heartRate,
             .respiratoryRate, .wristTemperature, .oxygenSaturation:
            return quantityType(for: kind)
        }
    }

    /// The `HealthDataKind` a sample type belongs to, for attributing observer callbacks.
    static func kind(for sampleType: HKSampleType) -> HealthDataKind? {
        HealthDataKind.allCases.first { objectType(for: $0) == sampleType }
    }

    /// Every type Zenithium reads. It never writes, so there is no share set (§12: no network,
    /// no account, and nothing written back into Health).
    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for kind in HealthDataKind.allCases {
            if let objectType = objectType(for: kind) {
                types.insert(objectType)
            }
        }
        types.insert(HKCharacteristicType(.dateOfBirth))
        types.insert(HKCharacteristicType(.biologicalSex))
        // Faz 11 — the vitals screen. Requested in the same sheet rather than a second
        // prompt later: one permission conversation is the honest one, and a user who
        // declines a signal simply sees that row empty.
        types.formUnion(vitalReadTypes)
        return types
    }

    /// The types worth observing for change. Blood oxygen is read but never scored, so a
    /// change in it does not justify waking the pipeline (§3).
    static var observedSampleTypes: [HKSampleType] {
        HealthDataKind.allCases
            .filter { $0.triggersRecalculation }
            .compactMap { objectType(for: $0) as? HKSampleType }
    }

    /// The types anchored queries track, so deletions are noticed (§5.6).
    static var anchoredSampleTypes: [HKSampleType] {
        observedSampleTypes
    }

    // MARK: - Units

    /// The canonical unit a metric is read in (§2.8 — conversion happens only here).
    static func unit(for metric: MetricKind) -> HKUnit {
        switch metric {
        case .heartRateVariability: return .secondUnit(with: .milli)
        case .restingHeartRate: return beatsPerMinute
        case .wristTemperature: return .degreeCelsius()
        case .respiratoryRate: return breathsPerMinute
        }
    }

    /// Beats per minute.
    static var beatsPerMinute: HKUnit {
        HKUnit.count().unitDivided(by: .minute())
    }

    /// Breaths per minute. Dimensionally identical to bpm; named separately so call sites read
    /// correctly.
    static var breathsPerMinute: HKUnit {
        HKUnit.count().unitDivided(by: .minute())
    }

    /// Kilocalories.
    static var kilocalories: HKUnit {
        HKUnit.kilocalorie()
    }

    /// Metres.
    static var meters: HKUnit {
        HKUnit.meter()
    }

    /// Fraction 0…1, the canonical form for blood oxygen (§3).
    static var fraction: HKUnit {
        HKUnit.percent()
    }

    // MARK: - Statistics

    /// The aggregation used for a metric's daily rollup.
    ///
    /// ASSUMPTION API-4: `.discreteAverage`, the documented option for discrete quantity types.
    static func aggregationOption(for metric: MetricKind) -> HKStatisticsOptions {
        .discreteAverage
    }

    // MARK: - Workouts

    /// Maps a HealthKit activity type into the domain (ASSUMPTION MUSCLE-1).
    ///
    /// Anything outside the supported set becomes `.other`, which carries a low
    /// whole-body involvement row rather than silently dropping the session's load.
    static func activity(for activityType: HKWorkoutActivityType) -> WorkoutActivity {
        switch activityType {
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .rowing: return .rowing
        case .elliptical: return .elliptical
        case .stairClimbing, .stairs: return .stairClimbing
        case .highIntensityIntervalTraining: return .highIntensityIntervalTraining
        case .traditionalStrengthTraining: return .traditionalStrengthTraining
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .coreTraining: return .coreTraining
        case .yoga: return .yoga
        case .pilates: return .pilates
        case .flexibility, .preparationAndRecovery: return .flexibility
        case .cardioDance, .socialDance: return .cardioDance
        case .boxing, .kickboxing: return .boxing
        case .martialArts: return .martialArts
        case .tennis: return .tennis
        case .basketball: return .basketball
        case .soccer: return .soccer
        case .golf: return .golf
        case .jumpRope: return .jumpRope
        case .crossTraining: return .crossTraining
        case .mixedCardio: return .mixedCardio
        case .climbing: return .climbing
        case .paddleSports, .surfingSports: return .paddleSports
        case .skatingSports: return .skatingSports
        case .downhillSkiing, .crossCountrySkiing, .snowboarding: return .downhillSkiing
        default: return .other
        }
    }

    /// The distance quantity type that matches an activity, when one does.
    static func distanceType(for activity: WorkoutActivity) -> HKQuantityType? {
        switch activity {
        case .running, .walking, .hiking:
            return HKQuantityType(.distanceWalkingRunning)
        case .cycling:
            return HKQuantityType(.distanceCycling)
        case .swimming:
            return HKQuantityType(.distanceSwimming)
        case .downhillSkiing, .skatingSports:
            return HKQuantityType(.distanceDownhillSnowSports)
        case .paddleSports, .rowing:
            return HKQuantityType(.distancePaddleSports)
        case .elliptical, .stairClimbing, .highIntensityIntervalTraining,
             .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining,
             .yoga, .pilates, .flexibility, .cardioDance, .boxing, .martialArts,
             .tennis, .basketball, .soccer, .golf, .jumpRope, .crossTraining,
             .mixedCardio, .climbing, .other:
            return nil
        }
    }
}
