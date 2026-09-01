//
//  JournalDayLog.swift
//  Zenithium
//
//  Bir günün günlük kaydı.
//

import Foundation
import SwiftData

@Model
final class JournalDayLog {

    /// Kaydın ait olduğu yerel gece yarısı. Günde tek kayıt.
    @Attribute(.unique) var dayStart: Date

    /// `JournalBehavior.rawValue` listesi.
    var behaviorRawValues: [String]

    /// `MoodRating.rawValue`, kaydedilmişse.
    var moodRawValue: Int?

    var note: String

    var createdAt: Date
    var updatedAt: Date

    init(
        dayStart: Date,
        behaviorRawValues: [String],
        moodRawValue: Int?,
        note: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.dayStart = dayStart
        self.behaviorRawValues = behaviorRawValues
        self.moodRawValue = moodRawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var behaviors: Set<JournalBehavior> {
        get { Set(behaviorRawValues.compactMap { JournalBehavior(rawValue: $0) }) }
        set { behaviorRawValues = newValue.map(\.rawValue).sorted() }
    }

    var mood: MoodRating? {
        get { moodRawValue.flatMap { MoodRating(rawValue: $0) } }
        set { moodRawValue = newValue?.rawValue }
    }

    var journalDay: JournalDay {
        JournalDay(dayStart: dayStart, behaviors: behaviors, mood: mood, note: note)
    }
}
