//
//  HealthChangeEvent.swift
//  Zenithium
//
//  What changed in HealthKit and when. Spec §8 (`observationStream()`), §5.6 (deleted
//  samples must trigger a recompute).
//

import Foundation

/// A change reported by an observer or anchored query.
struct HealthChangeEvent: Sendable, Equatable, Hashable {

    /// The categories that changed. Never empty.
    let kinds: Set<HealthDataKind>

    /// When the change was observed, not when the underlying sample was recorded.
    let observedAt: Date

    /// Whether the change included deletions, which force a recompute rather than an
    /// incremental extension (§5.6).
    let includesDeletions: Bool

    init(kinds: Set<HealthDataKind>, observedAt: Date, includesDeletions: Bool) {
        self.kinds = kinds
        self.observedAt = observedAt
        self.includesDeletions = includesDeletions
    }

    /// Whether this event should wake the recalculation pipeline.
    var shouldTriggerRecalculation: Bool {
        includesDeletions || kinds.contains { $0.triggersRecalculation }
    }

    /// Merges two events observed inside the same debounce window (ASSUMPTION BG-2).
    func merged(with other: HealthChangeEvent) -> HealthChangeEvent {
        HealthChangeEvent(
            kinds: kinds.union(other.kinds),
            observedAt: max(observedAt, other.observedAt),
            includesDeletions: includesDeletions || other.includesDeletions
        )
    }
}
