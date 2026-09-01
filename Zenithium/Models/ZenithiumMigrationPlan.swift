//
//  ZenithiumMigrationPlan.swift
//  Zenithium
//
//  Spec §7 requires the migration plan type to exist. It now has a stage.
//
//  When the next schema change lands:
//  1. Copy the model list into a `SchemaV4` enum, changed as needed.
//  2. Append `SchemaV4.self` to `schemas` and point `ModelContainerFactory` at it.
//  3. Append a `MigrationStage.lightweight(fromVersion:toVersion:)` — or `.custom(...)` when
//     values must be transformed — to `stages`.
//  4. Bump `EngineConstants.Orchestration.engineVersion` if the change alters computed
//     values, so existing records are backfilled rather than left stale (§7).
//

import Foundation
import SwiftData

/// Zenithium's schema migration plan.
enum ZenithiumMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            // V1 → V2 adds `SupplementCourseLog` and changes nothing that existed, so
            // SwiftData can do it without a transformation. Yol haritası v4, C5.
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            // V2 → V3 adds `UserProfile.appearanceRawValue`, defaulted. Yol haritası v4, B6.
            .lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
        ]
    }
}
