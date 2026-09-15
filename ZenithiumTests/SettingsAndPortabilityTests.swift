import Foundation
import SwiftData
import Testing
@testable import Zenithium

@Suite("Settings and portable local data")
struct SettingsAndPortabilityTests {
    private let now = Date(timeIntervalSince1970: 1_780_300_800)

    @Test("Preferences survive a new store instance, and reset removes the saved file")
    func preferencesPersistAndReset() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "preferences.json")
        let store = PersonalPreferenceStore(url: url)
        var preferences = PersonalPreferences()
        preferences.wakeMinute = 375
        preferences.decision = .progressive
        preferences.morningReminder = true
        preferences.baselineStart = now
        try await store.save(preferences)
        #expect(try await PersonalPreferenceStore(url: url).load() == preferences)
        try await store.reset()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try await store.load() == PersonalPreferences())
    }

    @Test("Invalid preferences leave the previous valid values intact")
    func invalidPreferencesDoNotOverwrite() async throws {
        let store = PersonalPreferenceStore(inMemory: true)
        var invalid = PersonalPreferences()
        invalid.wakeMinute = 1440
        await #expect(throws: ZenithiumError.self) { try await store.save(invalid) }
        #expect(try await store.load().wakeMinute == 420)
        invalid.wakeMinute = 420
        invalid.baselineStart = Date(timeIntervalSince1970: .infinity)
        #expect(throws: ZenithiumError.self) { try invalid.validated() }
    }

    @Test("Reminder switches produce distinct plans and bedtime wraps midnight")
    func reminderPlansAndBedtime() {
        var preferences = PersonalPreferences()
        #expect(LocalNotificationCoordinator.plans(for: preferences).isEmpty)
        preferences.missingNightReminder = true
        #expect(LocalNotificationCoordinator.plans(for: preferences).isEmpty, "Missing data needs an observation, not a recurring claim")
        preferences.wakeMinute = 1435
        preferences.morningReminder = true
        let morning = LocalNotificationCoordinator.plans(for: preferences)
        #expect(morning.count == 1)
        #expect(morning.first?.hour == 0 && morning.first?.minute == 10)
        preferences.weeklyReminder = true
        #expect(LocalNotificationCoordinator.plans(for: preferences).count == 2)
        preferences.wakeMinute = 420
        #expect(preferences.bedtimeMinute(needHours: 8) == 1380)
        #expect(preferences.bedtimeMinute(needHours: .nan) == nil)
    }

    @Test("Baseline reset excludes earlier health history and keeps existing day records")
    func baselineResetAndCacheInvalidation() async throws {
        let store = try ZenithiumStore(modelContainer: ModelContainerFactory.makeInMemory())
        let preferences = PersonalPreferenceStore(inMemory: true)
        let cache = DayRecordCache(upstream: store)
        let coordinator = DailyRecalculationCoordinator(health: MockHealthProvider(configuration: .complete),
            store: store, calendarProvider: { TestCalendars.utc }, automaticallyBackfills: false,
            preferences: preferences, invalidateRecords: { await cache.invalidate() })
        #expect(try await cache.recentDayRecords(limit: 10).isEmpty)
        let first = try await coordinator.recalculate(now: now)
        #expect(first.recovery.availability.isScored)
        #expect(try await cache.recentDayRecords(limit: 10).count == 1)
        var values = PersonalPreferences()
        values.baselineStart = TestCalendars.utc.startOfDay(for: now)
        try await preferences.save(values)
        try await store.resetBaselines()
        let reset = try await coordinator.recalculate(now: now)
        #expect(!reset.recovery.availability.isScored)
        #expect(try await store.baselines()[.heartRateVariability]?.sampleCount ?? 0 <= 1)
        #expect(try await store.recentDayRecords(limit: 10).count == 1)
        await coordinator.suspendForErasure()
        await #expect(throws: ZenithiumError.self) { try await coordinator.recalculate(now: now) }
        await coordinator.resumeAfterErasure()
    }

    @Test("On-disk store reopens without losing data; erase removes the profile and all records")
    func diskStoreReopensAndErases() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "local.store")
        try await writeDiskFixture(at: url)
        let reopened = try ZenithiumStore(modelContainer: ModelContainerFactory.make(at: url, allowsSave: true))
        #expect(try await reopened.profile().hasCompletedOnboarding)
        #expect(try await reopened.bloodMarkers().count == 1)
        #expect(try await reopened.journalDays(from: .distantPast, through: .distantFuture).count == 1)
        try await reopened.eraseAll()
        #expect(try await reopened.profile() == .empty)
        #expect(try await reopened.bloodMarkers().isEmpty)
        #expect(try await reopened.journalDays(from: .distantPast, through: .distantFuture).isEmpty)
    }

    private func writeDiskFixture(at url: URL) async throws {
        let store = try ZenithiumStore(modelContainer: ModelContainerFactory.make(at: url, allowsSave: true))
        var profile = UserProfileWrite()
        profile.hasCompletedOnboarding = true
        try await store.updateProfile(profile)
        try await store.saveJournalDay(JournalDay(dayStart: now, behaviors: [.lateCaffeine], mood: .good, note: "Akşam kahvesi"))
        try await store.saveBloodMarker(id: UUID(), marker: .ferritin, value: 40, unitSymbol: "ng/mL",
            referenceRange: .unbounded, optimalRange: .unbounded, drawnAt: now, note: "")
    }

    @Test("Archive restores preferences and markers idempotently; invalid paths cannot alter the profile")
    func restoreRoundTripAndValidation() async throws {
        let source = try ZenithiumStore(modelContainer: ModelContainerFactory.makeInMemory())
        let preferences = PersonalPreferenceStore(inMemory: true)
        var values = PersonalPreferences()
        values.wakeMinute = 510
        try await preferences.save(values)
        try await source.saveBloodMarker(id: UUID(), marker: .ferritin, value: 40, unitSymbol: "ng/mL",
            referenceRange: .unbounded, optimalRange: .unbounded, drawnAt: now, note: "")
        let archive = try await ArchiveService(store: source, vault: DocumentVault(), preferences: preferences).archive(now: now)
        let target = try ZenithiumStore(modelContainer: ModelContainerFactory.makeInMemory())
        let restoredPreferences = PersonalPreferenceStore(inMemory: true)
        let service = ArchiveService(store: target, vault: DocumentVault(), preferences: restoredPreferences)
        try await service.restore(archive)
        try await service.restore(archive)
        #expect(try await target.bloodMarkers().count == 1)
        #expect(try await restoredPreferences.load() == values)
        var malformed = archive
        malformed.documentFiles = [.init(fileName: "../outside.pdf", contents: Data())]
        await #expect(throws: ArchiveFailure.self) { try await service.restore(malformed) }
        #expect(try await target.bloodMarkers().count == 1)
    }

    @Test("Decision preference changes the action while missing recovery stays unscored")
    func decisionPolicyIsFunctional() {
        let quality = DataQualityAssessment(grade: .excellent, wearHours: 20, nocturnalWearHours: 8,
            hasNocturnalHRV: true, hasNocturnalRHR: true, hasWristTemperature: true, hasSleepStages: true,
            confidenceFactor: 1, missingSensors: [], qualityIssues: [])
        func result(score: Double?, preference: DecisionPreference, lens: TrainingLens = .endurance) -> AthleticDecision {
            DecisionEngine.decide(input: DecisionInput(recoveryScore: score, recoveryBand: .green,
                sleepScore: 85, dataQuality: quality, calibration: CalibrationState(recordedDaysCount: 30),
                lens: lens, preference: preference, evaluatedAt: now)).value
        }
        if case .maintain = result(score: 72, preference: .cautious).action {} else { Issue.record("Cautious policy must cap a borderline green day") }
        if case .push = result(score: 72, preference: .progressive).action {} else { Issue.record("Progressive policy should preserve this green action") }
        #expect(result(score: nil, preference: .progressive).action == .calibrate)
        #expect(result(score: 90, preference: .progressive, lens: .strength).suggestedActivities != result(score: 90, preference: .progressive).suggestedActivities)
    }
}
