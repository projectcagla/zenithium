//
//  BloodMarker.swift
//  Zenithium
//
//  One recorded blood-marker value. Spec §7 for the fields, §12 for the rule that governs
//  everything built on top of them: ranges and trends only, no interpretation.
//

import Foundation
import SwiftData

@Model
final class BloodMarker {

    /// Stable identity, unique.
    @Attribute(.unique) var id: UUID

    /// `BloodMarkerKind.storageKey`.
    var markerStorageKey: String

    /// The measured value, in `unitSymbol`.
    var value: Double

    /// The unit the value was entered in.
    var unitSymbol: String

    /// Reference range as printed on the user's own lab report, when they entered one.
    /// Falls back to the marker's built-in range for display.
    var refMin: Double?
    var refMax: Double?

    /// The narrower band shown as context (§12 — context, never a target).
    var optimalMin: Double?
    var optimalMax: Double?

    /// When the blood was drawn.
    var drawnAt: Date

    /// Optional free-text note, e.g. fasting state or lab name.
    var note: String

    var createdAt: Date

    init(
        id: UUID,
        marker: BloodMarkerKind,
        value: Double,
        unitSymbol: String,
        refMin: Double?,
        refMax: Double?,
        optimalMin: Double?,
        optimalMax: Double?,
        drawnAt: Date,
        note: String,
        createdAt: Date
    ) {
        self.id = id
        self.markerStorageKey = marker.storageKey
        self.value = value
        self.unitSymbol = unitSymbol
        self.refMin = refMin
        self.refMax = refMax
        self.optimalMin = optimalMin
        self.optimalMax = optimalMax
        self.drawnAt = drawnAt
        self.note = note
        self.createdAt = createdAt
    }

    /// The marker. `nil` only if the store carries a key this build does not know.
    var marker: BloodMarkerKind? {
        BloodMarkerKind.kind(forStorageKey: markerStorageKey)
    }

    /// The reference range to draw: the user's own if entered, else the marker's built-in.
    var effectiveReferenceRange: MarkerRange {
        if refMin != nil || refMax != nil {
            return MarkerRange(minimum: refMin, maximum: refMax)
        }
        return marker?.referenceRange ?? MarkerRange(minimum: nil, maximum: nil)
    }

    /// The optimal band to draw, on the same rule.
    var effectiveOptimalRange: MarkerRange {
        if optimalMin != nil || optimalMax != nil {
            return MarkerRange(minimum: optimalMin, maximum: optimalMax)
        }
        return marker?.optimalRange ?? MarkerRange(minimum: nil, maximum: nil)
    }

    /// Where the value sits across the reference range, 0…1, for positioning a dot on an
    /// axis. Position is not a verdict — §12 forbids interpreting the value.
    var positionInReferenceRange: Double? {
        effectiveReferenceRange.normalizedPosition(of: value)
    }

    var displayName: String {
        marker?.displayName ?? markerStorageKey
    }
}
