//
//  HealthObservationRelay.swift
//  Zenithium
//
//  Turns the HealthKit change stream into recalculations. Spec §10.
//
//  ASSUMPTION BG-2: events are coalesced over a 30-second window before the pipeline runs.
//  HealthKit can fire an observer many times during a single watch sync, and without a
//  debounce a morning sync would run the whole pipeline a dozen times in a few seconds.
//

import Foundation

actor HealthObservationRelay {

    private let health: any HealthDataProviding
    private let coordinator: DailyRecalculationCoordinator
    private let debounce: TimeInterval
    private let nowProvider: @Sendable () -> Date

    private var consumeTask: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?
    private var pendingEvent: HealthChangeEvent?

    init(
        health: any HealthDataProviding,
        coordinator: DailyRecalculationCoordinator,
        debounce: TimeInterval = EngineConstants.Orchestration.observerDebounceSeconds,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.health = health
        self.coordinator = coordinator
        self.debounce = debounce
        self.nowProvider = nowProvider
    }

    /// Starts observing. Idempotent — a second call is a no-op rather than a second consumer.
    ///
    /// The slot is claimed before the first suspension, and that ordering is the whole point.
    /// `consumeTask` used to be assigned only after `enableBackgroundDelivery()` and
    /// `observationStream()` had both been awaited — an actor releases its isolation across
    /// an `await`, so two concurrent starts both passed the `nil` guard, both opened a
    /// stream, and the second assignment orphaned the first consumer. `stop()` cancels the
    /// task it holds, so the orphan kept relaying events after the app had asked for the
    /// observer to be torn down.
    func start() async {
        guard consumeTask == nil else { return }
        consumeTask = Task { [weak self] in
            guard let self else { return }
            await self.consume()
        }
    }

    /// Enables delivery, opens the stream, and coalesces events until the task is cancelled.
    private func consume() async {
        do {
            try await health.enableBackgroundDelivery()
        } catch {
            // Background delivery being refused is not fatal: foreground refreshes still work,
            // so the app degrades to pull-driven rather than failing to launch.
            ZenithiumLog.orchestration.error("Background delivery unavailable")
        }
        // A `stop()` that lands while delivery is still being enabled must not go on to open
        // a stream nobody is going to close.
        guard !Task.isCancelled else { return }
        let stream = await health.observationStream()
        for await event in stream {
            guard !Task.isCancelled else { return }
            enqueue(event)
        }
    }

    /// Stops observing and cancels any pending recalculation.
    func stop() async {
        consumeTask?.cancel()
        consumeTask = nil
        pendingTask?.cancel()
        pendingTask = nil
        pendingEvent = nil
        await health.stopObserving()
    }

    /// Coalesces an event into the pending window.
    private func enqueue(_ event: HealthChangeEvent) {
        guard event.shouldTriggerRecalculation else { return }

        pendingEvent = pendingEvent.map { $0.merged(with: event) } ?? event

        // A timer already running covers this event too — merging above is what makes that
        // true, so restarting the timer would only delay work that is already scheduled.
        guard pendingTask == nil else { return }

        let interval = debounce
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Runs one recalculation for everything coalesced so far.
    private func flush() async {
        pendingTask = nil
        guard let event = pendingEvent else { return }
        pendingEvent = nil

        ZenithiumLog.orchestration.debug(
            "Recalculating after \(event.kinds.count, privacy: .public) changed categories, deletions: \(event.includesDeletions, privacy: .public)"
        )
        do {
            _ = try await coordinator.recalculate(now: nowProvider())
        } catch let error as ZenithiumError where error == .cancelled {
            return
        } catch {
            ZenithiumLog.orchestration.error("Observer-driven recalculation failed")
        }
    }
}
