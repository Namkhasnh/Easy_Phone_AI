import Foundation
import Testing
@testable import EasyPhoneAI

/// 2.3 — Gmail connect on the device (API_GMAIL §2–§3, D-151, D-306, D-310): PKCE consent request, callback
/// parsing, `LiveGmailService` guard, S15 Settings states.
@MainActor
@Suite("Gmail connect (API_GMAIL §2–§3)")
struct GmailConnectTests {
    static let clientID = "971763888498-37dojsggjfkt0p9h6ffggadnv4r6i1c8.apps.googleusercontent.com"

    // MARK: - Consent request

    @Test func pkceChallengeMatchesRFC7636Example() {
        let request = GoogleConsentRequest(clientID: Self.clientID,
                                           codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "s")
        #expect(request.codeChallenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")   // RFC 7636 Appendix B
        #expect(GoogleConsentRequest.randomToken().count == 43)
        #expect(GoogleConsentRequest.randomToken() != GoogleConsentRequest.randomToken())
    }

    @Test func redirectIsTheReversedClientID() {
        let request = GoogleConsentRequest(clientID: Self.clientID)
        #expect(request.callbackScheme == "com.googleusercontent.apps.971763888498-37dojsggjfkt0p9h6ffggadnv4r6i1c8")
        #expect(request.redirectURI == request.callbackScheme + ":/oauth2redirect")
    }

    @Test func authorizationURLAsksForReadAndComposeOfflineWithPKCE() throws {
        let request = GoogleConsentRequest(clientID: Self.clientID, codeVerifier: String(repeating: "a", count: 43),
                                           state: "st8")
        let items = try #require(URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(request.authorizationURL.host() == "accounts.google.com")
        #expect(query["client_id"] == Self.clientID && query["response_type"] == "code")
        #expect(query["code_challenge_method"] == "S256" && query["code_challenge"] == request.codeChallenge)
        #expect(query["access_type"] == "offline" && query["prompt"] == "consent" && query["state"] == "st8")
        let scopes = Set((query["scope"] ?? "").split(separator: " ").map(String.init))
        #expect(scopes.contains("https://www.googleapis.com/auth/gmail.readonly"))
        #expect(scopes.contains("https://www.googleapis.com/auth/gmail.compose"))
        #expect(!scopes.contains("https://mail.google.com/"))                       // no full-access scope
        #expect(query["code_verifier"] == nil)                                     // the verifier never goes to Google here
    }

    @Test func callbackGivesTheCodeOnlyWithTheRightState() throws {
        let request = GoogleConsentRequest(clientID: Self.clientID, state: "good")
        let base = request.redirectURI
        #expect(request.code(from: try #require(URL(string: "\(base)?state=good&code=4/0Ae&scope=x"))) == "4/0Ae")
        #expect(request.code(from: try #require(URL(string: "\(base)?state=bad&code=4/0Ae"))) == nil)
        #expect(request.code(from: try #require(URL(string: "\(base)?state=good&error=access_denied"))) == nil)
        #expect(request.code(from: try #require(URL(string: "\(base)?state=good"))) == nil)
    }

    @Test func liveServiceWithoutClientIDDoesNotOpenGoogle() async {
        let service = LiveGmailService(api: MockAPIClient(), clientID: nil)
        await #expect(throws: ServiceError.unavailable(GmailErrorCode.notConfigured)) { _ = try await service.connect() }
    }

    // MARK: - S15

    func model(_ gmail: MockGmailService, available: Bool = true) -> SettingsViewModel {
        SettingsViewModel(localData: MockLocalDataRepository(), drafts: MockTaskRepository(), auth: MockAuthService(),
                          gmail: gmail, gmailAvailable: available)
    }

    @Test func connectShowsTheAccount() async {
        let vm = model(MockGmailService())
        await vm.loadGmail()
        #expect(vm.gmailAccount == nil)
        await vm.connectGmail()
        #expect(vm.gmailAccount == MockGmailService.sample && vm.gmailMessage == nil && !vm.gmailBusy)
        #expect(vm.gmailAccountText == "Gmail: khoai.demo@gmail.com")
    }

    @Test func closingTheGoogleSheetIsNotAnError() async {
        let vm = model(MockGmailService(connectError: CancellationError()))
        await vm.connectGmail()
        #expect(vm.gmailAccount == nil && vm.gmailMessage == nil)
    }

    @Test func failuresMapToKeys() async {
        let scope = AppError.api(code: "invalid_input", retryable: false,
                                 details: APIErrorDetails(field: "scope", reason: "missingScope"), requestId: nil)
        let vm = model(MockGmailService(connectError: scope))
        await vm.connectGmail()
        #expect(vm.gmailMessage == UserMessage(key: "settings.gmail.missingScope"))
        #expect(SettingsViewModel.gmailFailure(AppError.api(code: "gmail_account_limit", retryable: false, details: nil,
                                                            requestId: nil)) == UserMessage(key: "error.gmail_account_limit"))
        #expect(SettingsViewModel.gmailFailure(AppError.network(.offline)) == UserMessage(key: "error.network.offline"))
        #expect(SettingsViewModel.gmailFailure(ServiceError.framework(code: GmailErrorCode.consentFailed))
                == UserMessage(key: "settings.gmail.failed"))
        for key in ["settings.gmail.missingScope", "settings.gmail.failed", "error.gmail_account_limit",
                    "settings.gmail.connect", "settings.gmail.reconnect", "confirm.gmailDisconnect.title"] {
            #expect(UserMessage(key: key).text != key, "missing string \(key)")
        }
    }

    @Test func disconnectNeedsTheConfirmTap() async {
        let gmail = MockGmailService(accounts: [MockGmailService.sample])
        let vm = model(gmail)
        await vm.loadGmail()
        #expect(vm.gmailAccount != nil)
        vm.pendingConfirm = .gmailDisconnect
        #expect(gmail.disconnectCalls.isEmpty)                                     // nothing before the tap
        #expect(SettingsViewModel.Confirm.gmailDisconnect.confirmKey == "confirm.gmailDisconnect.yes")
        await vm.perform(.gmailDisconnect)
        #expect(gmail.disconnectCalls == [MockGmailService.sample.accountId] && vm.gmailAccount == nil)
    }

    @Test func noClientIDMeansNoCalls() async {
        let gmail = MockGmailService(accounts: [MockGmailService.sample])
        let vm = model(gmail, available: false)
        await vm.loadGmail()
        #expect(vm.gmailAccount == nil)
    }
}
