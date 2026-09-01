//
//  StrengthSessionLog.swift
//  Zenithium
//
//  A manually logged strength session. Spec §5.4: strength sessions require a manual logger;
//  Zenithium never fabricates strength muscle data from HealthKit (ASSUMPTION MUSCLE-2).
//

import Foundation
import SwiftData

@Model
final class StrengthSessionLog {

    /// Stable identity, unique.
    @Attribute(.unique) var id: UUID

    /// When the session finished. Fatigue decay is measured from here (§5.4).
    var performedAt: Date

    /// The identifier of the time zone in effect at `performedAt` (§5.6).
    var timeZoneIdentifier: String

    /// `MovementPattern.storageKey`.
    var patternStorageKey: String

    /// The exercises performed.
    var entries: [StrengthEntry]

    /// `sessionLoad = clamp(Σ(sets · reps · RPE) / 3.0, 0, 100)` (§5.4), stamped at save time
    /// so history is stable, and recomputable because `entries` are kept.
    var sessionLoad: Double

    /// Optional free-text note.
    var note: String

    /// Stamped so a formula change can trigger a recompute (§7).
    var engineVersion: Int

    var createdAt: Date

    init(
        id: UUID,
        performedAt: Date,
        timeZoneIdentifier: String,
        pattern: MovementPattern,
        entries: [StrengthEntry],
        sessionLoad: Double,
        note: String,
        engineVersion: Int,
        createdAt: Date
    ) {
        self.id = id
        self.performedAt = performedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.patternStorageKey = pattern.storageKey
        self.entries = entries
        self.sessionLoad = sessionLoad
        self.note = note
        self.engineVersion = engineVersion
        self.createdAt = createdAt
    }

    /// The logged pattern. `nil` only if the store carries a key this build does not know.
    var pattern: MovementPattern? {
        MovementPattern.pattern(forStorageKey: patternStorageKey)
    }

    /// `Σ(sets · reps · RPE)` across valid entries (§5.4).
    var totalVolumeLoad: Double {
        entries.totalVolumeLoad
    }

    /// The time zone the session was logged in.
    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0) ?? .gmt
    }
}
