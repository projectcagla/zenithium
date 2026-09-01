//
//  PendingJournalDrain.swift
//  Zenithium
//
//  Moves the widget's taps into the store. Faz 22.
//
//  The widget cannot write SwiftData, so it appends to a file; this is the other half of
//  that arrangement. It runs on foreground, before any screen reads the journal, so a
//  behaviour tapped on the home screen is already there when the app opens.
//

import Foundation

enum PendingJournalDrain {

    /// Merge whatever the widget recorded into the stored day.
    ///
    /// A **union**, never a replacement. The widget offers four behaviours and the app
    /// twelve; overwriting the stored day with the widget's four would silently delete the
    /// other eight, and a journal that loses entries is worse than one nobody fills in.
    ///
    /// Returns whether anything changed, so the caller can decide whether to reload.
    @discardableResult
    static func drain(
        into repository: any JournalRepository,
        calendar: Calendar = .current
    ) async -> Bool {
        guard let pending = PendingJournalStore.drain() else { return false }
        let behaviors = pending.behaviors

        let dayStart = calendar.startOfDay(for: pending.dayStart)
        let existing = try? await repository.journalDay(for: dayStart)

        // A behaviour the widget shows but the user cleared there must come *off* the stored
        // day too — otherwise turning a chip off on the home screen does nothing, which is a
        // control that lies. So the widget's four are replaced wholesale and everything else
        // is preserved.
        let widgetOwned = Set(JournalBehaviorWidgetSet.featured)
        var merged = (existing?.behaviors ?? []).subtracting(widgetOwned)
        merged.formUnion(behaviors.intersection(widgetOwned))

        // Behaviours the widget does not offer, but somehow recorded, are still honoured —
        // a future widget build may offer more, and dropping them would lose real entries.
        merged.formUnion(behaviors.subtracting(widgetOwned))

        guard merged != (existing?.behaviors ?? []) else { return false }

        let day = JournalDay(
            dayStart: dayStart,
            behaviors: merged,
            mood: existing?.mood,
            note: existing?.note ?? ""
        )
        do {
            try await repository.saveJournalDay(day)
            return true
        } catch {
            ZenithiumLog.store.error("Widget günlük girdileri kaydedilemedi")
            return false
        }
    }
}
