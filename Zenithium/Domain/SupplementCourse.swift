//
//  SupplementCourse.swift
//  Zenithium
//
//  A supplement or medication, and the window it was taken in. Yol haritası v4, C5.
//
//  ## Why a course and not a daily tap
//
//  Journal behaviours are per-night: you drank last night or you did not. Supplements are
//  not taken that way. Somebody starts creatine and takes it for four months; asking them to
//  tap it every morning for a hundred and twenty days would produce a worse record than
//  asking them once when they started.
//
//  So a course has a start and an optional end, and expands to per-day presence when the
//  correlation engine needs it. The comparison then falls out of the machinery that already
//  exists: nights during the course against nights before it.
//
//  ## What this is not
//
//  Not a medication reminder, not a dosage tracker, and not a claim about anything. §12
//  applies with particular force here — the app reports that a measurement differed between
//  two windows, and never that a substance caused it. `CorrelationEngine.summary` already
//  enforces that wording, and this type feeds it rather than writing its own.
//

import Foundation

/// A supplement or medication, and when it was taken.
struct SupplementCourse: Sendable, Equatable, Hashable, Identifiable, Codable {

    let id: UUID

    /// The person's own name for it. Not matched against any catalogue — "kreatin",
    /// "D vitamini", a brand name, all equally valid.
    let name: String

    /// The first day it was taken.
    let startedAt: Date

    /// The last day, or `nil` while it is ongoing.
    let endedAt: Date?

    /// Free-text note: dose, brand, why.
    let note: String

    init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        endedAt: Date? = nil,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
    }

    /// Whether the course was running on a given day.
    func covers(_ dayStart: Date) -> Bool {
        guard dayStart >= startedAt else { return false }
        guard let endedAt else { return true }
        return dayStart <= endedAt
    }

    var isOngoing: Bool { endedAt == nil }

    /// How long it has run, in days, up to `now`.
    func days(through now: Date) -> Int {
        let end = endedAt ?? now
        guard end >= startedAt else { return 0 }
        return Int((end.timeIntervalSince(startedAt) / 86_400).rounded()) + 1
    }

    /// The subject this course becomes when the correlation engine looks at it.
    var correlationSubject: CorrelationSubject { .supplement(name) }
}
