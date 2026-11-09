import Foundation
import SwiftData

/// DATA_MODEL §3.2 (D-016). One user request = one draft with ordered steps (linked flow, D-120).
/// `currentStep`, `isClosed` and `overallStatus` are computed — added with the repository rules in 1A.9 (D-244).
@Model final class TaskDraft {
    @Attribute(.unique) var id: UUID
    var schemaVersion: Int                 // = 1
    var createdAt: Date
    var updatedAt: Date                    // bumped on every autosave (D-104)
    var inputMode: InputMode
    var originalInput: String              // transcript / typed text / OCR text
    var imageLocalPath: String?            // 🔒 relative path in Application Support/ocr/<id>.jpg
    var timeZoneId: String                 // at creation (D-058)
    var locale: String                     // "vi-VN"
    var followUpQuestion: String?          // the ONE pending question (spec §6.2 AC3)
    var steps: [TaskStep]                  // Codable composite attribute
    var isArchived: Bool                   // user swiped to hide
    var serverRequestId: String?           // id from /v1/parse for support/debug

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        inputMode: InputMode,
        originalInput: String,
        imageLocalPath: String? = nil,
        timeZoneId: String = TimeZone.current.identifier,
        locale: String = "vi-VN",
        followUpQuestion: String? = nil,
        steps: [TaskStep] = [],
        isArchived: Bool = false,
        serverRequestId: String? = nil
    ) {
        self.id = id
        self.schemaVersion = 1
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.inputMode = inputMode
        self.originalInput = originalInput
        self.imageLocalPath = imageLocalPath
        self.timeZoneId = timeZoneId
        self.locale = locale
        self.followUpQuestion = followUpQuestion
        self.steps = steps
        self.isArchived = isArchived
        self.serverRequestId = serverRequestId
    }
}

/// DATA_MODEL §3.2.
enum InputMode: String, Codable, Sendable, Hashable, CaseIterable {
    case text, voice, photo, shortcut
}
