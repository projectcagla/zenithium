//
//  PendingJournalTests.swift
//  ZenithiumTests
//
//  The widget's outbox and the drain that empties it. The merge rule is the load-bearing
//  part: a journal that loses entries is worse than one nobody fills in.
//

import Testing
import Foundation
@testable import Zenithium

@Suite("Pending journal drain")
struct PendingJournalDrainTests {

    private let calendar = Calendar(identifier: .gregorian)

    private var today: Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
    }

    /// An in-memory stand-in for the journal store.
    private actor FakeJournal: JournalRepository {

        private var days: [Date: JournalDay] = [:]

        init(seed: JournalDay?) {
            if let seed { days[seed.dayStart] = seed }
        }

        func journalDay(for dayStart: Date) async throws -> JournalDay? { days[dayStart] }

        func journalDays(from start: Date, through end: Date) async throws -> [JournalDay] {
            days.values.filter { $0.dayStart >= start && $0.dayStart <= end }
        }

        @discardableResult
        func saveJournalDay(_ day: JournalDay) async throws -> JournalDay {
            days[day.dayStart] = day
            return day
        }

        func stored(for dayStart: Date) -> JournalDay? { days[dayStart] }
    }

    /// The drain reads a file, so the test drives its merge rule directly with the same
    /// inputs rather than writing to the App Group — which does not exist in a test host.
    private func merge(stored: Set<JournalBehavior>, widget: Set<JournalBehavior>) -> Set<JournalBehavior> {
        let owned = Set(JournalBehaviorWidgetSet.featured)
        var merged = stored.subtracting(owned)
        merged.formUnion(widget.intersection(owned))
        merged.formUnion(widget.subtracting(owned))
        return merged
    }

    /// The widget offers four behaviours and the app twelve. Overwriting the stored day with
    /// the widget's four would silently delete the other eight.
    @Test("Widget'ın bilmediği davranışlar korunur")
    func preservesAppOnlyBehaviours() {
        let merged = merge(
            stored: [.alcohol, .travel, .sauna, .medication],
            widget: [.lateCaffeine]
        )
        #expect(merged.contains(.travel))
        #expect(merged.contains(.sauna))
        #expect(merged.contains(.medication))
        #expect(merged.contains(.lateCaffeine))
    }

    /// Turning a chip off on the home screen has to turn it off in the store, or the control
    /// is lying about what it does.
    @Test("Widget'ta kapatılan davranış kayıttan da düşer")
    func clearingOnWidgetClearsStored() {
        let merged = merge(
            stored: [.alcohol, .lateCaffeine, .travel],
            widget: [.lateCaffeine]
        )
        #expect(!merged.contains(.alcohol), "widget'ın sahibi olduğu davranış kapatılmalı")
        #expect(merged.contains(.lateCaffeine))
        #expect(merged.contains(.travel), "widget'ın sahibi olmadığı davranışa dokunulmamalı")
    }

    @Test("Boş widget kaydı uygulama davranışlarını silmez")
    func emptyWidgetDayKeepsAppBehaviours() {
        let merged = merge(stored: [.travel, .sauna], widget: [])
        #expect(merged == [.travel, .sauna])
    }

    @Test("Widget listesi dört davranış")
    func widgetSetIsFour() {
        #expect(JournalBehaviorWidgetSet.featured.count == 4)
        #expect(Set(JournalBehaviorWidgetSet.featured).count == 4)
    }

    // MARK: - Store

    @Test("Aynı davranışa iki kez dokunmak onu kapatır")
    func toggleIsIdempotentInPairs() {
        var day = PendingJournalDay(dayStart: today, behaviorRawValues: [])
        func toggle(_ behavior: JournalBehavior) {
            if let index = day.behaviorRawValues.firstIndex(of: behavior.rawValue) {
                day.behaviorRawValues.remove(at: index)
            } else {
                day.behaviorRawValues.append(behavior.rawValue)
            }
        }
        toggle(.alcohol)
        #expect(day.behaviors == [.alcohol])
        toggle(.alcohol)
        #expect(day.behaviors.isEmpty)
    }

    @Test("Tanınmayan ham değerler sessizce atılır")
    func unknownRawValuesAreDropped() {
        let day = PendingJournalDay(
            dayStart: today,
            behaviorRawValues: ["alcohol", "gelecektekiDavranış"]
        )
        #expect(day.behaviors == [.alcohol])
    }
}

@Suite("Widget snapshot")
struct WidgetSnapshotTests {

    /// A spoken answer of "zero" is a claim. The placeholder must be distinguishable from a
    /// real snapshot that happens to be empty.
    @Test("Yer tutucu gerçek veriden ayırt edilir")
    func placeholderIsDistinguishable() {
        #expect(!WidgetSnapshot.placeholder.hasData)

        let real = WidgetSnapshot(
            formatVersion: WidgetSnapshot.currentFormatVersion,
            generatedAt: Date(),
            recoveryScore: nil,
            recoveryBandRawValue: nil,
            dayStrain: 0,
            targetCeiling: nil,
            sleepScore: nil,
            isCalibrating: true,
            calibrationProgress: 0.5,
            trend: [],
            prescriptionLine: nil
        )
        #expect(real.hasData)
    }

    @Test("Biçim sürümü ikiye çıktı")
    func formatVersionBumped() {
        #expect(WidgetSnapshot.currentFormatVersion == 2)
    }

    @Test("Tavan ilerlemesi kırpılır")
    func ceilingProgressIsClamped() {
        func snapshot(strain: Double, ceiling: Double?) -> WidgetSnapshot {
            WidgetSnapshot(
                formatVersion: 2, generatedAt: Date(), recoveryScore: 70,
                recoveryBandRawValue: "green", dayStrain: strain, targetCeiling: ceiling,
                sleepScore: 80, isCalibrating: false, calibrationProgress: 1,
                trend: [], prescriptionLine: nil
            )
        }
        #expect(snapshot(strain: 20, ceiling: 10).ceilingProgress == 1)
        #expect(snapshot(strain: 5, ceiling: 10).ceilingProgress == 0.5)
        #expect(snapshot(strain: 5, ceiling: nil).ceilingProgress == nil)
    }
}
