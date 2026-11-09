import SwiftData

/// DATA_MODEL §12: `VersionedSchema` + `SchemaMigrationPlan` from v1.
/// Models are added here by their items (`TaskDraft` 1A.2; `SavedPlace`, `Nickname`, `AppSettings` 1A.9).
/// Nothing has shipped yet, so adding models to v1 before the demo build is fine; after that, add `SchemaV2`.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [TaskDraft.self, SavedPlace.self, Nickname.self, AppSettings.self]
    }
}

enum EasyPhoneMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
