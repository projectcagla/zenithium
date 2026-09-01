//
//  SessionShape.swift
//  Zenithium
//
//  A session someone keeps doing. Yol haritası v4, C8.
//

import Foundation

/// A recurring session, recognised from what was actually recorded.
struct SessionShape: Sendable, Equatable, Hashable, Identifiable {

    /// Below this many matches it is a coincidence, not a habit.
    ///
    /// Three, because two sessions of a similar length is what any two weeks of running
    /// produces, and offering that back as "your usual session" would be noise.
    ///
    /// Declared here rather than on the engine because `Domain` is compiled by the watch and
    /// the widget while `Engines` is not.
    static let minimumOccurrences = 3

    let activity: WorkoutActivity

    /// The band the durations fall in, minutes.
    let minutesLow: Int
    let minutesHigh: Int

    /// Typical distance in kilometres, when the activity has one.
    let kilometres: Double?

    /// Typical average heart rate.
    let averageHeartRate: Double?

    /// How many sessions matched.
    let occurrences: Int

    /// The most recent one.
    let lastPerformed: Date

    var id: String { "\(activity.rawValue)-\(minutesLow)-\(kilometres.map { Int($0 * 10) } ?? -1)" }

    /// Typical duration, minutes — the middle of the band.
    var minutes: Int { (minutesLow + minutesHigh) / 2 }

    /// Whether this has happened often enough to offer.
    var isEstablished: Bool { occurrences >= Self.minimumOccurrences }

    /// A name for the shape, built from what it is rather than from a guess about intent.
    ///
    /// Deliberately descriptive. Calling a forty-minute run "tempo" would be inferring an
    /// intention from a duration, and the app does not know whether that Tuesday was a tempo
    /// or a commute.
    var displayName: String {
        if let kilometres, kilometres > 0 {
            return "\(activity.displayName) · \(ZenithiumFormat.metric(kilometres, digits: 1)) km"
        }
        return "\(activity.displayName) · \(minutes) dk"
    }
}
