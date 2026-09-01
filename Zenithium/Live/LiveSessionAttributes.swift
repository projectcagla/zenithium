//
//  LiveSessionAttributes.swift
//  Zenithium
//
//  The Live Activity's shape. Yol haritası v4, C10.
//
//  Compiled by the app, which starts and updates the activity, and by the widget extension,
//  which draws it. Not by the watch: the watch has the session and needs none of this, and
//  `ActivityKit` is not on its framework list.
//
//  The split between `Attributes` and `ContentState` is ActivityKit's and it matters here:
//  attributes are fixed for the life of the activity, state is what changes. So the session's
//  identity and start go in the attributes and everything the number moves goes in the state.
//

import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// A running session, as the Dynamic Island and Lock Screen show it.
struct LiveSessionAttributes: ActivityAttributes {

    /// What changes while the session runs.
    struct ContentState: Codable, Hashable {

        /// Day strain if the session stopped now.
        let dayStrain: Double

        /// Where the day sits against its ceiling, when there is one.
        let ceilingProgress: Double?

        /// The ceiling itself, for the label.
        let ceiling: Double?

        /// The most recent heart rate.
        let heartRate: Double?

        /// How the session reads against the ceiling.
        let band: LiveSessionBand
    }

    /// Fixed for the activity's life.
    let sessionID: UUID
    let startedAt: Date
}

extension LiveSessionAttributes.ContentState {

    /// The state carried by a snapshot from the watch.
    init(snapshot: LiveSessionSnapshot) {
        self.init(
            dayStrain: snapshot.dayStrain,
            ceilingProgress: snapshot.ceilingProgress,
            ceiling: snapshot.ceiling,
            heartRate: snapshot.heartRate,
            band: snapshot.band
        )
    }
}
#endif
