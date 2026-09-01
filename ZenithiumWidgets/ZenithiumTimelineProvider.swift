//
//  ZenithiumTimelineProvider.swift
//  ZenithiumWidgets
//
//  Spec §10, ASSUMPTION WIDGET-1: widgets read the App-Group JSON snapshot rather than
//  opening the SwiftData container. A widget process has a tight memory budget and a
//  read-only need; a small file avoids the container-open cost and the schema coupling.
//

import WidgetKit
import SwiftUI

/// One timeline entry.
struct ZenithiumEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot

    static let placeholder = ZenithiumEntry(
        date: Date(timeIntervalSince1970: 0),
        snapshot: .placeholder
    )
}

struct ZenithiumTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> ZenithiumEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ZenithiumEntry) -> Void) {
        completion(ZenithiumEntry(date: Date(), snapshot: WidgetSnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ZenithiumEntry>) -> Void) {
        let now = Date()
        let entry = ZenithiumEntry(date: now, snapshot: WidgetSnapshotStore.read())

        // The app reloads timelines whenever it writes a new snapshot, so this refresh is a
        // backstop for the case where the app has not run — not the primary mechanism.
        let next = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: 1, to: now) ?? now
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

/// Shared pieces of widget presentation, so the three widgets read as one family.
enum WidgetStyle {

    static func bandColor(_ snapshot: WidgetSnapshot) -> Color {
        guard let band = snapshot.recoveryBand else { return ZenithiumColor.textSecondary }
        return ZenithiumColor.color(for: band)
    }

    /// The recovery value as text, or a dash when there is nothing to show.
    static func recoveryText(_ snapshot: WidgetSnapshot) -> String {
        guard let score = snapshot.recoveryScore else { return "—" }
        return ZenithiumFormat.score(score)
    }

    /// The spoken value, which must be a sentence rather than a number on its own.
    static func recoveryAccessibilityValue(_ snapshot: WidgetSnapshot) -> String {
        guard let score = snapshot.recoveryScore, let band = snapshot.recoveryBand else {
            return snapshot.isCalibrating
                ? "Hâlâ kalibrasyonda, \(ZenithiumFormat.percent(snapshot.calibrationProgress)) tamam"
                : "Henüz puan yok"
        }
        return "yüzde \(ZenithiumFormat.score(score)), \(band.displayName) bandı"
    }

    static func strainAccessibilityValue(_ snapshot: WidgetSnapshot) -> String {
        guard let ceiling = snapshot.targetCeiling else {
            return "21 üzerinden \(ZenithiumFormat.strain(snapshot.dayStrain))"
        }
        return "\(ZenithiumFormat.strain(snapshot.dayStrain)), \(ZenithiumFormat.strain(ceiling)) hedefi"
    }
}
