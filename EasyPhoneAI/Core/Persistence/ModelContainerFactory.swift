import SwiftData

/// Builds the app's single SwiftData container (ARCHITECTURE §2, §8: main context, `@MainActor`).
enum ModelContainerFactory {
    /// `inMemory: true` for previews and tests; the app uses the on-disk store.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: EasyPhoneMigrationPlan.self, configurations: [config])
    }
}
