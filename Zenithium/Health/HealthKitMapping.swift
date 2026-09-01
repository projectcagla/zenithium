//
//  HealthKitMapping.swift
//  Zenithium
//
//  HealthKit → Sendable DTO mapping. Spec §8:
//  `HKWorkout`, `HKSample` and `HKQuantitySample` are **not `Sendable`** and must never cross
//  an actor boundary. Every function here is `static` and pure, and every one of them runs
//  inside the HealthKit callback — before anything is returned or resumed — so no HealthKit
//  object ever escapes.
//

import Foundation
import HealthKit

/// Pure mapping from HealthKit objects to `Domain` value types.
enum HealthKitMapping {

    // MARK: - Heart rate

    /// Maps quantity samples to `HeartRateSample`, dropping implausible readings.
    ///
    /// Implausible values are dropped rather than clamped: a 0 bpm or 300 bpm reading is a
    /// sensor artefact, and clamping would fold the artefact into the strain integral.
    static func heartRateSamples(from samples: [HKSample]) -> [HeartRateSample] {
        let unit = HealthKitTypeCatalog.beatsPerMinute
        var mapped: [HeartRateSample] = []
        mapped.reserveCapacity(samples.count)
        for sample in samples {
            guard let quantity = sample as? HKQuantitySample else { continue }
            let value = quantity.quantity.doubleValue(for: unit)
            let heartRate = HeartRateSample(
                timestamp: quantity.startDate,
                beatsPerMinute: value,
                sourceBundleIdentifier: quantity.sourceRevision.source.bundleIdentifier
            )
            guard heartRate.isPlausible else { continue }
            mapped.append(heartRate)
        }
        return mapped.sorted { $0.timestamp < $1.timestamp }
    }

    /// Spec §8 — downsample to at most one sample per `minimumSpacing` seconds.
    ///
    /// Keeps the first sample of each spacing bucket rather than averaging, so the series
    /// stays a series of real observations. Input must be sorted ascending.
    static func downsample(
        _ samples: [HeartRateSample],
        minimumSpacing: TimeInterval = HealthQueryTuning.intradayDownsampleSeconds
    ) -> [HeartRateSample] {
        guard minimumSpacing > 0, let first = samples.first else { return samples }
        var kept: [HeartRateSample] = [first]
        var lastKept = first.timestamp
        for sample in samples.dropFirst() {
            if sample.timestamp.timeIntervalSince(lastKept) >= minimumSpacing {
                kept.append(sample)
                lastKept = sample.timestamp
            }
        }
        return kept
    }

    // MARK: - Sleep

    /// Maps sleep category samples to `SleepSegment`, dropping values this build does not know.
    static func sleepSegments(
        from samples: [HKSample],
        fallbackTimeZoneIdentifier: String
    ) -> [SleepSegment] {
        var mapped: [SleepSegment] = []
        mapped.reserveCapacity(samples.count)
        for sample in samples {
            guard let category = sample as? HKCategorySample else { continue }
            guard let stage = SleepStage.stage(forHealthKitRawValue: category.value) else { continue }
            guard category.endDate > category.startDate else { continue }
            mapped.append(
                SleepSegment(
                    interval: DateInterval(start: category.startDate, end: category.endDate),
                    stage: stage,
                    sourceBundleIdentifier: category.sourceRevision.source.bundleIdentifier,
                    timeZoneIdentifier: timeZoneIdentifier(
                        from: category.metadata,
                        fallback: fallbackTimeZoneIdentifier
                    )
                )
            )
        }
        return mapped.chronological
    }

    /// Spec §5.6 — a record carries the time zone in effect at its date. HealthKit writes it
    /// into `HKMetadataKeyTimeZone` when the source recorded one; otherwise the caller's
    /// current zone is the best available answer.
    static func timeZoneIdentifier(
        from metadata: [String: Any]?,
        fallback: String
    ) -> String {
        guard let identifier = metadata?[HKMetadataKeyTimeZone] as? String,
              TimeZone(identifier: identifier) != nil else {
            return fallback
        }
        return identifier
    }

    // MARK: - Workouts

