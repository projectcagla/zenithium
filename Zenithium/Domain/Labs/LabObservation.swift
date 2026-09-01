//
//  LabObservation.swift
//  Zenithium
//
//  What the laboratory panel has to say. Faz 23.
//
//  In `Domain` rather than beside the engine that produces it, because `BriefingIO` reads it
//  and `Domain` may not depend on `Engines` — the arrow points one way. That rule is not
//  bookkeeping: the watch target compiles `Domain` and none of the engines, so a domain type
//  reaching into an engine is a target that will not link.
//
//  §12 governs every string built from these: an observation about a value outside its
//  reference band routes to a clinician and says nothing else.
//

import Foundation

/// What one observation is about.
enum LabObservationKind: Sendable, Equatable, Hashable {

    /// The value sits outside the laboratory's reference band. Always routes to a clinician.
    case outsideReference(isAbove: Bool)

    /// Inside the reference band but outside the narrower band the literature cites.
    case outsideOptimal(isAbove: Bool)

    /// The marker has moved since the previous draw.
    case movement(delta: Double, days: Int)

    /// The most recent value is older than the marker's own retest interval.
    case aging(months: Int)

    /// A panel is partly filled in, so a value cannot be read in context.
    case panelGap(panel: BiomarkerPanel, missing: [String])

    /// The marker is known to move with recent training, and there *was* recent training.
    case timingCaveat(hoursSinceSession: Int)

    /// Something true about how the marker behaves in training.
    case context
}

/// One thing worth saying about one marker.
struct LabObservation: Sendable, Equatable, Hashable, Identifiable {

    let id: String
    let marker: BloodMarkerKind
    let kind: LabObservationKind

    /// The sentence shown to the user.
    let message: String

    /// Whether the sentence must be accompanied by the clinician prompt. Set for anything
    /// outside a reference band, without exception.
    let requiresClinician: Bool

    /// Sort weight — higher first.
    let priority: Int
}
