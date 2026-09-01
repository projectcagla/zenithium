//
//  SchemaV2.swift
//  Zenithium
//
//  Version 2 of Zenithium's store. Yol haritası v4, C5.
//
//  The only change from `SchemaV1` is one added model, `SupplementCourseLog`. Nothing that
//  existed was renamed, retyped or removed, which is exactly the shape SwiftData's
//  lightweight migration handles — see the stage in `ZenithiumMigrationPlan`.
//
//  `SchemaV1` stays in the file it is in rather than being edited in place. A schema version
//  describes a store that exists on somebody's phone; rewriting it to match the present is
//  how a migration plan quietly stops describing the migration it is meant to perform.
//

import Foundation
import SwiftData

/// Version 2 of Zenithium's store.
enum SchemaV2: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(2, 0, 0)
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
            HealthDocumentLog.self,
            SupplementCourseLog.self
        ]
    }
}

extension SchemaV2 {

    /// The `Schema` value the container is built from.
    static var schema: Schema {
        Schema(models, version: versionIdentifier)
    }
}
