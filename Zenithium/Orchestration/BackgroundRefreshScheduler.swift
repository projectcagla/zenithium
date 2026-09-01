//
//  BackgroundRefreshScheduler.swift
//  Zenithium
//
//  `BGAppRefreshTask` registration and scheduling. Spec §10, ASSUMPTION BG-1.
//
//  One task, rescheduled on every completion, earliest begin thirty minutes after the user's
//  usual wake time — which is when a post-wake recompute has data worth computing.
//

import Foundation
import BackgroundTasks

/// Carries a `BGAppRefreshTask` into the structured task that completes it.
///
/// ASSUMPTION BG-3: `BGTask` is not `Sendable`, and the two escape hatches normally used here
/// are both closed — §2.4 bans `DispatchQueue`, so the launch handler cannot be registered on
/// the main queue, and the handler must call `setTaskCompleted` after asynchronous work or the
/// system terminates the app. The box is the narrowest remaining option: it is created inside
/// the launch handler, handed to exactly one task, never stored, and never read twice.
/// `setTaskCompleted(success:)` is documented as callable from any thread.
private struct BackgroundTaskBox: @unchecked Sendable {
    let task: BGAppRefreshTask
}

@MainActor
final class BackgroundRefreshScheduler {

    private let coordinator: DailyRecalculationCoordinator
    private let store: any BiometricDayRepository
    private let calendarProvider: @Sendable () -> Calendar
    private let nowProvider: @Sendable () -> Date
    private let protectedData: ProtectedDataGuard
    private var isRegistered = false

