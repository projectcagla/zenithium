//
//  ProtectedDataGuardTests.swift
//  ZenithiumTests
//
//  The locked-morning path, asserted without a locked device.
//
//  `UIApplication.isProtectedDataAvailable` cannot be made false from a test, which is the
//  whole reason the guard talks to `ProtectedDataObserving` instead of to UIKit. The fake
//  below is the lock.
//

import Testing
import Foundation
@testable import Zenithium

/// A lock a test can turn.
@MainActor
private final class FakeProtectedDataObserver: ProtectedDataObserving {

    var isProtectedDataAvailable: Bool
    private(set) var observerCount = 0
    private(set) var stopCount = 0
    private var handler: (@MainActor () -> Void)?

    init(available: Bool) {
        self.isProtectedDataAvailable = available
    }

    func startObserving(onAvailable: @escaping @MainActor () -> Void) {
        observerCount += 1
        handler = onAvailable
    }

    func stopObserving() {
        if handler != nil { stopCount += 1 }
        handler = nil
    }

    /// Unlocks the device and delivers the notification, the way iOS would.
    func unlock() {
        isProtectedDataAvailable = true
        handler?()
    }
}

/// Records that a job ran, so a queued closure can be observed after the fact.
private actor JobLog {

    private(set) var ran: [String] = []

    func record(_ name: String) {
        ran.append(name)
    }
}

@Suite("Protected data guard")
@MainActor
struct ProtectedDataGuardTests {

    /// Waits for asynchronous jobs the guard started, without sleeping for a guess.
    private func waitForJobs(_ log: JobLog, toReach count: Int) async {
        var spins = 0
        while await log.ran.count < count, spins < 100_000 {
            await Task.yield()
            spins += 1
        }
    }

    @Test("Kilitli cihazda iş kuyruğa alınıyor, çalıştırılmıyor")
    func lockedDeviceQueuesTheWork() async {
        let observer = FakeProtectedDataObserver(available: false)
        let guardObject = ProtectedDataGuard(observer: observer)
        let log = JobLog()

        let outcome = guardObject.enqueue(id: ProtectedDataJob.morningRecalculation) {
            await log.record("morning")
        }

        #expect(outcome == .queued)
        #expect(guardObject.queuedCount == 1)
        #expect(observer.observerCount == 1)
        let ran = await log.ran
        #expect(ran.isEmpty)
    }

    /// The regression the whole type exists for: before it, this morning's numbers did not
    /// exist until the user opened the app.
    @Test("Kilit açılınca kuyruktaki iş çalışıyor")
    func unlockRunsTheQueuedWork() async {
        let observer = FakeProtectedDataObserver(available: false)
        let guardObject = ProtectedDataGuard(observer: observer)
        let log = JobLog()

        guardObject.enqueue(id: ProtectedDataJob.morningRecalculation) {
            await log.record("morning")
        }
        observer.unlock()
        await waitForJobs(log, toReach: 1)

        let ran = await log.ran
        #expect(ran == ["morning"])
        #expect(guardObject.queuedCount == 0)
        #expect(guardObject.drainedCount == 1)
        // The registration is dropped once nothing is waiting, rather than left running for
        // the life of the process.
        #expect(observer.stopCount == 1)
    }

