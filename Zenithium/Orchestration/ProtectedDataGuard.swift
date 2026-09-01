//
//  ProtectedDataGuard.swift
//  Zenithium
//
//  Work that cannot run while the device is locked, and what to do about it.
//
//  ## The failure this removes
//
//  `BGAppRefreshTask` is scheduled for thirty minutes after the user's usual wake time
//  (ASSUMPTION BG-1). That is precisely when the phone is most likely to be face down on a
//  nightstand, locked, and unlocked-since-boot only if the user has already picked it up.
//  HealthKit's store is protected data: while the device is locked its database is encrypted
//  and every query fails with `HKError.errorDatabaseInaccessible`.
//
//  Before this type, that morning went like this: the task woke, the pipeline threw, the
//  handler logged a failure and reported `setTaskCompleted(success: false)`, and the day's
//  numbers simply did not exist until the user opened the app. The system also learns from
//  those reported failures, so a run of locked mornings makes the *next* wake less likely.
//  Nothing was broken and nothing was retryable — the work had arrived at the wrong moment.
//
//  ## What it does instead
//
//  Ask first, then either run or wait. When protected data is available the work runs
//  immediately and nothing else happens. When it is not, the work is queued and
//  `UIApplication.protectedDataDidBecomeAvailableNotification` runs it at the moment of
//  unlock — which, on a morning where the user picks the phone up at 06:45, is a recompute
//  that finishes before they have opened anything.
//
//  ## What it does not do, stated plainly
//
//  The queue lives in memory, in this process. If iOS suspends the app before the unlock
//  arrives, the queued work is lost — a suspended process receives no notifications. This is
//  a real limit and not one this type can lift: keeping a process alive to wait for an
//  unlock is not something an app gets to decide.
//
//  What it covers is the window where the app is alive: the background task's own execution
//  window, and any period the app is backgrounded but not yet suspended. The case it does
//  not cover is already covered elsewhere — the app recalculates on foreground, so a user
//  who opens Zenithium gets the same numbers, just later. The point of this type is that the
//  numbers are ready *before* they open it, whenever the process is still around to compute
//  them.
//
//  ## Why UIKit
//
//  This is the project's second `UIKit` import and, like the first, it is here because the
//  framework has no replacement for what is needed. `isProtectedDataAvailable` and
//  `protectedDataDidBecomeAvailableNotification` are the only APIs that report this state on
//  iOS; there is no SwiftUI, Foundation or HealthKit equivalent. The import is confined to
//  `SystemProtectedDataObserver` below, and the guard itself talks only to a protocol — so
//  the logic is testable on a machine with no UIKit at all.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Reports whether protected data is readable, and calls back when it becomes readable.
@MainActor
protocol ProtectedDataObserving: AnyObject {

    /// Whether files and databases under complete protection can be read right now.
    var isProtectedDataAvailable: Bool { get }

    /// Starts calling `onAvailable` each time the device is unlocked. Replaces any previous
    /// registration, so calling it twice does not deliver twice.
    func startObserving(onAvailable: @escaping @MainActor () -> Void)

    /// Stops observing. Idempotent.
    ///
    /// The only lifecycle hook: a `@MainActor` type cannot clean up in `deinit` under strict
    /// concurrency without reaching across isolation. Nothing here needs it to — the guard
    /// stops observing as soon as its queue empties, and a registration that somehow outlives
    /// its owner is inert anyway, because the block holds the guard weakly.
    func stopObserving()
}

/// The real observer, on `UIApplication` and `NotificationCenter`.
@MainActor
final class SystemProtectedDataObserver: ProtectedDataObserving {

    private var token: (any NSObjectProtocol)?

    init() {}

    var isProtectedDataAvailable: Bool {
        #if canImport(UIKit)
        return UIApplication.shared.isProtectedDataAvailable
        #else
        // No UIKit means no data protection to wait for — macOS previews and the test host.
        return true
        #endif
    }

