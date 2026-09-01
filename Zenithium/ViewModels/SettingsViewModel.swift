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
    }

    private(set) var state: ViewState<Content> = .loading
    private(set) var isSaving = false
    private(set) var saveError: ZenithiumError?

    private let repository: any ProfileRepository
    private let baselines: any BaselineRepository
    private let health: any HealthAuthorizing
    private let coordinator: any RecalculationDriving
    private let nowProvider: @Sendable () -> Date

    init(
        repository: any ProfileRepository,
        baselines: any BaselineRepository,
        health: any HealthAuthorizing,
        coordinator: any RecalculationDriving,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.baselines = baselines
        self.health = health
        self.coordinator = coordinator
        self.nowProvider = nowProvider
    }

    func onAppear() async {
        await load()
    }

    func load() async {
        do {
            let profile = try await repository.profile()
            let report = await health.authorizationReport(now: nowProvider())
            state = .loaded(
                Content(
                    profile: profile,
                    authorization: report.overall,
                    engineVersion: EngineConstants.engineVersion,
                    appGroupIdentifier: AppGroup.identifier
                )
            )
        } catch {
            if let mapped = ViewState<Content>.from(error) {
                state = mapped
            }
        }
    }

    func setSleepNeed(_ hours: Double) async {
        var write = UserProfileWrite()
        write.baselineSleepNeedHours = hours
        await apply(write, recalculating: true)
    }

    func setDayBoundary(_ boundary: DayBoundary) async {
        var write = UserProfileWrite()
        write.dayBoundary = boundary
        await apply(write, recalculating: true)
    }

    /// Merceği değiştirir.
    ///
    /// Yeniden hesaplama yok: mercek motoru değil, arayüzü değiştirir (ASSUMPTION LENS-1).
    func setTrainingLens(_ lens: TrainingLens) async {
        var write = UserProfileWrite()
        write.trainingLens = lens
        await apply(write, recalculating: false)
    }

    /// Choose the palette. Yol haritası v4, B6.
    ///
    /// No recalculation: this changes how a number is drawn, never what it is.
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

    /// Sets or clears the `HRmax` override (§5.3). Values outside the accepted range are
    /// refused rather than clamped, so the user sees why nothing changed.
    func setMaxHeartRateOverride(_ value: Double?) async {
        if let value, !UserProfile.maxHeartRateOverrideRange.contains(value) {
            saveError = .invalidEngineInput(
                reason: "Enter a maximum heart rate between \(Int(UserProfile.maxHeartRateOverrideRange.lowerBound)) and \(Int(UserProfile.maxHeartRateOverrideRange.upperBound)) bpm."
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
            try await baselines.resetBaselines()
            _ = try await coordinator.recalculate(now: nowProvider())
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }

    private func apply(_ write: UserProfileWrite, recalculating: Bool) async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            _ = try await repository.updateProfile(write)
            if recalculating {
                _ = try? await coordinator.recalculate(now: nowProvider())
            }
            await load()
        } catch let error as ZenithiumError {
            saveError = error
        } catch {
            saveError = .persistenceWriteFailed(detail: String(describing: error))
        }
    }
}