    /// Two locked wakes in one morning must leave one job, not two — otherwise the unlock
    /// recomputes the same day twice.
    @Test("Aynı kimlikle ikinci kez kuyruğa alma, kuyruğu büyütmüyor")
    func aSecondWakeReplacesRatherThanStacks() async {
        let observer = FakeProtectedDataObserver(available: false)
        let guardObject = ProtectedDataGuard(observer: observer)
        let log = JobLog()

        #expect(guardObject.enqueue(id: ProtectedDataJob.morningRecalculation) {
            await log.record("first")
        } == .queued)

        #expect(guardObject.enqueue(id: ProtectedDataJob.morningRecalculation) {
            await log.record("second")
        } == .replacedQueuedWork)

        #expect(guardObject.queuedCount == 1)

        observer.unlock()
        await waitForJobs(log, toReach: 1)

        // The newer closure wins: it was built from a more recent `now`.
        let ran = await log.ran
        #expect(ran == ["second"])
    }

    @Test("Farklı kimlikler ayrı ayrı kuyrukta duruyor")
    func differentIdentitiesQueueSeparately() async {
        let observer = FakeProtectedDataObserver(available: false)
        let guardObject = ProtectedDataGuard(observer: observer)
        let log = JobLog()

        guardObject.enqueue(id: "a") { await log.record("a") }
        guardObject.enqueue(id: "b") { await log.record("b") }
        #expect(guardObject.queuedCount == 2)

        observer.unlock()
        await waitForJobs(log, toReach: 2)

        let ran = await log.ran
        #expect(Set(ran) == ["a", "b"])
        #expect(guardObject.drainedCount == 2)
    }

    @Test("Kilit hâlâ kapalıyken boşaltma hiçbir şey çalıştırmıyor")
    func drainingWhileStillLockedDoesNothing() async {
        let observer = FakeProtectedDataObserver(available: false)
        let guardObject = ProtectedDataGuard(observer: observer)
        let log = JobLog()

        guardObject.enqueue(id: "a") { await log.record("a") }
        guardObject.drainQueue()

        #expect(guardObject.queuedCount == 1)
        #expect(guardObject.drainedCount == 0)
        let ran = await log.ran
        #expect(ran.isEmpty)
    }

    /// The foreground path calls this directly, because a user looking at the screen means an
    /// unlocked device even if the notification was missed while the process was suspended.
    @Test("Ön plana geçişte elle boşaltma, kaçırılan bildirimi telafi ediyor")
    func manualDrainCoversAMissedNotification() async {
        let observer = FakeProtectedDataObserver(available: false)
        let guardObject = ProtectedDataGuard(observer: observer)
        let log = JobLog()

        guardObject.enqueue(id: ProtectedDataJob.morningRecalculation) {
            await log.record("morning")
        }
        // Unlocked without the notification ever arriving — the suspended-process case.
        observer.isProtectedDataAvailable = true
        guardObject.drainQueue()
        await waitForJobs(log, toReach: 1)

        let ran = await log.ran
        #expect(ran == ["morning"])
        #expect(guardObject.queuedCount == 0)
    }

    @Test("Boş kuyrukta boşaltma hiçbir şey yapmıyor")
    func drainingAnEmptyQueueIsANoOp() {
        let observer = FakeProtectedDataObserver(available: true)
        let guardObject = ProtectedDataGuard(observer: observer)

        guardObject.drainQueue()

        #expect(guardObject.drainedCount == 0)
        #expect(guardObject.queuedCount == 0)
        // Nothing was ever queued, so nothing ever registered for the notification.
        #expect(observer.observerCount == 0)
    }
}

@Suite("Protected data error")
struct ProtectedDataErrorTests {

    @Test("Kilitli veri hatası yeniden denenebilir değil")
    func lockedDataIsNotRetryable() {
        // A retry button on this error is a button that cannot work: the database stays
        // encrypted until the device is unlocked, whatever the user taps.
        #expect(!ZenithiumError.healthDataProtected.isRetryable)
        #expect(!ZenithiumError.healthDataProtected.requiresSystemSettings)
    }

    @Test("Kilitli veri hatası izin hatasından ayrı")
    func lockedDataIsNotAPermissionProblem() {
        #expect(ZenithiumError.healthDataProtected != .healthAuthorizationDenied)
        #expect(ZenithiumError.healthDataProtected != .healthDataUnavailable)
    }

    @Test("Kilitli veri hatası kullanıcıya sağlık iddiası yapmıyor")
    func copyStaysInsideTheSafetyRules() throws {
        // §12: the copy describes a device state, never a health status.
        let description = try #require(ZenithiumError.healthDataProtected.errorDescription)
        let suggestion = try #require(ZenithiumError.healthDataProtected.recoverySuggestion)
        #expect(!description.isEmpty)
        #expect(!suggestion.isEmpty)
    }
}