    /// Maps workouts to `WorkoutSummary`, reading energy, distance and average heart rate
    /// through `statistics(for:)` rather than the deprecated aggregate properties.
    static func workoutSummaries(from samples: [HKSample]) -> [WorkoutSummary] {
        var mapped: [WorkoutSummary] = []
        mapped.reserveCapacity(samples.count)
        for sample in samples {
            guard let workout = sample as? HKWorkout else { continue }
            guard workout.endDate > workout.startDate else { continue }
            let activity = HealthKitTypeCatalog.activity(for: workout.workoutActivityType)
            let energy = workout
                .statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?
                .doubleValue(for: HealthKitTypeCatalog.kilocalories)
            let distance = HealthKitTypeCatalog.distanceType(for: activity)
                .flatMap { workout.statistics(for: $0) }?
                .sumQuantity()?
                .doubleValue(for: HealthKitTypeCatalog.meters)
            let averageHeartRate = workout
                .statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?
                .doubleValue(for: HealthKitTypeCatalog.beatsPerMinute)
            // Weather, when the watch recorded it. Absent indoors and from most third-party
            // apps, so both stay optional all the way through. Yol haritası v4, C7.
            let temperature = (workout.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity)?
                .doubleValue(for: .degreeCelsius())
            let humidity = (workout.metadata?[HKMetadataKeyWeatherHumidity] as? HKQuantity)?
                .doubleValue(for: .percent())

            mapped.append(
                WorkoutSummary(
                    id: workout.uuid,
                    activity: activity,
                    interval: DateInterval(start: workout.startDate, end: workout.endDate),
                    activeEnergyKilocalories: energy,
                    distanceMeters: distance,
                    averageHeartRate: averageHeartRate,
                    sourceBundleIdentifier: workout.sourceRevision.source.bundleIdentifier,
                    ambientTemperatureCelsius: temperature,
                    ambientHumidity: humidity
                )
            )
        }
        return mapped.sorted { $0.start < $1.start }
    }

    // MARK: - Quantities

    /// The average of a quantity sample set in a metric's canonical unit, or `nil` when the
    /// set is empty. Used for the overnight rollup where a statistics query would be a second
    /// round trip for one number.
    static func averageValue(from samples: [HKSample], metric: MetricKind) -> Double? {
        let unit = HealthKitTypeCatalog.unit(for: metric)
        var total: Double = 0
        var count = 0
        for sample in samples {
            guard let quantity = sample as? HKQuantitySample else { continue }
            let value = quantity.quantity.doubleValue(for: unit)
            guard value.isFinite, metric.plausibleRange.contains(value) else { continue }
            total += value
            count += 1
        }
        guard count > 0 else { return nil }
        return total / Double(count)
    }

    /// The average of a blood-oxygen sample set as a fraction 0…1 (§3 — displayed, never scored).
    static func averageOxygenSaturation(from samples: [HKSample]) -> Double? {
        let unit = HealthKitTypeCatalog.fraction
        var total: Double = 0
        var count = 0
        for sample in samples {
            guard let quantity = sample as? HKQuantitySample else { continue }
            let value = quantity.quantity.doubleValue(for: unit)
            guard value.isFinite, value > 0, value <= 1 else { continue }
            total += value
            count += 1
        }
        guard count > 0 else { return nil }
        return total / Double(count)
    }

    // MARK: - Statistics collections

    /// Maps a statistics collection into daily samples for one metric.
    ///
    /// Buckets with no data are skipped entirely, which is what makes a gap a gap rather than
    /// a zero (§4.2.5). Values outside the metric's plausible range are discarded as artefacts
    /// before they can reach winsorization.
    static func dailySamples(
        from collection: HKStatisticsCollection,
        metric: MetricKind,
        start: Date,
        end: Date,
        calendar: Calendar,
        timeZoneIdentifier: String
    ) -> [DailyMetricSample] {
        let unit = HealthKitTypeCatalog.unit(for: metric)
        var samples: [DailyMetricSample] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            guard let quantity = statistics.averageQuantity() else { return }
            let value = quantity.doubleValue(for: unit)
            guard value.isFinite, metric.plausibleRange.contains(value) else { return }
            let dayStart = calendar.startOfDay(for: statistics.startDate)
            samples.append(
                DailyMetricSample(
                    dayStart: dayStart,
                    value: value,
                    timeZoneIdentifier: timeZoneIdentifier
                )
            )
        }
        return samples.sorted { $0.dayStart < $1.dayStart }
    }

    /// Daily maxima from a statistics collection, for the observed `HRmax` percentile
    /// (ASSUMPTION HRMAX-2).
    static func dailyMaxima(
        from collection: HKStatisticsCollection,
        unit: HKUnit,
        start: Date,
        end: Date,
        plausibleRange: ClosedRange<Double>
    ) -> [Double] {
        var maxima: [Double] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            guard let quantity = statistics.maximumQuantity() else { return }
            let value = quantity.doubleValue(for: unit)
            guard value.isFinite, plausibleRange.contains(value) else { return }
            maxima.append(value)
        }
        return maxima
    }

    // MARK: - Characteristics

    /// Maps `HKBiologicalSex` into the domain.
    static func biologicalSex(from sex: HKBiologicalSex) -> BiologicalSexValue {
        switch sex {
        case .female: return .female
        case .male: return .male
        case .other: return .other
        case .notSet: return .notSet
        @unknown default: return .notSet
        }
    }
}
