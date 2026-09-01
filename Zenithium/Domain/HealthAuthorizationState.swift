//
//  HealthAuthorizationState.swift
//  Zenithium
//
//  Authorization as the UI needs to reason about it. Spec §5.6 (HealthKit denied must be a
//  recoverable full-screen state with a deep link to Settings, never a crash or a hang).
//

import Foundation

/// Read authorization for one category, or for the app as a whole.
enum HealthAuthorizationState: String, Sendable, Codable, CaseIterable, Hashable {

    /// HealthKit is not present on this device.
    case unavailable

    /// The user has not been asked yet.
    case notDetermined

    /// The user has been asked and declined, or has since revoked access.
    case denied

    /// Read access has been granted.
    case authorized

    /// Whether Zenithium can attempt to read data in this state.
    var permitsReads: Bool {
        self == .authorized
    }

    /// Whether the UI should present the permission request rather than the Settings deep link.
    var shouldPrompt: Bool {
        self == .notDetermined
    }
}

/// The full picture: an overall verdict plus per-category detail, so the UI can say exactly
/// which categories are missing instead of showing an all-or-nothing gate.
struct HealthAuthorizationReport: Sendable, Equatable, Hashable {

    /// The verdict the gate uses.
    let overall: HealthAuthorizationState

    /// Per-category detail.
    let byKind: [HealthDataKind: HealthAuthorizationState]

    /// When the report was taken.
    let checkedAt: Date

    init(
        overall: HealthAuthorizationState,
        byKind: [HealthDataKind: HealthAuthorizationState],
        checkedAt: Date
    ) {
        self.overall = overall
        self.byKind = byKind
        self.checkedAt = checkedAt
    }

    static func unavailable(at date: Date) -> HealthAuthorizationReport {
        HealthAuthorizationReport(overall: .unavailable, byKind: [:], checkedAt: date)
    }

    /// State for one category, defaulting to the overall verdict when unreported.
    func state(for kind: HealthDataKind) -> HealthAuthorizationState {
        byKind[kind] ?? overall
    }

    /// Categories required for a recovery score that are not authorized (§4.3).
    var missingRequiredKinds: [HealthDataKind] {
        HealthDataKind.allCases
            .filter { $0.isRequiredForRecovery }
            .filter { !state(for: $0).permitsReads }
    }

    /// Whether a recovery score is possible at all given current authorization.
    var permitsRecoveryScoring: Bool {
        missingRequiredKinds.isEmpty
    }
}
