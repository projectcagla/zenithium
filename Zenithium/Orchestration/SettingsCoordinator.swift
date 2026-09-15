import Foundation

struct SettingsSnapshot: Sendable {
    let profile: UserProfileSnapshot
    let authorization: HealthAuthorizationReport
    let baselineNights: Int
    let preferences: PersonalPreferences
}

actor SettingsCoordinator {
    private let profiles: any ProfileRepository
    private let baselines: any BaselineRepository
    private let health: any HealthAuthorizing
    private let recalculation: any RecalculationDriving
    private let preferences: any PersonalPreferenceRepository
    let notifications: LocalNotificationCoordinator

    init(profiles: any ProfileRepository, baselines: any BaselineRepository, health: any HealthAuthorizing,
         recalculation: any RecalculationDriving, preferences: any PersonalPreferenceRepository,
         notifications: LocalNotificationCoordinator) {
        self.profiles = profiles
        self.baselines = baselines
        self.health = health
        self.recalculation = recalculation
        self.preferences = preferences
        self.notifications = notifications
    }

    func load(now: Date) async throws -> SettingsSnapshot {
        let profile = try await profiles.profile()
        let authorization = await health.authorizationReport(now: now)
        let baseline = try await baselines.baselines()
        return SettingsSnapshot(profile: profile, authorization: authorization,
            baselineNights: baseline[.heartRateVariability]?.sampleCount ?? 0,
            preferences: try await preferences.load())
    }

    func updateProfile(_ write: UserProfileWrite, now: Date) async throws {
        _ = try await profiles.updateProfile(write)
        _ = try await recalculation.recalculate(now: now)
    }

    func updatePreferences(_ value: PersonalPreferences, requestNotifications: Bool, now: Date) async throws {
        _ = try value.validated()
        let previous = try await preferences.load()
        try await notifications.apply(value, requestingPermission: requestNotifications)
        do { try await preferences.save(value) }
        catch {
            do { try await notifications.apply(previous) }
            catch { ZenithiumLog.orchestration.error("Notification rollback failed: \(error.localizedDescription, privacy: .public)") }
            throw error
        }
        _ = try await recalculation.recalculate(now: now)
    }

    func requestHealth(now: Date) async throws {
        try await health.requestAuthorization()
        _ = try await recalculation.recalculate(now: now)
    }

    func resetBaseline(now: Date) async throws {
        var value = try await preferences.load()
        value.baselineStart = Calendar.autoupdatingCurrent.startOfDay(for: now)
        try await preferences.save(value)
        try await baselines.resetBaselines()
        _ = try await recalculation.recalculate(now: now)
    }
}
