//
//  SleepSegment.swift
//  Zenithium
//
//  Sendable sleep-interval DTO. Spec §3 (stage taxonomy), §5.6 (the time zone in effect at
//  the record's date is stored on the record).
//

import Foundation

/// One contiguous run of a single sleep stage.
struct SleepSegment: Sendable, Equatable, Hashable {

    /// The interval the stage covers.
    let interval: DateInterval

    /// The stage recorded for the interval.
    let stage: SleepStage

    /// The bundle identifier of the writing source, when known.
    let sourceBundleIdentifier: String?

    /// The identifier of the time zone in effect when the segment was recorded (§5.6).
    let timeZoneIdentifier: String

    init(
        interval: DateInterval,
        stage: SleepStage,
        sourceBundleIdentifier: String?,
        timeZoneIdentifier: String
    ) {
        self.interval = interval
        self.stage = stage
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var start: Date { interval.start }
    var end: Date { interval.end }
    var duration: TimeInterval { interval.duration }

    /// Spec §3 — asleep is core + deep + REM (plus unspecified); `.inBed` never counts.
    var isAsleep: Bool { stage.isAsleep }
}

extension Array where Element == SleepSegment {

    /// Total seconds spent in the given stages.
    func seconds(in stages: Set<SleepStage>) -> TimeInterval {
        reduce(into: 0) { total, segment in
            if stages.contains(segment.stage) {
                total += segment.duration
            }
        }
    }

    /// Total asleep seconds (§3).
    var asleepSeconds: TimeInterval {
        reduce(into: 0) { total, segment in
            if segment.isAsleep { total += segment.duration }
        }
    }

    /// Whether any segment carries stage detail, which decides whether `Restorative` can be
    /// scored or must be dropped with the remaining weights renormalized (§5.2).
    var hasStageDetail: Bool {
        contains { $0.stage.isStaged }
    }

    /// Segments sorted by start, then by end, so ordering is deterministic.
    var chronological: [SleepSegment] {
        sorted { lhs, rhs in
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
    }
}
