//
//  SettingsViewModel.swift
//  Zenithium
//
//  The Settings screen. Spec §10, §12 (disclaimer and privacy surfaces are reachable here).
//

import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {

    struct Content: Sendable, Equatable {
        let profile: UserProfileSnapshot
        let authorization: HealthAuthorizationState
        let engineVersion: Int
        let appGroupIdentifier: String
        let baselineNights: Int
        let preferences: PersonalPreferences
        let healthReport: HealthAuthorizationReport
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isSaving = false
    private(set) var saveError: ZenithiumError?

    private let settings: SettingsCoordinator
    private let notifications: LocalNotificationCoordinator
    private(set) var integrations = IntegrationStatus()
    private(set) var notificationAuthorization = "Kontrol ediliyor"
    private let nowProvider: @Sendable () -> Date

    init(
        repository: any ProfileRepository,
        baselines: any BaselineRepository,
        health: any HealthAuthorizing,
        coordinator: any RecalculationDriving,
        preferences: any PersonalPreferenceRepository = PersonalPreferenceStore(inMemory: true),
        notifications: LocalNotificationCoordinator = LocalNotificationCoordinator(),
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.notifications = notifications
        self.settings = SettingsCoordinator(profiles: repository, baselines: baselines, health: health,
            recalculation: coordinator, preferences: preferences, notifications: notifications)
        self.nowProvider = nowProvider
    }

    func onAppear() async {
        await load()
    }

    func load() async {
        do {
            let value = try await settings.load(now: nowProvider())
            state = .loaded(Content(profile: value.profile, authorization: value.authorization.overall,
                engineVersion: EngineConstants.engineVersion, appGroupIdentifier: AppGroup.identifier,
                baselineNights: value.baselineNights, preferences: value.preferences, healthReport: value.authorization))
            notificationAuthorization = await notifications.authorizationLabel()
            integrations = await IntegrationStatusCoordinator.read()
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    func setSleepNeed(_ hours: Double) async {
        guard hours.isFinite, (5...12).contains(hours) else {
            saveError = .invalidEngineInput(reason: "Uyku hedefi 5–12 saat arasında olmalı.")
            return
        }
        var write = UserProfileWrite()
        write.baselineSleepNeedHours = hours
        await apply(write, recalculating: true)
    }

    func setDayBoundary(_ boundary: DayBoundary) async {
        var write = UserProfileWrite()
        write.dayBoundary = boundary
        await apply(write, recalculating: true)
    }

    /// Updates activity suggestions, leaving physiological measurements unchanged.
    func setTrainingLens(_ lens: TrainingLens) async {
        var write = UserProfileWrite()
        write.trainingLens = lens
        await apply(write, recalculating: false)
    }

    /// Choose the palette and publish the updated profile to the visible screens.
    func setAppearance(_ appearance: AppearancePreference) async {
        var write = UserProfileWrite()
        write.appearance = appearance
        await apply(write, recalculating: false)
    }

    /// Turn cycle awareness on or off (Faz 12).
    ///
    /// Recalculates, because the phase changes which baseline today is compared against —
    /// unlike the unit preference below, which changes only how a number is spelled.
    func setTracksMenstrualCycle(_ tracks: Bool) async {
        var write = UserProfileWrite()
        write.tracksMenstrualCycle = tracks
        await apply(write, recalculating: true)
    }

    func setUnitPreference(_ preference: UnitPreference) async {
        var write = UserProfileWrite()
        write.unitPreference = preference
        // Display only — nothing to recompute (§2.8).
        await apply(write, recalculating: false)
    }

    func setDateOfBirth(_ date: Date?) async {
        var write = UserProfileWrite()
        write.dateOfBirth = .some(date)
        await apply(write, recalculating: true)
    }

    func setBiologicalSex(_ sex: BiologicalSexValue) async {
        var write = UserProfileWrite()
        write.biologicalSex = sex
        await apply(write, recalculating: true)
    }

    func setMaxHeartRateText(_ text: String) async {
        if text.isEmpty { await setMaxHeartRateOverride(nil); return }
        guard let value = Double(text), value.isFinite else {
            saveError = .invalidEngineInput(reason: "Maksimum nabzı sayı olarak gir.")
            return
        }
        await setMaxHeartRateOverride(value)
    }

    /// Sets or clears the `HRmax` override (§5.3). Values outside the accepted range are
    /// refused rather than clamped, so the user sees why nothing changed.
    func setMaxHeartRateOverride(_ value: Double?) async {
        if let value, !UserProfile.maxHeartRateOverrideRange.contains(value) {
            saveError = .invalidEngineInput(
                reason: "Maksimum nabız \(Int(UserProfile.maxHeartRateOverrideRange.lowerBound))–\(Int(UserProfile.maxHeartRateOverrideRange.upperBound)) atım/dk arasında olmalı."
            )
            return
        }
        var write = UserProfileWrite()
        write.maxHeartRateOverride = .some(value)
        await apply(write, recalculating: true)
    }

    /// Clears every baseline and recomputes. Offered for a watch change or a long gap, where
    /// the old baseline describes a different situation than the current one.
    func rebuildBaselines() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await settings.resetBaseline(now: nowProvider())
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }

    private func apply(_ write: UserProfileWrite, recalculating: Bool) async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await settings.updateProfile(write, now: nowProvider())
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }
    func setPreferences(_ update: (inout PersonalPreferences) -> Void, requestNotifications: Bool = false) async {
        guard !isSaving, var preferences = state.value?.preferences else { return }
        update(&preferences)
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await settings.updatePreferences(preferences, requestNotifications: requestNotifications, now: nowProvider())
            await load()
        } catch {
            saveError = .persistenceWriteFailed(detail: error.localizedDescription)
            await load()
        }
    }

    func requestHealth() async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do { try await settings.requestHealth(now: nowProvider()); await load() }
        catch { saveError = .persistenceWriteFailed(detail: error.localizedDescription) }
    }

}
