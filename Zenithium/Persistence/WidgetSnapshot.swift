//
//  WidgetSnapshot.swift
//  Zenithium
//
//  The payload shared with the widget extension through the App Group.
//
//  ASSUMPTION WIDGET-1: widgets read this JSON rather than opening the SwiftData container.
//  A widget process has a tight memory budget and a read-only need; a small file avoids both
//  the container-open cost and coupling the extension to the schema.
//
//  This file is a member of *both* targets, which is why it lives in `Persistence` rather
//  than in the widget folder: one declaration, no drift.
//

import Foundation

/// One day in the three-day trend.
struct WidgetTrendPoint: Codable, Sendable, Equatable, Hashable {
    let dayStart: Date
    let recoveryScore: Double?
    let dayStrain: Double
    let sleepScore: Double?
}

/// Everything the widgets render.
struct WidgetSnapshot: Codable, Sendable, Equatable {

    /// Bumped when the payload shape changes, so an old file is ignored rather than
    /// half-decoded into a misleading widget.
    let formatVersion: Int

    let generatedAt: Date
    let recoveryScore: Double?
    let recoveryBandRawValue: String?
    let dayStrain: Double
    let targetCeiling: Double?
    let sleepScore: Double?
    let isCalibrating: Bool
    let calibrationProgress: Double
    let trend: [WidgetTrendPoint]

    /// Today's prescribed session, as one line. Faz 21/22.
    ///
    /// Carried on the snapshot rather than recomputed outside the app for the same reason
    /// every other field is: the watch and the widgets must not be able to disagree with the
    /// phone about what today's suggestion is. `nil` when there is no prescription — a health
    /// lens on a rest day, or a morning with no score.
    let prescriptionLine: String?

    /// Version 2 added `prescriptionLine`. A version-1 file is ignored rather than decoded
    /// with a missing field, which is the point of the check.
    static let currentFormatVersion = 2

    var recoveryBand: RecoveryBand? {
        recoveryBandRawValue.flatMap(RecoveryBand.init(rawValue:))
    }

    /// The placeholder a widget shows before any data exists.
    static let placeholder = WidgetSnapshot(
        formatVersion: currentFormatVersion,
        generatedAt: Date(timeIntervalSince1970: 0),
        recoveryScore: nil,
        recoveryBandRawValue: nil,
        dayStrain: 0,
        targetCeiling: nil,
        sleepScore: nil,
        isCalibrating: true,
        calibrationProgress: 0,
        trend: [],
        prescriptionLine: nil
    )

    /// Whether this is a real snapshot rather than the placeholder.
    ///
    /// The placeholder carries the epoch as its timestamp, so one comparison distinguishes
    /// "nothing has ever been written" from "written and empty" — which a widget renders the
    /// same way but an intent must not, because a spoken answer of "zero" is a claim.
    var hasData: Bool {
        generatedAt > Date(timeIntervalSince1970: 1)
    }

    /// Whether this snapshot would draw the same widget as another one.
    ///
    /// Everything except `generatedAt`. A recalculation pass runs on every foreground and
    /// every background refresh, and almost all of them recompute the same numbers — so
    /// `Equatable` is the wrong test for "should the widgets be told": it is never true,
    /// because the timestamp always moves.
    ///
    /// WidgetKit budgets timeline reloads, and a budget spent on redrawing an unchanged
    /// number is a redraw the widget does not get later when the number actually changes.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        formatVersion == other.formatVersion
            && recoveryScore == other.recoveryScore
            && recoveryBandRawValue == other.recoveryBandRawValue
            && dayStrain == other.dayStrain
            && targetCeiling == other.targetCeiling
            && sleepScore == other.sleepScore
            && isCalibrating == other.isCalibrating
            && calibrationProgress == other.calibrationProgress
            && trend == other.trend
            && prescriptionLine == other.prescriptionLine
    }

    /// Strain as a fraction of the ceiling, for the small widget's gauge.
    var ceilingProgress: Double? {
        guard let targetCeiling, targetCeiling > 0 else { return nil }
        return min(max(dayStrain / targetCeiling, 0), 1)
    }
}

/// Writes and reads the shared snapshot file.
enum WidgetSnapshotStore {

    /// Writes atomically, so a widget reading mid-write sees the old file rather than a
    /// truncated one.
    static func write(_ snapshot: WidgetSnapshot) throws {
        guard let url = AppGroup.widgetSnapshotURL else {
            throw ZenithiumError.appGroupUnavailable(identifier: AppGroup.identifier)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch let error as ZenithiumError {
            throw error
        } catch {
            throw ZenithiumError.persistenceWriteFailed(detail: error.localizedDescription)
        }
    }

    /// Reads the snapshot, returning the placeholder when the file is missing, unreadable, or
    /// written by a different format version.
    static func read() -> WidgetSnapshot {
        guard let url = AppGroup.widgetSnapshotURL,
              let data = try? Data(contentsOf: url) else {
            return .placeholder
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.formatVersion == WidgetSnapshot.currentFormatVersion else {
            return .placeholder
        }
        return snapshot
    }
}
