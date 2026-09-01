//
//  SchemaV3.swift
//  Zenithium
//
//  Version 3 of Zenithium's store. Yol haritası v4, B6.
//
//  `UserProfile` gained `appearanceRawValue`, defaulted so an existing row reads as dark.
//  Nothing was renamed, retyped or removed, so the stage is lightweight — but the version
//  still has to move, because a store on somebody's phone does not have the column.
//

import Foundation
import SwiftData

/// Version 3 of Zenithium's store.
enum SchemaV3: VersionedSchema {

    static var versionIdentifier: Schema.Version {
        Schema.Version(3, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        SchemaV2.models
    }
}

extension SchemaV3 {

    /// The `Schema` value the container is built from.
    static var schema: Schema {
        Schema(models, version: versionIdentifier)
    }
}
