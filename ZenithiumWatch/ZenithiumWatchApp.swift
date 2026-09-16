//
//  ZenithiumWatchApp.swift
//  ZenithiumWatch
//
//  The watch app. Faz 21.
//
//  ## What this is, and what it deliberately is not
//
//  It is a **reader**. Every number it shows comes from the snapshot the phone writes at the
//  end of each pass, through the shared App Group container. It runs no engine, opens no
//  HealthKit store and holds no SwiftData.
//
//  That is a design decision, not a shortcut. A watch app that recomputed would need its own
//  copy of the pipeline, its own baselines, and its own opinion about the day — and the first
//  time the two disagreed, the user would have two recoveries and no way to tell which was
//  real. One source, one answer, and the wrist is a display for it.
//
//  The one thing it *writes* is a journal tap, and even that goes into the same append-only
//  outbox the home-screen widget uses, drained by the phone.
//

import SwiftUI

@main
struct ZenithiumWatchApp: App {

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

/// Four pages, in the order a wrist is used: what am I at, what should I do, do it, log it.
struct WatchRootView: View {

    @State private var sender = WatchSessionSender.shared
    private var snapshot: WidgetSnapshot { sender.latestSnapshot }
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            WatchRecoveryView(snapshot: snapshot)
                .tag(0)
            WatchPrescriptionView(snapshot: snapshot)
                .tag(1)
            // The session sits between the prescription and the journal, because that is the
            // order the day happens in. Yol haritası v4, C1.
            WatchLiveSessionView()
                .tag(2)
            WatchStrengthView().tag(3)
            WatchJournalView().tag(4)
        }
        .tabViewStyle(.verticalPage)
        .task { sender.start(); sender.flushLogs() }
        .onChange(of: scenePhase) { _, phase in
            // Re-read on every foreground. The phone may have written a new snapshot while
            // the wrist was down, and there is nothing to observe on a file in a shared
            // container — a poll on activation is both the simplest and the cheapest answer.
            if phase == .active { sender.start(); sender.flushLogs() }
        }
    }
}
