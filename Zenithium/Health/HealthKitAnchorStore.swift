//
//  HealthKitAnchorStore.swift
//  Zenithium
//
//  Persisted `HKQueryAnchor` storage. Spec §8: anchored queries must persist their anchors so
//  that deletions are noticed across launches (§5.6).
//
//  The actor deals only in `Data`, which is `Sendable`. Archiving and unarchiving happen in
//  the nonisolated `AnchorCoding` helpers, called from inside `HealthKitService`, so an
//  `HKQueryAnchor` never crosses an isolation boundary.
//

import Foundation
import HealthKit

/// Archives and unarchives `HKQueryAnchor`. Pure and nonisolated by construction.
enum AnchorCoding {

    /// Archives an anchor for storage. Returns `nil` if archiving fails, which is treated as
    /// "no anchor" — the next query re-reads from the beginning rather than losing deletions.
    static func data(from anchor: HKQueryAnchor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    /// Unarchives an anchor. Returns `nil` for data this build cannot decode, which again
    /// degrades to a full re-read rather than a crash.
    static func anchor(from data: Data) -> HKQueryAnchor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}

/// Stores one anchor blob per observed category, in the App Group so a widget-triggered
/// refresh and an app-triggered refresh share the same position in the stream.
actor HealthKitAnchorStore {

    private let defaults: UserDefaults?
    private var cache: [HealthDataKind: Data] = [:]

    /// - Parameter defaults: the App Group suite. `nil` degrades to in-memory anchors, which
    ///   is correct for tests and survivable in the app: anchors rebuild on next launch.
    init(defaults: UserDefaults? = AppGroup.defaults) {
        self.defaults = defaults
    }

    /// The stored anchor blob for a category.
    func anchorData(for kind: HealthDataKind) -> Data? {
        if let cached = cache[kind] { return cached }
        guard let data = defaults?.data(forKey: Self.key(for: kind)) else { return nil }
        cache[kind] = data
        return data
    }

    /// Replaces the stored anchor blob for a category.
    func setAnchorData(_ data: Data?, for kind: HealthDataKind) {
        if let data {
            cache[kind] = data
            defaults?.set(data, forKey: Self.key(for: kind))
        } else {
            cache.removeValue(forKey: kind)
            defaults?.removeObject(forKey: Self.key(for: kind))
        }
    }

    /// Clears every anchor, forcing a full re-read. Used when the engine version changes and
    /// history must be rebuilt (§7).
    func reset() {
        for kind in HealthDataKind.allCases {
            defaults?.removeObject(forKey: Self.key(for: kind))
        }
        cache.removeAll()
    }

    private static func key(for kind: HealthDataKind) -> String {
        "com.zenithium.anchor.\(kind.rawValue)"
    }
}
