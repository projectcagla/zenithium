//
//  WorkoutSummary.swift
//  Zenithium
//
//  Sendable workout DTO. Spec §8: `fetchWorkouts(in:)` returns `[WorkoutSummary]`, never
//  `[HKWorkout]` — `HKWorkout` is not `Sendable` and must not leave the actor.
//

import Foundation

/// One workout as Zenithium needs it: enough to compute TRIMP and muscle involvement, and
/// nothing that would require holding on to a HealthKit object.
struct WorkoutSummary: Sendable, Equatable, Hashable, Identifiable {

    /// The HealthKit sample UUID, so re-fetches are idempotent.
    let id: UUID

    /// The activity, mapped into the domain (`WorkoutActivity`).
    let activity: WorkoutActivity

    /// The workout's wall-clock interval.
    let interval: DateInterval

    /// Active energy burned, kilocalories, when the source recorded it.
    let activeEnergyKilocalories: Double?

    /// Distance covered, metres, when the source recorded it.
    let distanceMeters: Double?

    /// Average heart rate over the workout, bpm, when derivable.
    ///
    /// Strain never uses this — TRIMP integrates the intraday series (§5.3). It exists for
    /// display and for the muscle engine's fallback when intraday coverage is missing.
    let averageHeartRate: Double?

    /// The bundle identifier of the writing source, when known.
    let sourceBundleIdentifier: String?

    /// Ambient temperature during the session, °C, when the watch recorded one.
    ///
    /// Written by watchOS for outdoor workouts where the weather was available. Frequently
    /// absent — indoors, without a network at the time, or from a third-party app that does
    /// not fill it in — which is why every use of it is optional rather than defaulted.
    ///
    /// Declared `var` rather than `let`, unlike every other field here: an optional `var`
    /// gets a `nil` default in the synthesised memberwise initialiser and an optional `let`
    /// does not, so this is what lets the call sites that predate weather keep compiling.
    /// Yol haritası v4, C7.
    let ambientTemperatureCelsius: Double?

    /// Relative humidity during the session, 0…1, when the watch recorded one.
    let ambientHumidity: Double?

    init(
        id: UUID,
        activity: WorkoutActivity,
        interval: DateInterval,
        activeEnergyKilocalories: Double?,
        distanceMeters: Double?,
        averageHeartRate: Double?,
        sourceBundleIdentifier: String?,
        ambientTemperatureCelsius: Double? = nil,
        ambientHumidity: Double? = nil
    ) {
        self.id = id
        self.activity = activity
        self.interval = interval
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.ambientTemperatureCelsius = ambientTemperatureCelsius
        self.ambientHumidity = ambientHumidity
    }

    var start: Date { interval.start }
    var end: Date { interval.end }
    var duration: TimeInterval { interval.duration }
}
