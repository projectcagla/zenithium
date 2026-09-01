//
//  SchemaV1.swift
//  Zenithium
//
//  The versioned schema. Spec §7 requires an explicit `Schema` plus a `SchemaV1` enum.
//  ASSUMPTION STORE-3: `SchemaV1` is the only version today.
//

import Foundation
import SwiftData

/// Version 1 of Zenithium's store.
///
/// Adding a model here without bumping the version identifier will not migrate an existing
/// store — add a `SchemaV2` and a stage in `ZenithiumMigrationPlan` instead.
enum SchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            BaselineState.self,
            BiometricDayRecord.self,
            MuscleFatigueSnapshot.self,
            StrengthSessionLog.self,
            BloodMarker.self,
            JournalDayLog.self,
            HybridSessionLog.self,
            GoalEventLog.self,
            PainEntryLog.self,
            HealthDocumentLog.self
        ]
    }
}

extension SchemaV1 {

    /// The `Schema` value the container is built from.
    static var schema: Schema {
        Schema(models, version: versionIdentifier)
    }
}
