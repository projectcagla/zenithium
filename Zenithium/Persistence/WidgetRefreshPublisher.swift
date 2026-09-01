//
//  WidgetRefreshPublisher.swift
//  Zenithium
//
//  The hop from "the shared snapshot changed" to "WidgetKit, redraw".
//
//  ## What was missing
//
//  `DailyRecalculationCoordinator.refreshWidgetTrend` has always written the snapshot the
//  widgets read, and nothing ever told WidgetKit about it. A widget therefore showed
//  whatever its last timeline entry said until the system chose to refresh it on its own
//  schedule — which for a Lock Screen accessory can be a long time after the morning
//  recalculation that produced the new number. The file on disk was current and the screen
//  was not.
//
//  ## Why it is a protocol
//
//  `WidgetCenter` is a system singleton with no seam. Behind this protocol the coordinator's
//  behaviour is assertable: a test can check that a pass with new numbers asks for a reload
//  and a pass with identical numbers does not, without a widget existing.
//
//  ## Why the reload is conditional
//
//  WidgetKit budgets reloads. A pass runs on every foreground and every background refresh,
//  and most of them recompute the same numbers, so reloading unconditionally spends the
//  day's budget on redrawing an unchanged score — and then the budget is gone at the moment
//  the score actually moves. `WidgetSnapshot.hasSameContent(as:)` is the gate.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

/// Tells the widget system that the shared snapshot changed.
protocol WidgetTimelineRefreshing: Sendable {

    /// Reloads every timeline the extension provides.
    func reloadAll()
}

/// The real implementation, on `WidgetCenter`.
struct WidgetCenterRefresher: WidgetTimelineRefreshing {

    init() {}

    func reloadAll() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// Publishes a snapshot and reloads the widgets only when the drawn content changed.
///
/// Owns the write as well as the reload so the two cannot get out of step: there is no path
/// that writes a snapshot without considering whether the widgets need to hear about it.
struct WidgetRefreshPublisher: Sendable {

    private let refresher: any WidgetTimelineRefreshing
    private let readSnapshot: @Sendable () -> WidgetSnapshot
    private let writeSnapshot: @Sendable (WidgetSnapshot) throws -> Void

    /// The file access is injected so the decision this type makes can be asserted without
    /// an App Group. On a test machine there is no shared container, so a publisher wired
    /// straight to `WidgetSnapshotStore` can only ever report `writeFailed` — which would
    /// make every outcome but one untestable.
    init(
        refresher: any WidgetTimelineRefreshing = WidgetCenterRefresher(),
        readSnapshot: @escaping @Sendable () -> WidgetSnapshot = { WidgetSnapshotStore.read() },
        writeSnapshot: @escaping @Sendable (WidgetSnapshot) throws -> Void = {
            try WidgetSnapshotStore.write($0)
        }
    ) {
        self.refresher = refresher
        self.readSnapshot = readSnapshot
        self.writeSnapshot = writeSnapshot
    }

    /// What publishing a snapshot did.
    enum Outcome: Sendable, Equatable {

        /// Written, and the widgets were asked to redraw.
        case published

        /// Written, but the content matched what was already there, so no reload was spent.
        case unchanged

        /// The write failed. The widgets keep the previous file, which is why this is not
        /// allowed to fail the recalculation that produced it.
        case writeFailed

        /// There was nothing to publish — no day record yet, so no snapshot to build.
        /// Distinct from a failure: an app on its first morning is not broken.
        case noData
    }

    /// Writes the snapshot and reloads the widgets if anything they draw actually moved.
    @discardableResult
    func publish(_ snapshot: WidgetSnapshot) -> Outcome {
        let previous = readSnapshot()
        do {
            try writeSnapshot(snapshot)
        } catch {
            ZenithiumLog.widget.error("Widget snapshot write failed")
            return .writeFailed
        }

        // `hasData` is the first-write case: the placeholder matches nothing, but a snapshot
        // arriving where there was none is exactly when the widgets must be told.
        guard previous.hasData, previous.hasSameContent(as: snapshot) else {
            refresher.reloadAll()
            return .published
        }
        return .unchanged
    }
}
