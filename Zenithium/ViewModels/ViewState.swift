//
//  ViewState.swift
//  Zenithium
//
//  The explicit state every screen carries. Spec §10: each view model has a `ViewState` enum
//  with `.calibrating(progress:)`, `.needsAuthorization`, `.noData(reason:)`, `.loaded(...)`
//  and `.failed(_)`; §15 rule 9: every missing-data path has a defined state, never a crash
//  and never a zero rendered as if it were a measurement.
//
//  ASSUMPTION VM-1: a `.loading` case is added to the five the specification names. A view
//  model has to be in some state before its first read completes, and the alternative —
//  starting in `.noData` — would flash "no data" on every launch.
//

import Foundation

/// Why a screen has nothing to show. Distinct from a failure: nothing went wrong.
enum NoDataReason: Sendable, Equatable, Hashable {

    /// The watch was not worn overnight (§5.6).
    case noOvernightData

    /// No intraday heart rate for the day yet — normal early in the morning.
    case noHeartRateYet

    /// A required overnight metric was missing, so recovery is suppressed (§4.3).
    case recoveryUnavailable(RecoveryUnavailableReason)

    /// The night was rejected as implausible (§5.6).
    case sleepImplausible

    /// Not enough history for a trend.
    case notEnoughHistory(daysAvailable: Int, daysRequired: Int)

    /// The user has not logged anything of this kind yet.
    case nothingLogged(what: String)

    var title: String {
        switch self {
        case .noOvernightData:
            return SafetyCopy.noOvernightDataTitle
        case .noHeartRateYet:
            return "Henüz kalp verisi yok"
        case .recoveryUnavailable(let reason):
            return reason.displayName
        case .sleepImplausible:
            return "Dün gece güvenilir görünmüyor"
        case .notEnoughHistory:
            return "Yeterli geçmiş yok"
        case .nothingLogged(let what):
            return "Henüz \(what) yok"
        }
    }

    /// Training-directive explanation only — §12 forbids health-status language anywhere.
    var message: String {
        switch self {
        case .noOvernightData:
            return SafetyCopy.noOvernightDataBody
        case .noHeartRateYet:
            return "Zenithium builds today's strain from your watch's heart rate. It'll fill in as the day goes on."
        case .recoveryUnavailable(let reason):
            return reason.explanation
        case .sleepImplausible:
            return "2 saatten kısa ya da 14 saatten uzun geceleri atlıyorum."
        case .notEnoughHistory(let available, let required):
            let remaining = max(0, required - available)
            return "\(remaining) more \(remaining == 1 ? "day" : "days") of data and this chart fills in."
        case .nothingLogged:
            return "İlk kaydını ekle; burada, zaman içinde nasıl değiştiğiyle birlikte görünecek."
        }
    }
}

/// The state of one screen.
enum ViewState<Value: Sendable>: Sendable {

    /// Before the first read completes (ASSUMPTION VM-1).
    case loading

    /// Fewer than five valid baseline days — no score, progress shown as `n/14` (§4.2.4).
    case calibrating(progress: Double, daysCollected: Int, daysRequired: Int)

    /// Health access has not been granted (§5.6 — recoverable, with a Settings deep link).
    case needsAuthorization(HealthAuthorizationState)

    /// Nothing to show, and nothing went wrong.
    case noData(reason: NoDataReason)

    /// Loaded.
    case loaded(Value)

    /// Something failed. Carries the typed error so the view can offer the right affordance.
    case failed(ZenithiumError)

    /// The loaded value, when there is one.
    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// Whether the view should offer a retry button.
    var isRetryable: Bool {
        switch self {
        case .failed(let error): return error.isRetryable
        case .loading, .calibrating, .needsAuthorization, .noData, .loaded: return false
        }
    }

    /// Maps the loaded value, leaving every other case alone.
    func map<Other: Sendable>(_ transform: (Value) -> Other) -> ViewState<Other> {
        switch self {
        case .loading: return .loading
        case .calibrating(let progress, let collected, let required):
            return .calibrating(progress: progress, daysCollected: collected, daysRequired: required)
        case .needsAuthorization(let state): return .needsAuthorization(state)
        case .noData(let reason): return .noData(reason: reason)
        case .loaded(let value): return .loaded(transform(value))
        case .failed(let error): return .failed(error)
        }
    }
}

extension ViewState: Equatable where Value: Equatable {}

extension ViewState {

    /// Classifies a thrown error into the state that describes it.
    ///
    /// Authorization failures become `.needsAuthorization` rather than `.failed`, because
    /// they are a permission the user can grant, not a fault (§5.6). Cancellation is not a
    /// failure at all and leaves the previous state in place — the caller checks for `nil`.
    static func from(_ error: any Error) -> ViewState<Value>? {
        guard let zenithiumError = error as? ZenithiumError else {
            return .failed(.persistenceReadFailed(detail: String(describing: error)))
        }
        switch zenithiumError {
        case .cancelled:
            return nil
        case .healthAuthorizationDenied:
            return .needsAuthorization(.denied)
        case .healthAuthorizationNotDetermined:
            return .needsAuthorization(.notDetermined)
        case .healthDataUnavailable:
            return .needsAuthorization(.unavailable)
        default:
            return .failed(zenithiumError)
        }
    }
}

// `HealthAuthorizing` is declared in `Health/HealthDataProviding.swift`, which
// `HealthDataProviding` inherits — so any provider is already usable as a permission gate
// without a cast.

/// The subset of the coordinator a view model needs.
protocol RecalculationDriving: Sendable {
    @discardableResult
    func recalculate(now: Date) async throws -> RecalculationResult
    func results() async -> AsyncStream<RecalculationResult>
}

extension DailyRecalculationCoordinator: RecalculationDriving {}
