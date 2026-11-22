import Foundation
import SwiftData

/// Builds the app's single SwiftData container (ARCHITECTURE §2, §8: main context, `@MainActor`).
enum ModelContainerFactory {
    /// `inMemory: true` for previews and tests; the app uses the on-disk store.
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: EasyPhoneMigrationPlan.self, configurations: [config])
    }

    /// 1G.10 XCUITest only (`-uiTestDisk YES`): an on-disk store in its own file, so a test can kill and relaunch the
    /// app and find its drafts again, without ever opening the user's store. `reset` deletes it first.
    static func makeUITestStore(reset: Bool) throws -> ModelContainer {
        let dir = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "uitest.store")
        if reset {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path(percentEncoded: false) + suffix) }
        }
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, migrationPlan: EasyPhoneMigrationPlan.self, configurations: [config])
    }
}
