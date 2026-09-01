//
//  HeartRateSample.swift
//  Zenithium
//
//  Sendable intraday heart-rate DTO. Spec §8: `HKQuantitySample` is not `Sendable` and must
//  never cross the actor boundary — the actor maps to this type before returning.
//

import Foundation

/// One intraday heart-rate reading, in beats per minute.
struct HeartRateSample: Sendable, Equatable, Hashable {

    /// The instant the reading applies to. For interval samples this is the start.
    let timestamp: Date

    /// Beats per minute.
    let beatsPerMinute: Double

    /// The bundle identifier of the source that wrote the sample, when known. Used to
    /// prefer the watch over third-party writers when both cover the same window.
    let sourceBundleIdentifier: String?

    init(timestamp: Date, beatsPerMinute: Double, sourceBundleIdentifier: String?) {
        self.timestamp = timestamp
        self.beatsPerMinute = beatsPerMinute
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    /// Whether the reading is physiologically plausible. Implausible samples are dropped at
    /// the boundary rather than clamped, because a 0 bpm or 300 bpm reading is an artefact.
    var isPlausible: Bool {
        beatsPerMinute.isFinite && beatsPerMinute >= 25 && beatsPerMinute <= 240
    }
}
