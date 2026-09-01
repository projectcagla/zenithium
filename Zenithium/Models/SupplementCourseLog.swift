//
//  SupplementCourseLog.swift
//  Zenithium
//
//  The stored form of `SupplementCourse`. Yol haritası v4, C5.
//

import Foundation
import SwiftData

@Model
final class SupplementCourseLog {

    @Attribute(.unique) var id: UUID
    var name: String
    var startedAt: Date
    var endedAt: Date?
    var note: String

    init(
        id: UUID,
        name: String,
        startedAt: Date,
        endedAt: Date?,
        note: String
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
    }

    /// The value form.
    var course: SupplementCourse {
        SupplementCourse(
            id: id,
            name: name,
            startedAt: startedAt,
            endedAt: endedAt,
            note: note
        )
    }
}
