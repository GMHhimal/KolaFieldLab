//
//  Persistence.swift
//  KolaCare
//
//  SwiftData stack (SwiftData sits on top of the Core Data SQLite store).
//  A versioned schema and migration plan are declared from day one so future
//  model changes can be migrated without losing a farmer's scan history.
//

import Foundation
import SwiftData
import OSLog

enum KolaCareSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Plant.self, ScanRecord.self] }
}

enum KolaCareMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [KolaCareSchemaV1.self] }
    /// Add `MigrationStage.lightweight(fromVersion:toVersion:)` entries here when V2 ships.
    static var stages: [MigrationStage] { [] }
}

enum PersistenceController {
    static let schema = Schema(versionedSchema: KolaCareSchemaV1.self)

    /// Creates the app's model container.
    /// If the on-disk store cannot be opened, the app falls back to an in-memory
    /// store instead of crashing, and logs the error.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration("KolaCare", schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, migrationPlan: KolaCareMigrationPlan.self,
                                      configurations: [configuration])
        } catch {
            Logger.persistence.fault("Failed to open store, using in-memory fallback: \(error.localizedDescription, privacy: .public)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // An in-memory store with a valid schema cannot fail to open.
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }

    /// Container pre-filled with demo data, used by SwiftUI previews.
    @MainActor
    static let preview: ModelContainer = {
        let container = makeContainer(inMemory: true)
        DemoDataSeeder.seed(into: container.mainContext)
        return container
    }()
}
