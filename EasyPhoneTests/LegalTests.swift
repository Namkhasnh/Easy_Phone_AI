import Foundation
import Testing
@testable import EasyPhoneAI

/// 1G.4 – 1G.6: privacy manifest, permission texts, in-app Terms / Privacy (D-186, D-187, D-188, D-284).
@Suite("Privacy and legal (1G)")
struct LegalTests {
    @Test func legalTextsExistAndMatchWhatTheAppDoes() {
        let privacy = UserMessage(key: "legal.privacy.body").text
        let terms = UserMessage(key: "legal.terms.body").text
        #expect(privacy != "legal.privacy.body" && terms != "legal.terms.body")
        #expect(privacy.contains("OpenAI"))                                    // D-187 AI provider disclosure
        #expect(privacy.contains("không bao giờ tự gửi thư"))                  // D-304
        #expect(privacy.contains("Xóa tài khoản"))                             // D-073
        #expect(terms.contains("113") && terms.contains("Xác nhận"))           // D-100
    }

    @Test func privacyManifestShipsWithTheApp() throws {
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
                                 as? [String: Any])
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        let types = (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
        #expect(!types.contains("NSPrivacyCollectedDataTypeContacts"))         // contacts stay on the phone (D-056)
        #expect(types.contains("NSPrivacyCollectedDataTypeEmailsOrTextMessages"))
    }

    @Test func everyPermissionHasAVietnameseReason() {                         // D-186
        let info = Bundle.main.infoDictionary ?? [:]
        for key in ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription",
                    "NSCalendarsFullAccessUsageDescription", "NSRemindersFullAccessUsageDescription",
                    "NSContactsUsageDescription", "NSCameraUsageDescription", "NSPhotoLibraryUsageDescription",
                    "NSPhotoLibraryAddUsageDescription", "NSLocationWhenInUseUsageDescription"] {
            #expect((info[key] as? String)?.isEmpty == false, "\(key)")
        }
    }
}
