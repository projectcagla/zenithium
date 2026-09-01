//
//  SessionShapeEngine.swift
//  Zenithium
//
//  Recognising the sessions somebody keeps doing. Yol haritası v4, C8.
//
//  ## What this recognises, and what it refuses to
//
//  The roadmap asked for HealthKit workouts to be classified into the Hyrox stations the
//  hybrid screen models. That is not possible and should not be faked: a workout summary
//  carries an activity type, a duration, a distance and an average heart rate, and none of
//  those distinguish a sled push from a set of wall balls. Both arrive as "functional
//  strength training, 42 minutes". Guessing would fill somebody's log with stations they did
//  not do, and a wrong log is worse than an empty one.
//
//  What *is* in the data is repetition. Somebody who runs eight kilometres every Tuesday has
//  recorded that eight times, and offering it back as a template — pre-filled duration,
//  distance, intensity — saves the typing without inventing anything.
//
//  ## How
//
//  Workouts are bucketed by activity, by a duration band and by a distance band, and any
//  bucket with enough members becomes a shape. Bands rather than exact values because nobody
//  runs 8.00 km twice; the bucket is what makes 7.8 and 8.3 the same session.
//
//  Names are descriptive, never interpretive. A forty-minute run is "Koşu · 8,2 km", not
//  "tempo" — the app does not know whether that Tuesday was a tempo or a commute.
//

import Foundation

enum SessionShapeEngine {

    /// How far back sessions are read.
    static let windowDays = 120

    /// The duration bucket's width, minutes.
    ///
    /// Ten minutes: wide enough that a session that ran long still matches, narrow enough
    /// that a twenty-minute jog and a fifty-minute run do not become one shape.
    static let durationBucketMinutes = 10

    /// The distance bucket's width, kilometres.
    static let distanceBucketKilometres: Double = 2

    /// A workout shorter than this is not a session.
    static let minimumMinutes: Double = 10

    /// The recurring shapes, most frequent first.
    static func shapes(
        from workouts: [WorkoutSummary],
        now: Date
    ) -> [SessionShape] {
        let start = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let recent = workouts.filter {
            $0.interval.start >= start
                && $0.interval.start <= now
                && $0.interval.duration / 60 >= minimumMinutes
        }
        guard !recent.isEmpty else { return [] }

        var buckets: [BucketKey: [WorkoutSummary]] = [:]
        for workout in recent {
            buckets[key(for: workout), default: []].append(workout)
        }

        return buckets
            .compactMap { key, members -> SessionShape? in
                guard members.count >= SessionShape.minimumOccurrences else { return nil }
                guard let last = members.map(\.interval.start).max() else { return nil }

                let distances = members.compactMap { $0.distanceMeters.map { $0 / 1_000 } }
                let rates = members.compactMap(\.averageHeartRate)

                return SessionShape(
                    activity: key.activity,
                    minutesLow: key.durationBucket * durationBucketMinutes,
                    minutesHigh: (key.durationBucket + 1) * durationBucketMinutes,
                    kilometres: distances.isEmpty ? nil : MathSupport.mean(distances),
                    averageHeartRate: rates.isEmpty ? nil : MathSupport.mean(rates),
                    occurrences: members.count,
                    lastPerformed: last
                )
                // The mean rather than the median: the bucket has already excluded the
                // outliers that a median would be protecting against, and a mean of three
                // near-identical sessions reads as the number the person recognises.
            }
            .sorted { lhs, rhs in
                if lhs.occurrences != rhs.occurrences { return lhs.occurrences > rhs.occurrences }
                return lhs.lastPerformed > rhs.lastPerformed
            }
    }

    // MARK: - Buckets

    private struct BucketKey: Hashable {
        let activity: WorkoutActivity
        let durationBucket: Int
        let distanceBucket: Int
    }

    private static func key(for workout: WorkoutSummary) -> BucketKey {
        let minutes = workout.interval.duration / 60
        let kilometres = (workout.distanceMeters ?? 0) / 1_000
        return BucketKey(
            activity: workout.activity,
            durationBucket: Int(minutes / Double(durationBucketMinutes)),
            // −1 marks "no distance", so a treadmill session without one does not land in
            // the same bucket as a zero-kilometre outdoor run.
            distanceBucket: workout.distanceMeters == nil
                ? -1
                : Int(kilometres / distanceBucketKilometres)
        )
    }

    // MARK: - Copy

    /// One line describing how established a shape is.
    static func summary(for shape: SessionShape) -> String {
        let days = Int(Date().timeIntervalSince(shape.lastPerformed) / 86_400)
        let last = days <= 0 ? "bugün" : "\(days) gün önce"
        return "Son \(windowDays) günde \(shape.occurrences) kez — en sonu \(last)."
    }
}
