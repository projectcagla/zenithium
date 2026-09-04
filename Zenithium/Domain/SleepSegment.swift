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
        sourceBundleIdentifier: String? = nil,
        timeZoneIdentifier: String = "UTC"
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

    /// Whether any two segments in the collection overlap in time.
    var hasOverlappingSegments: Bool {
        let sorted = chronological
        for i in 0..<sorted.count {
            for j in (i + 1)..<sorted.count {
                if let overlap = sorted[i].interval.intersection(with: sorted[j].interval),
                   overlap.duration > 0 {
                    return true
                } else if sorted[j].start >= sorted[i].end {
                    break
                }
            }
        }
        return false
    }

    /// Resolves overlapping segments into a non-overlapping partitioned timeline.
    /// At every point where multiple segments coincide, the stage with the highest
    /// specificity priority wins (Deep > REM > Core > Unspecified > Awake > InBed).
    /// Adjacent segments with the same resolved stage are coalesced.
    var resolvedNonOverlapping: [SleepSegment] {
        guard count > 1 else { return self }
        var timestamps = Set<Date>()
        for segment in self {
            guard segment.duration > 0 else { continue }
            timestamps.insert(segment.start)
            timestamps.insert(segment.end)
        }
        let sortedTimes = timestamps.sorted()
        guard sortedTimes.count >= 2 else { return [] }

        var resolved: [SleepSegment] = []
        for i in 0..<(sortedTimes.count - 1) {
            let tStart = sortedTimes[i]
            let tEnd = sortedTimes[i + 1]
            guard tEnd > tStart else { continue }
            let subInterval = DateInterval(start: tStart, end: tEnd)

            let covering = filter { segment in
                segment.start <= tStart && segment.end >= tEnd
            }
            guard let bestSegment = covering.max(by: { $0.stage.resolutionPriority < $1.stage.resolutionPriority }) else { continue }
            let newSegment = SleepSegment(
                interval: subInterval,
                stage: bestSegment.stage,
                sourceBundleIdentifier: bestSegment.sourceBundleIdentifier,
                timeZoneIdentifier: bestSegment.timeZoneIdentifier
            )

            if let last = resolved.last, last.stage == newSegment.stage, last.end == newSegment.start {
                resolved[resolved.count - 1] = SleepSegment(
                    interval: DateInterval(start: last.start, end: newSegment.end),
                    stage: last.stage,
                    sourceBundleIdentifier: last.sourceBundleIdentifier,
                    timeZoneIdentifier: last.timeZoneIdentifier
                )
            } else {
                resolved.append(newSegment)
            }
        }
        return resolved
    }

    /// Total seconds spent in the given stages after resolving overlapping intervals.
    func seconds(in stages: Set<SleepStage>) -> TimeInterval {
        resolvedNonOverlapping
            .filter { stages.contains($0.stage) }
            .reduce(into: 0.0) { $0 += $1.duration }
    }

    /// Total asleep seconds after resolving overlapping intervals (§3).
    var asleepSeconds: TimeInterval {
        resolvedNonOverlapping
            .filter(\.isAsleep)
            .reduce(into: 0.0) { $0 += $1.duration }
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
