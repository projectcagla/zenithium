//
//  GoalEventLog.swift
//  Zenithium
//
//  A goal the user is working towards. Faz 20.
//

import Foundation
import SwiftData

@Model
final class GoalEventLog {

    @Attribute(.unique) var id: UUID

    /// `GoalEventKind.rawValue`.
    var kindRawValue: String

    var name: String

    /// Local start of the event's day.
    var eventDate: Date

    /// When the run-up began, if the user said. `nil` falls back to a twelve-week default.
    var planStart: Date?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        kind: GoalEventKind,
        name: String,
        eventDate: Date,
        planStart: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.name = name
        self.eventDate = eventDate
        self.planStart = planStart
        self.createdAt = createdAt
    }

    var kind: GoalEventKind {
        get { GoalEventKind(rawValue: kindRawValue) ?? .other }
        set { kindRawValue = newValue.rawValue }
    }

    var event: GoalEvent {
        GoalEvent(id: id, kind: kind, name: name, date: eventDate)
    }
}
