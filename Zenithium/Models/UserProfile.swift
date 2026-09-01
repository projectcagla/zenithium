//
//  UserProfile.swift
//  Zenithium
//
//  Spec §7. Enum-valued properties are stored as their stable string keys so that adding a
//  case can never invalidate an existing store.
//

import Foundation
import SwiftData

@Model
final class UserProfile {

    /// There is exactly one profile. The unique key makes that structural rather than
    /// conventional, so a duplicate insert fails loudly instead of silently forking state.
    @Attribute(.unique) var identifier: String

    /// Date of birth, mirrored from HealthKit or entered in Settings. Feeds Tanaka (§5.3).
    var dateOfBirth: Date?

    /// `BiologicalSexValue.rawValue`.
    var biologicalSexRawValue: String

    /// A user-entered `HRmax`, bpm. Overrides both the observed and Tanaka estimates (§5.3).
    var maxHeartRateOverride: Double?

    /// `baselineNeed` in the sleep-need model, hours. Default 8.0 (§5.2).
    var baselineSleepNeedHours: Double

    /// `DayBoundary.rawValue` (ASSUMPTION DAY-1).
    var dayBoundaryRawValue: String

    /// `UnitPreference.rawValue`. Display only.
    var unitPreferenceRawValue: String

    /// `TrainingLens.rawValue` (ASSUMPTION LENS-1). Motoru değil, hangi ekranın öne
    /// çıktığını belirler.
    var trainingLensRawValue: String

    /// `AppearancePreference.rawValue`. Defaulted so a profile written before this field
    /// existed reads as dark rather than failing to migrate. Yol haritası v4, B6.
    var appearanceRawValue: String = AppearancePreference.default.rawValue

    /// Whether the user has turned cycle awareness on (Faz 12).
    ///
    /// Off by default and never inferred from biological sex. Reading menstrual data
    /// because somebody selected "female" would be a decision the app made about a person
    /// rather than one they made for themselves.
    var tracksMenstrualCycle: Bool = false

    /// Whether onboarding has been completed.
    var hasCompletedOnboarding: Bool

    /// When the §12 disclaimer was acknowledged. `nil` until it is.
    var disclaimerAcknowledgedAt: Date?

    var createdAt: Date
    var updatedAt: Date

    init(
        identifier: String = UserProfile.primaryIdentifier,
        dateOfBirth: Date? = nil,
        biologicalSex: BiologicalSexValue = .notSet,
        maxHeartRateOverride: Double? = nil,
        baselineSleepNeedHours: Double = UserProfile.defaultSleepNeedHours,
        dayBoundary: DayBoundary = DayBoundary.default,
        unitPreference: UnitPreference = .metric,
        trainingLens: TrainingLens = .endurance,
        appearance: AppearancePreference = .default,
        tracksMenstrualCycle: Bool = false,
        hasCompletedOnboarding: Bool = false,
        disclaimerAcknowledgedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.identifier = identifier
        self.dateOfBirth = dateOfBirth
        self.biologicalSexRawValue = biologicalSex.rawValue
        self.maxHeartRateOverride = maxHeartRateOverride
        self.baselineSleepNeedHours = baselineSleepNeedHours
        self.dayBoundaryRawValue = dayBoundary.rawValue
        self.unitPreferenceRawValue = unitPreference.rawValue
        self.trainingLensRawValue = trainingLens.rawValue
        self.appearanceRawValue = appearance.rawValue
        self.tracksMenstrualCycle = tracksMenstrualCycle
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.disclaimerAcknowledgedAt = disclaimerAcknowledgedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The single profile's key.
    static let primaryIdentifier = "primary"

    /// Spec §5.2 — `baselineNeed` defaults to 8.0 h. Defined in `EngineConstants`
    /// (ASSUMPTION CONST-2).
    static let defaultSleepNeedHours: Double = EngineConstants.Sleep.defaultBaselineNeedHours

    /// The range the settings stepper allows.
    static let sleepNeedRange: ClosedRange<Double> = 5.0...12.0

    /// The range a manual `HRmax` override may take.
    static let maxHeartRateOverrideRange: ClosedRange<Double> = 120...230

    var biologicalSex: BiologicalSexValue {
        get { BiologicalSexValue(rawValue: biologicalSexRawValue) ?? .notSet }
        set { biologicalSexRawValue = newValue.rawValue }
    }

    var dayBoundary: DayBoundary {
        get { DayBoundary(rawValue: dayBoundaryRawValue) ?? DayBoundary.default }
        set { dayBoundaryRawValue = newValue.rawValue }
    }

    var unitPreference: UnitPreference {
        get { UnitPreference(rawValue: unitPreferenceRawValue) ?? .metric }
        set { unitPreferenceRawValue = newValue.rawValue }
    }

    var trainingLens: TrainingLens {
        get { TrainingLens(rawValue: trainingLensRawValue) ?? .endurance }
        set { trainingLensRawValue = newValue.rawValue }
    }

    var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: appearanceRawValue) ?? .default }
        set { appearanceRawValue = newValue.rawValue }
    }

    /// Whether the §12 disclaimer has been acknowledged.
    var hasAcknowledgedDisclaimer: Bool {
        disclaimerAcknowledgedAt != nil
    }

    /// The characteristics the engines consume.
    var characteristics: UserCharacteristics {
        UserCharacteristics(
            dateOfBirth: dateOfBirth,
            biologicalSex: biologicalSex,
            maxHeartRateOverride: maxHeartRateOverride
        )
    }
}
