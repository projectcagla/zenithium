//
//  OnboardingViewModel.swift
//  Zenithium
//
//  Onboarding: disclaimer → permissions → profile. Spec §12 requires the disclaimer here, and
//  §5.6 requires denial to be a recoverable state rather than a dead end.
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingViewModel {

    /// Where the user is in the flow.
    enum Step: Int, Sendable, CaseIterable, Hashable, Identifiable {
        case welcome
        case disclaimer
        case permissions
        case profile
        case done

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: return "Zenithium"
            case .disclaimer: return SafetyCopy.disclaimerTitle
            case .permissions: return SafetyCopy.authorizationTitle
            case .profile: return "A couple of details"
            case .done: return "Hazırsın"
            }
        }
    }

    private(set) var step: Step = .welcome
    private(set) var authorization: HealthAuthorizationState = .notDetermined
    private(set) var isWorking = false
    private(set) var error: ZenithiumError?

    /// Profile fields collected during onboarding. Every one is optional — Zenithium works
    /// without them, using the documented fallbacks (HRMAX-1, API-2).
    var dateOfBirth: Date?
    var biologicalSex: BiologicalSexValue = .notSet
    var sleepNeedHours: Double = EngineConstants.Sleep.defaultBaselineNeedHours

    private let health: any HealthAuthorizing
    private let profileRepository: any ProfileRepository
    private let coordinator: any RecalculationDriving
    private let nowProvider: @Sendable () -> Date
    private let calendarProvider: @Sendable () -> Calendar

    init(
        health: any HealthAuthorizing,
        profileRepository: any ProfileRepository,
        coordinator: any RecalculationDriving,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        calendarProvider: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.health = health
        self.profileRepository = profileRepository
        self.coordinator = coordinator
        self.nowProvider = nowProvider
        self.calendarProvider = calendarProvider
    }

    func onAppear() async {
        authorization = await health.authorizationReport(now: nowProvider()).overall
        if let profile = try? await profileRepository.profile() {
            dateOfBirth = profile.dateOfBirth
            biologicalSex = profile.biologicalSex
            sleepNeedHours = profile.baselineSleepNeedHours
        }
    }

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Records the §12 acknowledgement and moves on. The timestamp is persisted so the
    /// disclaimer is never silently re-shown or silently skipped.
    func acknowledgeDisclaimer() async {
        var write = UserProfileWrite()
        write.disclaimerAcknowledgedAt = .some(nowProvider())
        _ = try? await profileRepository.updateProfile(write)
        advance()
    }

    /// Presents the system permission sheet.
    ///
    /// A denial advances the flow rather than blocking it: Zenithium works with whatever the
    /// user allows, and §5.6 requires a recoverable state, not a dead end.
    func requestPermissions() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await health.requestAuthorization()
        } catch let thrown as ZenithiumError {
            error = thrown
        } catch {
            self.error = .healthAuthorizationDenied
        }
        authorization = await health.authorizationReport(now: nowProvider()).overall
        advance()
    }

    /// Saves the collected profile, marks onboarding complete, and runs the first pass.
    func finish() async {
        isWorking = true
        error = nil
        defer { isWorking = false }

        var write = UserProfileWrite()
        write.dateOfBirth = .some(dateOfBirth)
        write.biologicalSex = biologicalSex
        write.baselineSleepNeedHours = sleepNeedHours
        write.hasCompletedOnboarding = true

        do {
            _ = try await profileRepository.updateProfile(write)
        } catch let thrown as ZenithiumError {
            error = thrown
            return
        } catch {
            self.error = .persistenceWriteFailed(detail: String(describing: error))
            return
        }

        // The first pass may legitimately produce nothing — a fresh install has no baseline.
        // That is the calibrating state, not a failure, so it must not block finishing.
        _ = try? await coordinator.recalculate(now: nowProvider())
        step = .done
    }

    /// Age implied by the entered date of birth, for the profile step's confirmation line.
    var impliedAge: Int? {
        UserCharacteristics(
            dateOfBirth: dateOfBirth,
            biologicalSex: biologicalSex,
            maxHeartRateOverride: nil
        ).age(at: nowProvider(), calendar: calendarProvider())
    }

    /// What Zenithium will use for `HRmax` given what has been entered (§5.3).
    var impliedMaxHeartRate: (value: Double, source: MaxHeartRateSource) {
        StrainEngine.resolveMaxHeartRate(override: nil, observed: nil, age: impliedAge)
    }
}
