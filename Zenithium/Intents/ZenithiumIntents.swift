//
//  ZenithiumIntents.swift
//  Zenithium
//
//  App Intents, Siri and Shortcuts. Faz 22.
//
//  Every intent here answers from the **shared snapshot** the widgets already read, never by
//  running the pipeline. Two reasons, and both matter. Siri gives an intent a very short
//  budget, and a recalculation involves HealthKit reads that will overrun it. And an intent
//  that recomputes could disagree with the app's own screen a second later, which is worse
//  than being slightly stale — a number that changes depending on how you asked for it is
//  not a number anybody can trust.
//
//  So: the app writes the snapshot at the end of every pass, and everything outside the app
//  reads it. One source, one answer.
//

import AppIntents
import Foundation

/// "Bugün ne kadar toparlandım?"
struct RecoveryQueryIntent: AppIntent {

    static let title: LocalizedStringResource = "Toparlanmamı sor"
    static let description = IntentDescription(
        "Bugünün toparlanma puanını ve zorlanma tavanını söyler.",
        categoryName: "Zenithium"
    )

    /// Answered without opening the app: the whole point is not to.
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = WidgetSnapshotStore.read()
        guard snapshot.hasData else {
            return .result(dialog: "Henüz bir puan yok. Saatini gece takarak yat, sabah hazır olur.")
        }
        guard let score = snapshot.recoveryScore else {
            return .result(
                dialog: IntentDialog(stringLiteral: snapshot.calibrationProgress < 1
                    ? "Taban çizgin hâlâ kuruluyor — %\(Int(snapshot.calibrationProgress * 100)) tamam."
                    : "Bugün için bir toparlanma puanı üretemedim.")
            )
        }

        var sentence = "Toparlanman \(Int(score.rounded()))."
        if let ceiling = snapshot.targetCeiling {
            sentence += " Bugünün zorlanma tavanı \(ZenithiumFormat.strain(ceiling))."
        }
        sentence += " Şu an \(ZenithiumFormat.strain(snapshot.dayStrain))'desin."
        return .result(dialog: IntentDialog(stringLiteral: sentence))
    }
}

/// "Bugün ne kadar zorlandım?"
struct StrainQueryIntent: AppIntent {

    static let title: LocalizedStringResource = "Zorlanmamı sor"
    static let description = IntentDescription(
        "Bugüne kadar biriken zorlanmayı ve tavanı söyler.",
        categoryName: "Zenithium"
    )

    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = WidgetSnapshotStore.read()
        guard snapshot.hasData else {
            return .result(dialog: "Bugün için henüz veri yok.")
        }
        let strain = ZenithiumFormat.strain(snapshot.dayStrain)
        guard let ceiling = snapshot.targetCeiling else {
            return .result(dialog: IntentDialog(stringLiteral: "Bugünkü zorlanman \(strain)."))
        }
        let remaining = ceiling - snapshot.dayStrain
        let sentence = remaining > 0
            ? "Bugünkü zorlanman \(strain), tavanın \(ZenithiumFormat.strain(ceiling)). \(ZenithiumFormat.strain(remaining)) kadar alanın var."
            : "Bugünkü zorlanman \(strain) ve tavanın \(ZenithiumFormat.strain(ceiling)) — tavanı geçtin."
        return .result(dialog: IntentDialog(stringLiteral: sentence))
    }
}

/// "Zenithium'da uykumu göster" — opens the sleep screen.
struct OpenSleepIntent: AppIntent {

    static let title: LocalizedStringResource = "Uykumu aç"
    static let description = IntentDescription("Zenithium'u uyku ekranında açar.", categoryName: "Zenithium")

    /// This one *does* open the app, because there is nothing useful to say about a
    /// hypnogram out loud.
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await DeepLink.request(.sleep)
        return .result()
    }
}

/// Where an intent asked the app to go.
///
/// A plain shared box rather than a URL scheme: the app and its intents are one binary, so
/// round-tripping through a URL would be ceremony. Read and cleared on the next foreground.
enum DeepLink {

    enum Destination: String, Sendable {
        case today
        case sleep
        case journal
    }

    /// The last destination an intent requested.
    ///
    /// Isolated to the main actor rather than declared `nonisolated(unsafe)`. The unsafe
    /// version was argued for on the grounds that a single enum assignment is too small a
    /// window to race in — which is an argument the compiler cannot check and the one place
    /// in the app that asked to be trusted rather than verified. The hop it was avoiding
    /// costs nothing: the only writer is an `async` intent, and the only reader is a SwiftUI
    /// view that is on this actor already.
    @MainActor private static var pending: Destination?

    /// Records where an intent wants the app to open.
    @MainActor static func request(_ destination: Destination) {
        pending = destination
    }

    /// Take the pending destination, clearing it.
    @MainActor static func take() -> Destination? {
        defer { pending = nil }
        return pending
    }
}

/// The Shortcuts entries offered without the user building anything.
struct ZenithiumShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecoveryQueryIntent(),
            phrases: [
                "\(.applicationName) toparlanmam ne",
                "\(.applicationName) bugün nasılım",
                "\(.applicationName) recovery"
            ],
            shortTitle: "Toparlanma",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: StrainQueryIntent(),
            phrases: [
                "\(.applicationName) zorlanmam ne",
                "\(.applicationName) strain"
            ],
            shortTitle: "Zorlanma",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: OpenSleepIntent(),
            phrases: ["\(.applicationName) uykumu göster"],
            shortTitle: "Uyku",
            systemImageName: "moon.zzz.fill"
        )
    }
}
