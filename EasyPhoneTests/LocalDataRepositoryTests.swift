import Foundation
import SwiftData
import Testing
@testable import EasyPhoneAI

/// 1A.9b — DATA_MODEL §5 local models + §7.2 `normalize` + §13 "Name normalization".
@Suite("NameNormalizer (DATA_MODEL §7.2)")
struct NameNormalizerTests {
    @Test(arguments: [
        ("minh", "Minh"), ("minh", "Mính"), ("duc", "đức"), ("duc", "Đức"), ("me", "Mẹ"),
        ("anh minh", "  Anh   Minh "), ("nguyen van a", "NGUYỄN Văn A"),
    ])
    func folds(_ expected: String, _ input: String) {
        #expect(NameNormalizer.normalize(input) == expected)
    }

    @Test func fullWidthFolds() {
        #expect(NameNormalizer.normalize("ＭＩＮＨ") == "minh")
    }
}

@MainActor
@Suite("LiveLocalDataRepository (SwiftData, in memory)")
struct LiveLocalDataRepositoryTests {
    let container: ModelContainer
    let repo: LiveLocalDataRepository

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        repo = LiveLocalDataRepository(container: container)
    }

    static func place(_ label: String, at: Date = .now) -> SavedPlace {
        SavedPlace(label: label, name: "Nhà", address: "1 Lê Lợi", latitude: 10.77, longitude: 106.70, createdAt: at)
    }

    @Test func settingsIsOneRowWithDefaults() throws {
        let s = repo.settings()
        #expect(s.voiceEnabled && !s.simpleMode)
        #expect(s.speechRate == 0.45 && s.snoozeMorningHour == 8 && s.preferredMapsApp == "googleMaps")
        #expect(s.lastSeenEntitlement == nil)
        s.snoozeMorningHour = 7
        repo.saveSettings()
        #expect(repo.settings() === s)
        #expect(try ModelContext(container).fetch(FetchDescriptor<AppSettings>()).map(\.snoozeMorningHour) == [7])
    }

    @Test func savedPlacesNewestFirstAndDelete() {
        let home = Self.place("home", at: .distantPast), work = Self.place("work")
        repo.save(home); repo.save(work); repo.save(work)
        #expect(repo.savedPlaces().map(\.label) == ["work", "home"])
        repo.delete(work)
        #expect(repo.savedPlaces().map(\.label) == ["home"])
    }

    @Test func nicknameUpsertByNormalizedKey() throws {
        repo.saveNickname("mẹ", contactId: "C1")
        repo.saveNickname("Mẹ", contactId: "C2")                       // same key "me" → replaces
        let all = repo.nicknames()
        #expect(all.count == 1)
        #expect(all[0].contactId == "C2" && all[0].nickname == "Mẹ" && all[0].normalized == "me")
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Nickname>()) == 1)
    }

    @Test func nicknameLookupExactThenNormalized() {
        repo.saveNickname("sếp", contactId: "C9")
        #expect(repo.nickname(matching: "sếp")?.contactId == "C9")
        #expect(repo.nickname(matching: "SẾP")?.contactId == "C9")
        #expect(repo.nickname(matching: "sep")?.contactId == "C9")
        #expect(repo.nickname(matching: "mẹ") == nil)
    }

    @Test func wipeMemoryKeepsSettingsWipeAllResets() throws {
        repo.save(Self.place("home"))
        repo.saveNickname("mẹ", contactId: "C1")
        repo.settings().simpleMode = true
        repo.saveSettings()

        repo.wipeMemory()
        #expect(repo.savedPlaces().isEmpty && repo.nicknames().isEmpty)
        #expect(repo.settings().simpleMode)

        repo.wipeAll()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<AppSettings>()) == 0)
        #expect(!repo.settings().simpleMode)                           // recreated with defaults
    }
}

@MainActor
@Suite("MockLocalDataRepository")
struct MockLocalDataRepositoryTests {
    @Test func behavesLikeLive() {
        let repo = MockLocalDataRepository()
        repo.saveNickname("mẹ", contactId: "C1")
        repo.saveNickname("Mẹ", contactId: "C2")
        #expect(repo.nicknames().map(\.contactId) == ["C2"])
        #expect(repo.nickname(matching: "me")?.contactId == "C2")
        #expect(repo.settings() === repo.settings())
        repo.wipeAll()
        #expect(repo.nicknames().isEmpty)
    }
}
