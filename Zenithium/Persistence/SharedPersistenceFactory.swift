//
//  SharedPersistenceFactory.swift
//  Zenithium
//
//  Who may open the shared store, and what to say when it cannot be opened.
//
//  ## The split with `ModelContainerFactory`
//
//  `ModelContainerFactory` knows how to build a container from the schema — which version,
//  which migration plan, CloudKit off. This type knows *where* the store lives and *which
//  process is allowed to write it*. Those are different questions with different failure
//  modes, and keeping them apart is what lets the entitlement problem be reported as an
//  entitlement problem rather than as "persistence unavailable".
//
//  ## Roles, not options
//
//  Two processes open this store and exactly one of them may write it. Expressing that as a
//  `Role` rather than an `allowsSave:` flag means a caller picks what it *is*, not what it
//  wants — an extension cannot ask for write access by passing `true`.
//
//  ## Why the failure has its own type
//
//  A missing App Group entitlement produces `containerURL == nil`, and that is the single
//  most confusing failure in this project to debug: everything compiles, the app launches,
//  and the store is simply not there. `Availability` names the three states apart so the
//  launch path can log which one it hit — a group that is not in the entitlement file at
//  all reads differently from one that is there but absent from the provisioning profile,
//  and both read differently from a container that exists but cannot be written.
//

import Foundation
import SwiftData

/// Resolves the App Group container the app and its extensions share.
enum SharedPersistenceFactory {

    /// Which process is opening the store.
    enum Role: Sendable {

        /// The main app. The only writer.
        case app

        /// A widget or intent extension. Read-only, so an extension process can never write
        /// into the store the app owns (ASSUMPTION WIDGET-1).
        case extensionProcess

        var allowsSave: Bool {
            switch self {
            case .app: return true
            case .extensionProcess: return false
            }
        }
    }

    /// What the shared container looks like from here.
    enum Availability: Sendable, Equatable {

        /// The container resolved and is writable by this process.
        case ready(URL)

        /// `containerURL(forSecurityApplicationGroupIdentifier:)` returned `nil`. The
        /// entitlement is missing from this target, or the group is not in the provisioning
        /// profile. Both are build-configuration problems, not runtime ones.
        case entitlementMissing(identifier: String)

        /// The container resolved but the directory could not be reached — an unusual state
        /// that in practice means the device is locked and the container is protected.
        case containerUnreachable(identifier: String, detail: String)

        var url: URL? {
            if case .ready(let url) = self { return url }
            return nil
        }
    }

    // MARK: - Resolution

    /// Where the shared store file is, or why it is not reachable.
    ///
    /// Reachability is checked rather than assumed: a container URL is handed out whether or
    /// not the directory can be opened, and the difference matters on a locked device.
    static func availability() -> Availability {
        guard let container = AppGroup.containerURL else {
            return .entitlementMissing(identifier: AppGroup.identifier)
        }
        guard let storeURL = AppGroup.storeURL else {
            return .entitlementMissing(identifier: AppGroup.identifier)
        }
        do {
            // Creating the directory is a no-op when it already exists, and it is the
            // cheapest operation that fails for the reason we want to distinguish.
            try FileManager.default.createDirectory(
                at: container,
                withIntermediateDirectories: true
            )
        } catch {
            return .containerUnreachable(
                identifier: AppGroup.identifier,
                detail: error.localizedDescription
            )
        }
        return .ready(storeURL)
    }

    /// The shared store URL, or the error that explains its absence.
    static func storeURL() throws -> URL {
        switch availability() {
        case .ready(let url):
            return url
        case .entitlementMissing(let identifier):
            ZenithiumLog.store.error(
                "App Group \(identifier, privacy: .public) is not reachable from this target"
            )
            throw ZenithiumError.appGroupUnavailable(identifier: identifier)
        case .containerUnreachable(let identifier, _):
            ZenithiumLog.store.error(
                "App Group \(identifier, privacy: .public) resolved but the directory could not be opened"
            )
            throw ZenithiumError.appGroupUnavailable(identifier: identifier)
        }
    }

    // MARK: - Containers

    /// Opens the shared container for a given role.
    static func makeContainer(for role: Role) throws -> ModelContainer {
        try ModelContainerFactory.make(at: storeURL(), allowsSave: role.allowsSave)
    }

    /// The app's read-write container.
    static func makeAppContainer() throws -> ModelContainer {
        try makeContainer(for: .app)
    }

    /// An extension's read-only container over the same store.
    ///
    /// Widgets read `WidgetSnapshotStore` instead (ASSUMPTION WIDGET-1) because a widget
    /// process has a tight memory budget and a small JSON file avoids both the container
    /// open and coupling the extension to the schema. This exists for an extension that
    /// genuinely needs history, and it is read-only so that choice stays safe.
    static func makeExtensionContainer() throws -> ModelContainer {
        try makeContainer(for: .extensionProcess)
    }
}
