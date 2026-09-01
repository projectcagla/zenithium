//
//  StressEngine.swift
//  Zenithium
//
//  The day, split. Faz 13.
//
//  Everything here runs off the intraday heart-rate series the strain engine already reads,
//  plus the day's workouts. No new HealthKit surface, no new storage — the same data, asked
//  a different question: not "how much load" but "where did it come from, and when did the
//  day let up".
//
//  §12: sustained elevation outside a session is described as load and as a pattern. It is
//  never called stress in the clinical sense, and it never becomes a health finding.
//

import Foundation

enum StressEngine {

    /// Bucket width. Five minutes is fine enough to show a meeting and coarse enough that a
    /// single stray sample cannot create a spike.
    static let bucketSeconds: TimeInterval = 300

    /// A recovery window must last at least this long to count.
    ///
    /// Fifteen minutes: shorter stretches at resting heart rate are just the gaps between
    /// activities, and listing them would bury the ones that mean something.
    static let minimumRecoveryWindowSeconds: TimeInterval = 900

    /// A bucket counts as restful below this fraction of heart-rate reserve.
    static let restfulReserveFraction = 0.10

    // MARK: - Entry point

    static func analyse(
        samples: [HeartRateSample],
        workouts: [WorkoutSummary],
        dayWindow: DateInterval,
        restingHeartRate: Double,
        maxHeartRate: Double,
        biologicalSex: BiologicalSexValue
    ) -> StressDay {
        let usable = samples
            .filter { $0.isPlausible && dayWindow.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
        guard !usable.isEmpty else { return .empty }

        let reserve = max(
            maxHeartRate - restingHeartRate,
            EngineConstants.Strain.minimumHeartRateReserve
        )
        let workoutIntervals = workouts.map(\.interval)

        let intervals = buckets(
            samples: usable,
            dayWindow: dayWindow,
            restingHeartRate: restingHeartRate,
            reserve: reserve,
            workoutIntervals: workoutIntervals
        )

        // Training load is re-integrated per workout rather than apportioned from the day's
        // total, for the same reason `StrainEngine.trimp(for:)` does it: a session's load
        // must not change because the rest of the day did.
        let trainingLoad = workoutIntervals.reduce(0.0) { total, interval in
            total + StrainEngine.trimp(
                for: interval,
                samples: usable,
                restingHeartRate: restingHeartRate,
                maxHeartRate: maxHeartRate,
                biologicalSex: biologicalSex
            )
        }

        let dayLoad = StrainEngine.trimp(
            for: dayWindow,
            samples: usable,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            biologicalSex: biologicalSex
        )

        var secondsByBand: [StressBand: Double] = [:]
        for interval in intervals {
            secondsByBand[interval.band, default: 0] += interval.end.timeIntervalSince(interval.start)
        }

        return StressDay(
            intervals: intervals,
            trainingLoad: trainingLoad,
            // Clamped at zero: the two integrations cover overlapping sample sets, and
            // rounding can leave the workout total a hair above the day's. A negative
            // "rest of life" figure would be nonsense on the screen.
            nonTrainingLoad: max(0, dayLoad - trainingLoad),
            recoveryWindows: recoveryWindows(from: intervals),
            secondsByBand: secondsByBand
        )
    }

    // MARK: - Buckets

    /// Average the series into fixed buckets.
    ///
    /// Buckets with no samples are skipped rather than interpolated. A watch off the wrist
    /// is not a resting heart rate, and filling the gap would draw a calm afternoon that
    /// never happened.
    static func buckets(
        samples: [HeartRateSample],
        dayWindow: DateInterval,
        restingHeartRate: Double,
        reserve: Double,
        workoutIntervals: [DateInterval]
    ) -> [StressInterval] {
        var result: [StressInterval] = []
        var bucketStart = dayWindow.start

        var index = 0
        while bucketStart < dayWindow.end {
            let bucketEnd = min(bucketStart.addingTimeInterval(bucketSeconds), dayWindow.end)

            var total = 0.0
            var count = 0
            while index < samples.count, samples[index].timestamp < bucketEnd {
                if samples[index].timestamp >= bucketStart {
                    total += samples[index].beatsPerMinute
                    count += 1
                }
                index += 1
            }

            if count > 0 {
                let mean = total / Double(count)
                let fraction = MathSupport.clamp(
                    MathSupport.safeDivide(mean - restingHeartRate, by: reserve),
                    0,
                    1
                )
                let bucket = DateInterval(start: bucketStart, end: bucketEnd)
                result.append(
                    StressInterval(
                        start: bucketStart,
                        end: bucketEnd,
                        heartRate: mean,
                        reserveFraction: fraction,
                        isWorkout: workoutIntervals.contains { $0.intersects(bucket) }
                    )
                )
            }

            bucketStart = bucketEnd
        }
        return result
    }

    // MARK: - Recovery windows

    /// Contiguous stretches spent at or near resting, longest first.
    static func recoveryWindows(from intervals: [StressInterval]) -> [RecoveryWindow] {
        var windows: [RecoveryWindow] = []
        var runStart: Date?
        var runEnd: Date?
        var heartRates: [Double] = []

        func closeRun() {
            defer {
                runStart = nil
                runEnd = nil
                heartRates.removeAll(keepingCapacity: true)
            }
            guard let start = runStart, let end = runEnd,
                  end.timeIntervalSince(start) >= minimumRecoveryWindowSeconds,
                  let mean = MathSupport.mean(heartRates) else { return }
            windows.append(RecoveryWindow(start: start, end: end, heartRate: mean))
        }

        for interval in intervals {
            let isRestful = !interval.isWorkout && interval.reserveFraction < restfulReserveFraction
            if isRestful {
                // A gap in the buckets breaks the run: two calm stretches either side of an
                // unmeasured hour are two windows, not one long one.
                if let end = runEnd, interval.start > end {
                    closeRun()
                }
                if runStart == nil { runStart = interval.start }
                runEnd = interval.end
                heartRates.append(interval.heartRate)
            } else {
                closeRun()
            }
        }
        closeRun()

        return windows.sorted { $0.duration > $1.duration }
    }

    // MARK: - Copy

    /// One sentence about when the day let up, or `nil` when it did not.
    static func recoverySummary(for day: StressDay, calendar: Calendar) -> String? {
        guard let longest = day.recoveryWindows.first else {
            return "Bugün nabzın dinlenik seviyeye uzun süre inmedi."
        }
        let formatter = Date.FormatStyle.dateTime.hour().minute()
        let start = longest.start.formatted(formatter)
        let minutes = Int((longest.duration / 60).rounded())
        return "Günün en sakin bloğu \(start) civarında başladı ve \(minutes) dakika sürdü."
    }
}
