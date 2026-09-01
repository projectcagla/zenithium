//
//  ModelContainerFactory.swift
//  Zenithium
//
//  Builds the SwiftData container. Spec §7 requires an explicit `Schema` and
//  `ModelConfiguration`.
//
//  This file answers "how is a container built from the schema" and nothing else. *Where*
//  the shared store lives, and which process may write it, is `SharedPersistenceFactory`'s
//  question — see the note there for why the two are apart.
//

import Foundation
import SwiftData

enum ModelContainerFactory {

    /// Opens a container over a store file.
    ///
    /// CloudKit is explicitly disabled. Zenithium has no network entitlement and §12 promises
    /// data never leaves the device — leaving the CloudKit database at its default would make
    /// that promise depend on an omission rather than on a decision.
    static func make(at url: URL, allowsSave: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: SchemaV3.schema,
            url: url,
            allowsSave: allowsSave,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: SchemaV3.schema,
                migrationPlan: ZenithiumMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            ZenithiumLog.store.error("Container creation failed")
            throw ZenithiumError.persistenceUnavailable(detail: error.localizedDescription)
        }
    }

    /// An in-memory container for tests and previews (§11 — suites must run without a device).
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: SchemaV3.schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: SchemaV3.schema,
                migrationPlan: ZenithiumMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            throw ZenithiumError.persistenceUnavailable(detail: error.localizedDescription)
        }
    }
}
