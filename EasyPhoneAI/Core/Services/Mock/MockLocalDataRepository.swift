import Foundation

/// In-memory `LocalDataRepository` for previews and tests (D-206). Models live without a `ModelContext`.
@MainActor final class MockLocalDataRepository: LocalDataRepository {
    private var places: [SavedPlace] = []
    private var names: [Nickname] = []
    private var settingsRow: AppSettings?

    /// `nonisolated` so `AppEnvironment.mock()` can build it off the main actor.
    nonisolated init() {}

    func savedPlaces() -> [SavedPlace] { places.sorted { $0.createdAt > $1.createdAt } }
    func save(_ place: SavedPlace) { if !places.contains(where: { $0 === place }) { places.append(place) } }
    func delete(_ place: SavedPlace) { places.removeAll { $0 === place } }

    func nicknames() -> [Nickname] { names.sorted { $0.createdAt > $1.createdAt } }

    func nickname(matching text: String) -> Nickname? {
        names.first { $0.nickname == text } ?? names.first { $0.normalized == NameNormalizer.normalize(text) }
    }

    @discardableResult
    func saveNickname(_ nickname: String, contactId: String) -> Nickname {
        if let existing = names.first(where: { $0.normalized == NameNormalizer.normalize(nickname) }) {
            existing.nickname = nickname
            existing.contactId = contactId
            return existing
        }
        let row = Nickname(nickname: nickname, contactId: contactId)
        names.append(row)
        return row
    }

    func delete(_ nickname: Nickname) { names.removeAll { $0 === nickname } }

    func settings() -> AppSettings {
        if let settingsRow { return settingsRow }
        let row = AppSettings()
        settingsRow = row
        return row
    }

    func saveSettings() {}

    func wipeMemory() {
        places = []
        names = []
    }

    func wipeAll() {
        wipeMemory()
        settingsRow = nil
    }
}
