//
//  AppGroup.swift
//  Zenithium
//
//  The shared container both the app and the widget extension read. Spec §10 (shared App
//  Group container), ASSUMPTION STORE-2 and WIDGET-1.
//

import Foundation

/// The App Group the app and its widget extension share.
enum AppGroup {

    /// ASSUMPTION STORE-2 — the group identifier declared in both entitlement files.
    static let identifier = "group.com.cagla.zenithium"

    /// The shared container directory, or `nil` when the entitlement is missing.
    ///
    /// Every caller treats `nil` as `ZenithiumError.appGroupUnavailable` rather than falling
    /// back to the app sandbox, because a silent fallback would leave the widget reading a
    /// file the app never writes.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// The shared defaults suite, or `nil` when the entitlement is missing.
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// The SwiftData store file inside the shared container (ASSUMPTION STORE-2).
    static var storeURL: URL? {
        containerURL?.appending(path: "Zenithium.store", directoryHint: .notDirectory)
    }

    /// The widget snapshot file inside the shared container (ASSUMPTION WIDGET-1).
    static var widgetSnapshotURL: URL? {
        containerURL?.appending(path: "widget-snapshot.json", directoryHint: .notDirectory)
    }
}
