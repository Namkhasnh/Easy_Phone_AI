import Foundation
import os
import SwiftData

/// SwiftData `LocalDataRepository` on the container's main context (ARCHITECTURE §4.4, §8).
@MainActor final class LiveLocalDataRepository: LocalDataRepository {
    private let context: ModelContext
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "localData")

    init(container: ModelContainer) {
        context = container.mainContext
    }

    // MARK: Saved places

    func savedPlaces() -> [SavedPlace] {
        fetch(FetchDescriptor<SavedPlace>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    func save(_ place: SavedPlace) {
        if place.modelContext == nil { context.insert(place) }
        persist("savePlace")
    }

    func delete(_ place: SavedPlace) {
        context.delete(place)
        persist("deletePlace")
    }

    // MARK: Nicknames

    func nicknames() -> [Nickname] {
        fetch(FetchDescriptor<Nickname>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    func nickname(matching text: String) -> Nickname? {
        var exact = FetchDescriptor<Nickname>(predicate: #Predicate { $0.nickname == text })
        exact.fetchLimit = 1
        if let hit = fetch(exact).first { return hit }
        return byNormalized(NameNormalizer.normalize(text))
    }

    @discardableResult
    func saveNickname(_ nickname: String, contactId: String) -> Nickname {
        let key = NameNormalizer.normalize(nickname)
        let row: Nickname
        if let existing = byNormalized(key) {
            existing.nickname = nickname
            existing.contactId = contactId
            row = existing
        } else {
            row = Nickname(nickname: nickname, contactId: contactId)
            context.insert(row)
        }
        persist("saveNickname")
        return row
    }

    func delete(_ nickname: Nickname) {
        context.delete(nickname)
        persist("deleteNickname")
    }

    // MARK: Settings

    func settings() -> AppSettings {
        if let row = fetch(FetchDescriptor<AppSettings>()).first { return row }
        let row = AppSettings()
        context.insert(row)
        persist("createSettings")
        return row
    }

    func saveSettings() { persist("saveSettings") }

    // MARK: Wipe

    func wipeMemory() {
        do {
            try context.delete(model: Nickname.self)
            try context.delete(model: SavedPlace.self)
        } catch { logFailure("wipeMemory", error) }
        persist("wipeMemory")
    }

    func wipeAll() {
        wipeMemory()
        do { try context.delete(model: AppSettings.self) } catch { logFailure("wipeAll", error) }
        persist("wipeAll")
    }

    // MARK: Private

    private func byNormalized(_ key: String) -> Nickname? {
        var d = FetchDescriptor<Nickname>(predicate: #Predicate { $0.normalized == key })
        d.fetchLimit = 1
        return fetch(d).first
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do { return try context.fetch(descriptor) } catch {
            logFailure("fetch", error)
            return []
        }
    }

    private func persist(_ op: String) {
        do { try context.save() } catch { logFailure(op, error) }
    }

    private func logFailure(_ op: String, _ error: any Error) {
        logger.error("\(op, privacy: .public) failed: \(String(describing: type(of: error)), privacy: .public)")
    }
}
