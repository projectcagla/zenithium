//
//  ZenithiumLog.swift
//  Zenithium
//
//  Categorised OSLog vendor. Spec §2.5 (OSLog categorised logging), §2.4 (print() banned),
//  ASSUMPTION LOG-1 (subsystem, categories, privacy posture).
//

import Foundation
import OSLog

/// The app's only logging surface.
///
/// Raw biometric values must never be logged at `.notice` or above, and must always be
/// marked `privacy: .private` so they cannot appear in a sysdiagnose. Use the helpers in
/// `ZenithiumLog.Redacted` rather than interpolating values directly.
enum ZenithiumLog {

    /// ASSUMPTION LOG-1: subsystem is the app bundle identifier.
    static let subsystem = "com.zenithium.app"

    /// HealthKit authorization, queries, anchors, background delivery.
    static let health = Logger(subsystem: subsystem, category: "health")

    /// Pure engine computation — inputs dropped, weights renormalized, degenerate guards hit.
    static let engine = Logger(subsystem: subsystem, category: "engine")

    /// SwiftData container lifecycle, reads, writes, backfill decisions.
    static let store = Logger(subsystem: subsystem, category: "store")

    /// The recalculation pipeline, observation relay, background task scheduling.
    static let orchestration = Logger(subsystem: subsystem, category: "orchestration")

    /// View and view-model state transitions.
    static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Widget timeline provider and App Group snapshot IO.
    static let widget = Logger(subsystem: subsystem, category: "widget")

    /// Anlatıcı katmanı — cihaz içi model kullanılabilirliği ve geri düşüşler.
    static let intelligence = Logger(subsystem: subsystem, category: "intelligence")

    /// Laboratuvar belgesi okuma ve ayrıştırma.
    static let labs = Logger(subsystem: subsystem, category: "labs")

    /// Formatting helpers for values that must not leak into logs verbatim.
    enum Redacted {

        /// Describes a biometric magnitude without disclosing it: order of magnitude only.
        /// Used at `.notice` and above where `privacy: .private` is not sufficient because
        /// the log line itself may be surfaced in a diagnostic bundle.
        static func magnitude(_ value: Double) -> String {
            guard value.isFinite else { return "nonfinite" }
            let magnitude = abs(value)
            if magnitude == 0 { return "zero" }
            if magnitude < 1 { return "<1" }
            if magnitude < 10 { return "1s" }
            if magnitude < 100 { return "10s" }
            if magnitude < 1000 { return "100s" }
            return "1000s+"
        }

        /// Describes a count bucket, safe for `.notice`.
        static func count(_ value: Int) -> String {
            switch value {
            case ..<0: return "negative"
            case 0: return "0"
            case 1...9: return "1-9"
            case 10...99: return "10-99"
            case 100...999: return "100-999"
            default: return "1000+"
            }
        }
    }
}
