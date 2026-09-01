//
//  PainEntryLog.swift
//  Zenithium
//
//  A logged pain entry. Faz 32.
//

import Foundation
import SwiftData

@Model
final class PainEntryLog {

    @Attribute(.unique) var id: UUID

    /// `MuscleGroup.rawValue`.
    var muscleRawValue: String

    /// `BodyLaterality.rawValue`.
    var lateralityRawValue: String

    /// The user's own 0–10 rating.
    var severity: Int

    /// `PainQuality.rawValue`.
    var qualityRawValue: String

    var loggedAt: Date
    var note: String
    var createdAt: Date

    init(entry: PainEntry, createdAt: Date = Date()) {
        self.id = entry.id
        self.muscleRawValue = entry.muscle.rawValue
        self.lateralityRawValue = entry.laterality.rawValue
        self.severity = entry.severity
        self.qualityRawValue = entry.quality.rawValue
        self.loggedAt = entry.loggedAt
        self.note = entry.note
        self.createdAt = createdAt
    }

    /// The value, or `nil` when a raw value no longer resolves — which can only happen if a
    /// future build removes a case, and dropping the row is better than inventing a region.
    var entry: PainEntry? {
        guard let muscle = MuscleGroup(rawValue: muscleRawValue),
              let laterality = BodyLaterality(rawValue: lateralityRawValue),
              let quality = PainQuality(rawValue: qualityRawValue) else { return nil }
        return PainEntry(
            id: id,
            muscle: muscle,
            laterality: laterality,
            severity: severity,
            quality: quality,
            loggedAt: loggedAt,
            note: note
        )
    }
}
