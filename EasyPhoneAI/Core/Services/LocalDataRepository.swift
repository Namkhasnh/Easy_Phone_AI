import Foundation

/// ARCHITECTURE §4.4: `SavedPlace`, `Nickname`, `AppSettings` (DATA_MODEL §5). Main actor, like `TaskRepository`.
// TODO(spec): ARCHITECTURE §4.4 names this repository but lists no methods; the simplest CRUD set is used.
@MainActor protocol LocalDataRepository: AnyObject, Sendable {
    /// Newest first.
    func savedPlaces() -> [SavedPlace]
    func save(_ place: SavedPlace)
    func delete(_ place: SavedPlace)

    /// Newest first.
    func nicknames() -> [Nickname]
    /// Exact or normalized lookup (§7.2 match order steps 1–2).
    func nickname(matching text: String) -> Nickname?
    /// Upsert by `normalized`: saving "Mẹ" again replaces the contact of "mẹ" (unique key, §5).
    @discardableResult func saveNickname(_ nickname: String, contactId: String) -> Nickname
    func delete(_ nickname: Nickname)

    /// The single settings row; created with §5 defaults on first call.
    func settings() -> AppSettings
    /// Persists changes made to `settings()` (autosave from S15).
    func saveSettings()

    /// "Xóa dữ liệu ghi nhớ": deletes every `Nickname` and `SavedPlace` (§5).
    func wipeMemory()
    /// Account deletion (D-073): also resets settings.
    func wipeAll()
}
