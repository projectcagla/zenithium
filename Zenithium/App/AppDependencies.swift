//
//  AppDependencies.swift
//  Zenithium
//
//  The composition root. Spec §6 — everything below this file is wired through protocols, so
//  no type constructs its own collaborators and every screen is previewable and testable
//  against `MockHealthProvider` and an in-memory store.
//

import Foundation
import SwiftData

/// The object graph, built once at launch.
@MainActor
final class AppDependencies {

    let modelContainer: ModelContainer
    let store: ZenithiumStore
    let health: any HealthDataProviding
    let coordinator: DailyRecalculationCoordinator
    let relay: HealthObservationRelay
    let scheduler: BackgroundRefreshScheduler

    /// What the screens read day records through.
    ///
    /// One instance for the whole app, so a window fetched for one screen is already in
    /// hand for the next. Invalidated from `start()` on every recalculation pass, which is
    /// the only thing that rewrites a day record. Yol haritası v4, A4 and A5.
    let dayRecords: DayRecordCache

    /// Drains the recalculation stream to keep `dayRecords` honest.
    private var invalidationTask: Task<Void, Never>?

    /// Whole-store export and import. Yol haritası v4, C9.
    let archive: ArchiveService

    /// Listens for a session running on the watch and drives its Live Activity.
    /// Yol haritası v4, C10.
    #if canImport(ActivityKit) && canImport(WatchConnectivity)
    let liveSession = LiveSessionRelay()
    #endif

    private init(
        modelContainer: ModelContainer,
        store: ZenithiumStore,
        health: any HealthDataProviding
    ) {
        self.modelContainer = modelContainer
        self.store = store
        self.health = health
        self.dayRecords = DayRecordCache(upstream: store)
        self.archive = ArchiveService(store: store, vault: DocumentVault())

        let coordinator = DailyRecalculationCoordinator(health: health, store: store)
        self.coordinator = coordinator
        self.relay = HealthObservationRelay(health: health, coordinator: coordinator)
        self.scheduler = BackgroundRefreshScheduler(coordinator: coordinator, store: store)
    }

    /// The live graph: the shared App Group store and real HealthKit.
    static func live() throws -> AppDependencies {
        if ProcessInfo.processInfo.arguments.contains("-mockData") {
            return try preview(configuration: .complete)
        }
        let container = try SharedPersistenceFactory.makeAppContainer()
        return AppDependencies(
            modelContainer: container,
            store: ZenithiumStore(modelContainer: container),
            health: HealthKitService()
        )
    }

    /// An in-memory graph over the seeded mock, for previews and tests (§11).
    static func preview(
        configuration: MockHealthProvider.Configuration = .default
    ) throws -> AppDependencies {
        let container = try ModelContainerFactory.makeInMemory()
        return AppDependencies(
            modelContainer: container,
            store: ZenithiumStore(modelContainer: container),
            health: MockHealthProvider(configuration: configuration)
        )
    }

    /// Starts the background machinery. Called once, after the first frame.
    func start() async {
        // Invalidation first: a recalculation that lands before this drain is running would
        // leave the cache holding the previous pass's numbers with nothing to correct it.
        invalidationTask?.cancel()
        invalidationTask = Task { [coordinator, dayRecords] in
            for await _ in await coordinator.results() {
                await dayRecords.invalidate()
            }
        }
        // Started before the relay and the scheduler, because a session may already be
        // running on the wrist when the app is opened and its context is waiting.
        #if canImport(ActivityKit) && canImport(WatchConnectivity)
        liveSession.start()
        #endif

        await relay.start()
        await scheduler.schedule()
    }

    /// Stops observing. Called when the app is being torn down in tests.
    func stop() async {
        invalidationTask?.cancel()
        invalidationTask = nil
        await relay.stop()
    }
}
