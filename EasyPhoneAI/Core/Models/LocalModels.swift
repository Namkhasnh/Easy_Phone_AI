import Foundation
import SwiftData

// DATA_MODEL §5 — local only, never sent to the backend (🔒, D-056). Saved-place addresses stay on device;
// only the label ("home") may be sent (§5 note).

@Model final class SavedPlace {
    @Attribute(.unique) var id: UUID
    var label: String            // "home" | "work" | "custom"
    var customLabel: String?     // "Nhà con gái"
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var createdAt: Date

    init(id: UUID = UUID(), label: String, customLabel: String? = nil, name: String, address: String,
         latitude: Double, longitude: Double, createdAt: Date = .now) {
        self.id = id
        self.label = label
        self.customLabel = customLabel
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
    }
}

@Model final class Nickname {
    @Attribute(.unique) var id: UUID
    var nickname: String         // "mẹ", "sếp" — stored as typed
    @Attribute(.unique) var normalized: String   // §7.2 key; unique
    var contactId: String        // 🔒 CNContact.identifier
    var createdAt: Date

    init(id: UUID = UUID(), nickname: String, contactId: String, createdAt: Date = .now) {
        self.id = id
        self.nickname = nickname
        self.normalized = NameNormalizer.normalize(nickname)
        self.contactId = contactId
        self.createdAt = createdAt
    }
}

/// Exactly one row (`LocalDataRepository.settings()` creates it on first use).
@Model final class AppSettings {
    var voiceEnabled: Bool = true
    var speechRate: Double = 0.45     // AVSpeechUtterance rate
    var simpleMode: Bool = false      // "Chế độ đơn giản"
    var snoozeMorningHour: Int = 8
    var preferredMapsApp: String = "appleMaps"
    var lastSeenEntitlement: CachedEntitlement?  // display only (D-085)
    var petEnabled: Bool = true       // "Hiện bạn Khoai" (D-289)
    var autoSend: Bool = true         // "Tự gửi khi nói xong" (D-296)

    init() {}
}
