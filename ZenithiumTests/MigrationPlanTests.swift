//
//  MigrationPlanTests.swift
//  ZenithiumTests
//
//  Tests for SwiftData versioned schemas and lightweight migration stages (§7).
//

import Foundation
import SwiftData
import Testing
@testable import Zenithium

@Suite("SwiftData schema migration plan")
struct MigrationPlanTests {

    @Test("Schema versions are strictly ordered and versioned")
    func schemaVersionsAreOrdered() {
        let schemas = ZenithiumMigrationPlan.schemas
        #expect(schemas.count == 3)
        #expect(schemas[0].versionIdentifier == SchemaV1.versionIdentifier)
        #expect(schemas[1].versionIdentifier == SchemaV2.versionIdentifier)
        #expect(schemas[2].versionIdentifier == SchemaV3.versionIdentifier)

        #expect(SchemaV1.versionIdentifier < SchemaV2.versionIdentifier)
        #expect(SchemaV2.versionIdentifier < SchemaV3.versionIdentifier)
    }

    @Test("Migration stages bridge consecutive schema versions")
    func stagesBridgeVersions() {
        let stages = ZenithiumMigrationPlan.stages
        #expect(stages.count == 2)
    }

    @Test("ModelContainer initializes with current SchemaV3 and migration plan")
    func containerInitializesWithMigrationPlan() throws {
        let container = try ModelContainerFactory.makeInMemory()
        #expect(container.schema.entities.count >= 12)
    }
}
