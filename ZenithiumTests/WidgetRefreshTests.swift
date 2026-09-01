//
//  WidgetRefreshTests.swift
//  ZenithiumTests
//
//  The hop from a written snapshot to a redrawn widget, and the gate that keeps it from
//  spending WidgetKit's reload budget on numbers that did not move.
//
//  These assert counts rather than observing a widget: `WidgetCenter` has no seam, which is
//  why the coordinator talks to `WidgetTimelineRefreshing` instead.
//

import Testing
import Foundation
@testable import Zenithium

/// Counts reload requests instead of making them.
private final class CountingRefresher: WidgetTimelineRefreshing, @unchecked Sendable {

    // Mutated from one task at a time in these tests, and read after it has finished. The
    // `@unchecked` is the honest label for that: a counter with no synchronisation, kept
    // inside a single test's lifetime.
    private(set) var reloadCount = 0

    func reloadAll() {
        reloadCount += 1
    }
}

@Suite("Widget refresh publisher")
struct WidgetRefreshPublisherTests {

    private func snapshot(
        recovery: Double?,
        strain: Double,
        generatedAt: Date
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            formatVersion: WidgetSnapshot.currentFormatVersion,
            generatedAt: generatedAt,
            recoveryScore: recovery,
            recoveryBandRawValue: recovery.map { $0 >= 67 ? "green" : "yellow" },
            dayStrain: strain,
            targetCeiling: 14,
            sleepScore: 80,
            isCalibrating: false,
            calibrationProgress: 1,
            trend: [],
            prescriptionLine: "45 dakika kolay"
        )
    }

    @Test("Aynı içerik, farklı zaman damgası — yeniden çizim istenmiyor")
    func identicalContentDoesNotSpendAReload() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let first = snapshot(recovery: 72, strain: 9, generatedAt: now)
        let second = snapshot(recovery: 72, strain: 9, generatedAt: now.addingTimeInterval(900))

        // `generatedAt` her geçişte ilerliyor, yani `Equatable` burada asla doğru olmuyor.
        #expect(first != second)
        #expect(first.hasSameContent(as: second))
    }

    @Test("Değişen her alan içerik farkı sayılıyor")
    func everyDrawnFieldCountsAsAChange() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let base = snapshot(recovery: 72, strain: 9, generatedAt: now)

        #expect(!base.hasSameContent(as: snapshot(recovery: 73, strain: 9, generatedAt: now)))
        #expect(!base.hasSameContent(as: snapshot(recovery: 72, strain: 9.5, generatedAt: now)))
        #expect(!base.hasSameContent(as: snapshot(recovery: nil, strain: 9, generatedAt: now)))
    }

    @Test("Üç günlük eğilim değişince de fark sayılıyor")
    func trendChangeCountsAsAChange() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        var withTrend = snapshot(recovery: 72, strain: 9, generatedAt: now)
        withTrend = WidgetSnapshot(
            formatVersion: withTrend.formatVersion,
            generatedAt: withTrend.generatedAt,
            recoveryScore: withTrend.recoveryScore,
            recoveryBandRawValue: withTrend.recoveryBandRawValue,
            dayStrain: withTrend.dayStrain,
            targetCeiling: withTrend.targetCeiling,
            sleepScore: withTrend.sleepScore,
            isCalibrating: withTrend.isCalibrating,
            calibrationProgress: withTrend.calibrationProgress,
            trend: [WidgetTrendPoint(dayStart: now, recoveryScore: 70, dayStrain: 8, sleepScore: 79)],
            prescriptionLine: withTrend.prescriptionLine
        )
        #expect(!snapshot(recovery: 72, strain: 9, generatedAt: now).hasSameContent(as: withTrend))
    }

    @Test("Yer tutucu, gerçek bir anlık görüntüyle eşleşmiyor")
    func placeholderNeverMatchesRealData() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        #expect(!WidgetSnapshot.placeholder.hasData)
        #expect(!WidgetSnapshot.placeholder.hasSameContent(as: snapshot(recovery: 72, strain: 9, generatedAt: now)))
    }

    // MARK: - Outcomes

    /// A publisher over an in-memory file, so all four outcomes are reachable without an
    /// App Group.
    private func makePublisher(
        stored: WidgetSnapshot,
        refresher: CountingRefresher,
        writeFails: Bool = false
    ) -> WidgetRefreshPublisher {
        WidgetRefreshPublisher(
            refresher: refresher,
            readSnapshot: { stored },
            writeSnapshot: { _ in
                if writeFails {
                    throw ZenithiumError.persistenceWriteFailed(detail: "test")
                }
            }
        )
    }

    @Test("Sayı değişince widget'lara yeniden çizim söyleniyor")
    func aChangedScoreAsksForARedraw() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let refresher = CountingRefresher()
        let publisher = makePublisher(
            stored: snapshot(recovery: 72, strain: 9, generatedAt: now),
            refresher: refresher
        )

        let outcome = publisher.publish(
            snapshot(recovery: 64, strain: 11, generatedAt: now.addingTimeInterval(3_600))
        )

        #expect(outcome == .published)
        #expect(refresher.reloadCount == 1)
    }

    /// The regression this gate exists for: a pass runs on every foreground, and reloading
    /// each time spends the day's budget on redrawing a number that did not move.
    @Test("Sayı değişmeyince yeniden çizim bütçesi harcanmıyor")
    func anUnchangedScoreSpendsNothing() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let refresher = CountingRefresher()
        let publisher = makePublisher(
            stored: snapshot(recovery: 72, strain: 9, generatedAt: now),
            refresher: refresher
        )

        for minute in 1...5 {
            let outcome = publisher.publish(
                snapshot(recovery: 72, strain: 9, generatedAt: now.addingTimeInterval(Double(minute) * 60))
            )
            #expect(outcome == .unchanged)
        }
        #expect(refresher.reloadCount == 0)
    }

    @Test("İlk yazma her zaman yeniden çizim istiyor")
    func theFirstWriteAlwaysRedraws() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let refresher = CountingRefresher()
        let publisher = makePublisher(stored: .placeholder, refresher: refresher)

        #expect(publisher.publish(snapshot(recovery: 72, strain: 9, generatedAt: now)) == .published)
        #expect(refresher.reloadCount == 1)
    }

    @Test("Yazma başarısızsa yeniden çizim istenmiyor")
    func aFailedWriteDoesNotRedraw() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let refresher = CountingRefresher()
        let publisher = makePublisher(
            stored: .placeholder,
            refresher: refresher,
            writeFails: true
        )

        // The widgets keep the previous file, so telling them to redraw would only make them
        // draw the old number again.
        #expect(publisher.publish(snapshot(recovery: 72, strain: 9, generatedAt: now)) == .writeFailed)
        #expect(refresher.reloadCount == 0)
    }
}

@Suite("Shared persistence factory")
struct SharedPersistenceFactoryTests {

    @Test("Uygulama rolü yazabilir, uzantı rolü yazamaz")
    func onlyTheAppMayWrite() {
        #expect(SharedPersistenceFactory.Role.app.allowsSave)
        #expect(!SharedPersistenceFactory.Role.extensionProcess.allowsSave)
    }

    @Test("Grup kimliği beklenen değerde")
    func identifierIsTheExpectedGroup() {
        // The identifier also lives in three entitlement plists, and nothing in Swift can
        // see those. `Scripts/check-target-sources.py` compares all four, because a mismatch
        // produces no compiler error and no crash — just a container that silently is not
        // shared, which is the hardest failure in this project to notice.
        #expect(AppGroup.identifier == "group.com.zenithium.app")
    }

    @Test("Anlık görüntü ve depo aynı konteynerin altında")
    func snapshotAndStoreShareOneContainer() throws {
        // Both are resolved from `AppGroup.containerURL`, so either both are present or
        // neither is. On a machine without the entitlement they are both nil, and that is a
        // valid outcome for this test — what must never happen is one without the other.
        #expect((AppGroup.storeURL == nil) == (AppGroup.widgetSnapshotURL == nil))
    }
}