    init(
        coordinator: DailyRecalculationCoordinator,
        store: any BiometricDayRepository,
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent },
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        protectedData: ProtectedDataGuard = ProtectedDataGuard()
    ) {
        self.coordinator = coordinator
        self.store = store
        self.calendarProvider = calendarProvider
        self.nowProvider = nowProvider
        self.protectedData = protectedData
    }

    /// The identifier that must also appear in `BGTaskSchedulerPermittedIdentifiers` (§8).
    static let taskIdentifier = EngineConstants.Orchestration.backgroundTaskIdentifier

    /// Registers the launch handler.
    ///
    /// Must run during launch, before the app finishes initialising, or `BGTaskScheduler`
    /// refuses the registration. Idempotent.
    func register() {
        guard !isRegistered else { return }
        isRegistered = true

        let coordinator = self.coordinator
        let nowProvider = self.nowProvider

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let box = BackgroundTaskBox(task: refreshTask)

            let work = Task {
                // Held strongly for the length of the task only: the registration itself
                // keeps `self` weakly, so the scheduler can still be torn down between wakes.
                guard let scheduler = self else {
                    box.task.setTaskCompleted(success: false)
                    return
                }

                // The wake lands thirty minutes after the usual wake time, which is when the
                // phone is most likely still locked on a nightstand — and HealthKit's store
                // is encrypted until it is unlocked. Running the pass anyway produced a
                // guaranteed failure, and reporting that failure taught the system to wake
                // us less often. Adım 3.
                if await scheduler.canReadProtectedData() {
                    let success = await Self.runPass(coordinator: coordinator, nowProvider: nowProvider)
                    box.task.setTaskCompleted(success: success)
                } else {
                    await scheduler.deferMorningPass {
                        _ = await Self.runPass(coordinator: coordinator, nowProvider: nowProvider)
                    }
                    // Reported as a success because nothing failed: the work is queued and
                    // will run at unlock. Reporting failure here would be the app telling the
                    // scheduler it cannot do its job, for a morning where it simply arrived
                    // before the user did.
                    box.task.setTaskCompleted(success: true)
                }

                // Chain the next request only after this one finishes, so there is never
                // more than one outstanding request for the same identifier.
                await scheduler.schedule()
            }

            refreshTask.expirationHandler = {
                // The system is reclaiming the task. Cancelling propagates into the
                // pipeline, which checks for cancellation between steps.
                work.cancel()
            }
        }
    }

    /// One recalculation pass plus its backfill. Reports whether it got through.
    ///
    /// `nonisolated static` for two reasons: the background handler must not capture `self`
    /// for the work itself, and a static member of a `@MainActor` class is main-actor
    /// isolated unless it says otherwise — which would drag the whole pass onto the main
    /// thread for no reason.
    private nonisolated static func runPass(
        coordinator: DailyRecalculationCoordinator,
        nowProvider: @Sendable () -> Date
    ) async -> Bool {
        do {
            _ = try await coordinator.recalculate(now: nowProvider())
            try await coordinator.backfillPendingDays(now: nowProvider())
            return true
        } catch let error as ZenithiumError where error == .healthDataProtected {
            // The device locked between the availability check and the query. Nothing is
            // wrong and a retry now cannot succeed, so this is not logged as a failure.
            ZenithiumLog.orchestration.notice("Background refresh met a locked device mid-pass")
            return false
        } catch is CancellationError {
            // The expiration handler fired and cancelled the pass. The system reclaiming its
            // budget is not the app failing, so it is not logged as one.
            return false
        } catch let error as ZenithiumError where error == .cancelled {
            return false
        } catch {
            ZenithiumLog.orchestration.error("Background refresh failed")
            return false
        }
    }

    /// Whether HealthKit's store can be read right now.
    ///
    /// A method on the scheduler rather than a reach through `protectedData` from the
    /// background handler: the guard is a non-`Sendable` class, so handing it across the
    /// isolation boundary is exactly what strict concurrency forbids. A `Bool` crosses fine.
    private func canReadProtectedData() -> Bool {
        protectedData.isProtectedDataAvailable
    }

    /// Queues the morning pass for the next unlock. Same isolation reasoning as above.
    private func deferMorningPass(_ work: @escaping @Sendable () async -> Void) {
        protectedData.enqueue(id: ProtectedDataJob.morningRecalculation, work)
    }

    /// Runs anything the guard is holding, if the device is unlocked.
    ///
    /// Called when the app comes to the foreground: the user is looking at the screen, so the
    /// device is unlocked by definition, and a job queued by a locked wake can run now even if
    /// the unlock notification was missed while the process was suspended.
    func drainDeferredWork() {
        protectedData.drainQueue()
    }

    /// Submits the next request. Safe to call repeatedly — an existing request for the same
    /// identifier is replaced rather than duplicated.
    func schedule() async {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = await nextBeginDate()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission is refused in the Simulator and when the user has turned background
            // refresh off. Neither is fatal: the app still refreshes on foreground.
            ZenithiumLog.orchestration.notice("Background refresh not scheduled")
        }
    }

    /// ASSUMPTION BG-1 — thirty minutes after the user's recent wake time, or 06:00 local
    /// when no wake time has been recorded yet.
    private func nextBeginDate() async -> Date {
        let calendar = calendarProvider()
        let now = nowProvider()
        let today = calendar.startOfDay(for: now)

        let records = (try? await store.recentDayRecords(limit: 7)) ?? []
        let recentWake = records.compactMap(\.wakeTime).first

        let hour: Int
        let minute: Int
        if let recentWake {
            let components = calendar.dateComponents([.hour, .minute], from: recentWake)
            hour = components.hour ?? EngineConstants.Orchestration.backgroundFallbackHour
            minute = components.minute ?? 0
        } else {
            hour = EngineConstants.Orchestration.backgroundFallbackHour
            minute = 0
        }

        let offset = EngineConstants.Orchestration.backgroundEarliestOffsetMinutes
            * TimeConversion.secondsPerMinute

        guard let todayAnchor = calendar.date(
            bySettingHour: hour, minute: minute, second: 0, of: today
        ) else {
            return now.addingTimeInterval(TimeConversion.secondsPerHour)
        }

        let candidate = todayAnchor.addingTimeInterval(offset)
        if candidate > now { return candidate }

        // Past today's window — aim at tomorrow's, by calendar arithmetic so a DST transition
        // does not shift it by an hour.
        guard let tomorrowAnchor = calendar.date(byAdding: .day, value: 1, to: todayAnchor) else {
            return now.addingTimeInterval(TimeConversion.secondsPerDay)
        }
        return tomorrowAnchor.addingTimeInterval(offset)
    }
}
