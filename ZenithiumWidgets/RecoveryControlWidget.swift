//
//  RecoveryControlWidget.swift
//  ZenithiumWidgets
//
//  The Control Center control. Faz 22, iOS 18.
//
//  A control is not a small widget. It has room for a value and a symbol and nothing else,
//  so the only question worth answering here is the one the user opened Control Centre to
//  ask: what is my recovery. Tapping it opens the app.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct RecoveryControlWidget: ControlWidget {

    nonisolated static let kind = "com.zenithium.app.control.recovery"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenZenithiumIntent()) {
                let snapshot = WidgetSnapshotStore.read()
                Label {
                    Text(Self.valueText(for: snapshot))
                } icon: {
                    Image(systemName: snapshot.recoveryBand?.symbolName ?? "heart.fill")
                }
            }
        }
        .displayName("Toparlanma")
        .description("Bugünün toparlanma puanı.")
    }

    /// The control's single line of text.
    ///
    /// A calibrating baseline shows its progress rather than a dash: "still learning" is
    /// information, and an em-dash is not.
    nonisolated static func valueText(for snapshot: WidgetSnapshot) -> String {
        if let score = snapshot.recoveryScore {
            return "\(Int(score.rounded()))"
        }
        if snapshot.isCalibrating {
            return "%\(Int((snapshot.calibrationProgress * 100).rounded()))"
        }
        return "—"
    }
}

/// Opens the app. A control's action must be an intent, even when the intent only opens.
struct OpenZenithiumIntent: AppIntent {

    static let title: LocalizedStringResource = "Zenithium'u aç"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}