    func startObserving(onAvailable: @escaping @MainActor () -> Void) {
        #if canImport(UIKit)
        stopObserving()
        token = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil,
            queue: .main
        ) { _ in
            // `queue: .main` guarantees the main thread, which is not the same as the main
            // actor as far as the compiler is concerned. `assumeIsolated` is the assertion
            // that they coincide here, and it traps rather than corrupting state if they
            // ever do not.
            MainActor.assumeIsolated { onAvailable() }
        }
        #endif
    }

    func stopObserving() {
        if let token {
            NotificationCenter.default.removeObserver(token)
            self.token = nil
        }
    }
}

/// Runs work now, or at the next unlock.
@MainActor
final class ProtectedDataGuard {

    /// What `enqueue` did with the work it was handed.
    enum Outcome: Sendable, Equatable {

        /// The work is queued for the next unlock.
        case queued

        /// The device was locked and work with the same identity was already queued. The
        /// newer closure replaced the older one; nothing was started.
        ///
        /// Reported rather than hidden because a queue that quietly grows one entry per
        /// locked wake would recompute the same morning several times over at unlock.
        case replacedQueuedWork
    }

    private let observer: any ProtectedDataObserving

    /// Queued work by identity. A dictionary rather than an array so a second wake for the
    /// same job replaces the first instead of stacking behind it.
    private var queued: [String: @Sendable () async -> Void] = [:]

    /// How many queued jobs have been drained. Counted so the suite can assert the drain
    /// happened without observing HealthKit.
    private(set) var drainedCount = 0

    init(observer: any ProtectedDataObserving = SystemProtectedDataObserver()) {
        self.observer = observer
    }

    /// Whether the device can read protected data right now.
    var isProtectedDataAvailable: Bool { observer.isProtectedDataAvailable }

    /// How many jobs are waiting for an unlock.
    var queuedCount: Int { queued.count }

    /// Queues `work` to run at the next unlock.
    ///
    /// Callers check `isProtectedDataAvailable` first and run the work themselves when it is
    /// true. That split exists because the background handler must *await* the work to report
    /// `setTaskCompleted(success:)` honestly, and a combined "run or queue" call would have
    /// to swallow that result.
    ///
    /// - Parameter id: identity for de-duplication. Two calls with the same `id` leave one
    ///   queued job, not two.
    @discardableResult
    func enqueue(id: String, _ work: @escaping @Sendable () async -> Void) -> Outcome {
        let wasQueued = queued[id] != nil
        queued[id] = work
        // Re-registered on every enqueue rather than only on the first. `startObserving`
        // replaces its own registration, so this cannot deliver twice, and registering
        // unconditionally means there is no "was it already observing?" state to keep
        // correct across a `drainQueue` that stopped it.
        observer.startObserving { [weak self] in
            self?.drainQueue()
        }
        ZenithiumLog.orchestration.notice(
            "Protected data unavailable; \(id, privacy: .public) deferred until unlock"
        )
        return wasQueued ? .replacedQueuedWork : .queued
    }

    /// Runs everything waiting, if protected data is readable.
    ///
    /// Called by the unlock notification, and callable directly by a foreground path that
    /// knows the device must be unlocked because the user is looking at it.
    func drainQueue() {
        guard observer.isProtectedDataAvailable else { return }
        guard !queued.isEmpty else {
            observer.stopObserving()
            return
        }
        // Materialized before the dictionary is emptied. `queued.values` is a view, and
        // reading it after `removeAll()` works only because copy-on-write happens to keep the
        // old storage alive — a correctness argument no reader should have to reconstruct.
        let jobs = Array(queued.values)
        queued.removeAll()
        drainedCount += jobs.count
        observer.stopObserving()
        for job in jobs {
            Task { await job() }
        }
        ZenithiumLog.orchestration.notice(
            "Protected data available; ran \(jobs.count, privacy: .public) deferred job(s)"
        )
    }
}

/// Identities for work the guard can hold, so a typo cannot silently create a second slot.
///
/// At file scope rather than nested inside `ProtectedDataGuard`: a type nested in a
/// `@MainActor` class carries that isolation, and these are read from the background task's
/// handler, which is not on the main actor.
enum ProtectedDataJob {

    /// The morning recalculation a `BGAppRefreshTask` wake asks for.
    static let morningRecalculation = "morning-recalculation"
}
