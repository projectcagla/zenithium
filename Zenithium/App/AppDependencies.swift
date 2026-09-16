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
import Observation
import WidgetKit

/// The object graph, built once at launch.
@MainActor
@Observable
final class AppDependencies {

    var presentationID = UUID()
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
    let preferences: PersonalPreferenceStore
    let notifications = LocalNotificationCoordinator()

    /// Listens for a session running on the watch and drives its Live Activity.
    /// Yol haritası v4, C10.
    #if canImport(ActivityKit) && canImport(WatchConnectivity)
    let liveSession = LiveSessionRelay()
    private let watchLogs: WatchLogCoordinator
    #endif

    private init(
        modelContainer: ModelContainer,
        store: ZenithiumStore,
        health: any HealthDataProviding,
        automaticallyBackfills: Bool = true
    ) {
        self.modelContainer = modelContainer
        self.store = store
        self.health = health
        let cache = DayRecordCache(upstream: store)
        self.dayRecords = cache
        let preferences = PersonalPreferenceStore(inMemory: !automaticallyBackfills)
        self.preferences = preferences
        let coordinator = DailyRecalculationCoordinator(health: health, store: store, automaticallyBackfills: automaticallyBackfills, preferences: preferences, invalidateRecords: { await cache.invalidate() })
        self.coordinator = coordinator
        let notifications = self.notifications
        self.archive = ArchiveService(store: store, vault: DocumentVault(), preferences: preferences,
            beforeRestore: { await coordinator.suspendForErasure() },
            afterRestore: {
                await cache.invalidate()
                await coordinator.resumeAfterErasure()
                do { try await notifications.apply(try await preferences.load()) }
                catch { ZenithiumLog.orchestration.error("Imported notification schedule failed: \(error.localizedDescription, privacy: .public)") }
            })
        #if canImport(ActivityKit) && canImport(WatchConnectivity)
        let watchLogs = WatchLogCoordinator(sessions: store, journal: store)
        self.watchLogs = watchLogs
        self.liveSession.logHandler = { message in
            try await watchLogs.receive(message)
            await cache.invalidate()
            _ = try await coordinator.recalculate(now: Date())
        }
        #endif
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
            health: MockHealthProvider(configuration: configuration),
            automaticallyBackfills: false
        )
    }

    /// Starts the background machinery. Called once, after the first frame.
    func start() async {
        guard (try? await store.profile().hasCompletedOnboarding) == true else { return }
        // Invalidation first: a recalculation that lands before this drain is running would
        // leave the cache holding the previous pass's numbers with nothing to correct it.
        invalidationTask?.cancel()
        let stream = await coordinator.results()
        invalidationTask = Task { [notifications, preferences] in
            for await result in stream {
                do {
                    let values = try await preferences.load()
                    try await notifications.checkNight(result.record, preferences: values, now: result.computedAt)
                } catch { ZenithiumLog.orchestration.error("Notification refresh failed: \(error.localizedDescription, privacy: .public)") }
            }
        }
        do { try await notifications.apply(try await preferences.load()) }
        catch { ZenithiumLog.orchestration.error("Notification schedule failed: \(error.localizedDescription, privacy: .public)") }
        // Started before the relay and the scheduler, because a session may already be
        // running on the wrist when the app is opened and its context is waiting.
        #if canImport(ActivityKit) && canImport(WatchConnectivity)
        await watchLogs.resume()
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
    func eraseAll() async throws {
        await stop()
        await coordinator.suspendForErasure()
        do {
        #if canImport(ActivityKit) && canImport(WatchConnectivity)
            let cutoff = Date()
            AppGroup.defaults?.set(cutoff, forKey: "watchEraseBefore")
            WatchSnapshotTransport.publish(.placeholder, eraseBefore: cutoff)
            try await watchLogs.clear()
            await liveSession.stopAndClear()
        #endif
            try await archive.eraseAll()
            await notifications.clearAll()
            try WidgetSnapshotStore.write(.placeholder)
            await dayRecords.invalidate()
            await coordinator.resumeAfterErasure()
            WidgetCenter.shared.reloadAllTimelines()
            presentationID = UUID()
        } catch {
            await coordinator.resumeAfterErasure()
            #if canImport(ActivityKit) && canImport(WatchConnectivity)
            await watchLogs.resume()
            #endif
            throw error
        }
    }

}
