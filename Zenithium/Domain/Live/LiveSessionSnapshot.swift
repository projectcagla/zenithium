//
//  LiveSessionSnapshot.swift
//  Zenithium
//
//  What crosses from the watch to the phone during a session. Yol haritası v4, C10.
//
//  Deliberately small and deliberately dumb. The watch does the computing — it has the heart
//  rate and it runs `LiveSessionEngine` — and the phone renders. Sending the samples instead
//  and recomputing on the other side would mean two implementations of the same integral,
//  which is the drift this project has spent four waves removing.
//
//  Foundation only, so the watch can build one and the widget extension can read one.
//  `Codable` because `WCSession.updateApplicationContext` takes a property-list dictionary
//  and JSON round-tripping is the least surprising way to produce one.
//

import Foundation

/// The state of a running session, as the phone needs to draw it.
struct LiveSessionSnapshot: Codable, Sendable, Equatable, Hashable {

    /// Identifies the session, so a stale payload from a finished one cannot restart an
    /// activity that was just dismissed.
    let sessionID: UUID

    /// When the session started, for the elapsed clock the phone runs itself.
    ///
    /// The phone ticks its own clock from this rather than being told the elapsed seconds:
    /// application context is coalesced and may arrive late, and a clock that jumps
    /// backwards reads as a bug even when the number is right.
    let startedAt: Date

    /// Day strain if the session stopped now, on the 0–21 scale.
    let dayStrain: Double

    /// Where the day sits against its ceiling, when there is one.
    let ceilingProgress: Double?

    /// Today's ceiling, for the label.
    let ceiling: Double?

    /// The most recent heart rate, when one has arrived.
    let heartRate: Double?

    /// How the session reads against the ceiling.
    let band: LiveSessionBand

    /// Whether the session is still running. `false` ends the activity.
    let isRunning: Bool

    /// When this snapshot was made, so the phone can ignore one that arrives out of order.
    let generatedAt: Date

    /// A property-list dictionary for `WCSession`.
    func asApplicationContext() throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        return [Self.contextKey: data]
    }

    /// The reverse, or `nil` when the payload is not one of these.
    static func from(applicationContext context: [String: Any]) -> LiveSessionSnapshot? {
        guard let data = context[contextKey] as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LiveSessionSnapshot.self, from: data)
    }

    /// The only key the two sides agree on.
    static let contextKey = "com.zenithium.liveSession"
}

extension LiveSessionBand: Codable {}
