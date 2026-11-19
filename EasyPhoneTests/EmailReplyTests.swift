import Foundation
import Testing
@testable import EasyPhoneAI

/// 2.6 / 2.7 — `emailReply` (DATA_MODEL §4, API_GMAIL §5, D-103, D-105, D-106, D-304, D-307): recipient address from
/// Contacts, S04, "Xác nhận" → Gmail draft (never sent), evidence, same key on retry.
@MainActor
@Suite("emailReply → Gmail draft")
struct EmailReplyTests {
    let repo = MockTaskRepository()

    func step(_ values: [String: String]) -> TaskStep {
        let fields = FieldCatalog.mvp.fields(.emailReply, .create).map {
            Field(id: $0.id, type: $0.type, value: values[$0.id], source: .ai, deviceOnly: $0.deviceOnly)
        }
        return TaskStep(order: 0, kind: .emailReply, operation: .create, fields: fields)
    }

    static let lan = ContactRecord(id: "lan", givenName: "Lan", middleName: "Thị", familyName: "Nguyễn", phoneCount: 0)
    static let lan2 = ContactRecord(id: "lan2", givenName: "Lan", familyName: "Trần", phoneCount: 0)

    func resolver(_ contacts: MockContactsService, permissions: MockPermissionManager = MockPermissionManager()) -> DeviceResolver {
        DeviceResolver(contacts: contacts, calendar: MockCalendarService(), permissions: permissions)
    }

    // MARK: - Address (D-307)

    @Test func catalogKeepsTheAddressOnTheDevice() {
        let spec = FieldCatalog.mvp.fields(.emailReply, .create)
        #expect(spec.first { $0.id == "toAddress" }?.deviceOnly == true)
        #expect(FieldCatalog.mvp.rule(.emailReply, .create)?.fields == ["recipientName", "toAddress", "body"])
        let d = TaskDraft(inputMode: .text, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh",
                          steps: [step(["recipientName": "chị Lan", "toAddress": "lan@example.com", "body": "Chào chị"])])
        let wire = DraftBuilder.wireDraft(d)
        let ids = wire.steps[0].fields.map(\.id)
        #expect(!ids.contains("toAddress") && !ids.contains("accountEmail") && ids.contains("body"))   // D-056
    }

    @Test func addressFromContacts() async {
        let perms = MockPermissionManager()
        perms.set(.contacts, .granted)
        let one = resolver(MockContactsService([Self.lan], emails: ["lan": ["Lan.Nguyen@Example.com"]]), permissions: perms)
        let r1 = await one.resolve(step(["recipientName": "chị Lan"]), timeZoneId: "Asia/Ho_Chi_Minh")
        #expect(r1.values["toAddress"] == "lan.nguyen@example.com")

        let typed = await one.resolve(step(["recipientName": "boss@company.vn"]), timeZoneId: "Asia/Ho_Chi_Minh")
        #expect(typed.values["toAddress"] == "boss@company.vn")

        let many = resolver(MockContactsService([Self.lan, Self.lan2],
                                                emails: ["lan": ["lan@a.vn"], "lan2": ["lan@b.vn", "lan@a.vn"]]),
                            permissions: perms)
        let r2 = await many.resolve(step(["recipientName": "Lan"]), timeZoneId: "Asia/Ho_Chi_Minh")
        #expect(r2.values["toAddress"] == nil)                                     // never auto-picked (D-106)
        let rows = r2.ambiguities["toAddress"]?.candidates ?? []
        #expect(rows.map(\.id) == ["lan@a.vn", "lan@b.vn"])                        // the same address once
        #expect(rows.first?.title == "Nguyễn Thị Lan" && rows.first?.subtitle == "lan@a.vn")

        let none = await one.resolve(step(["recipientName": "Hùng"]), timeZoneId: "Asia/Ho_Chi_Minh")
        #expect(none.isEmpty)                                                      // typed later in S05
    }

    @Test func noContactsAccessResolvesNothing() async {
        let perms = MockPermissionManager()
        perms.set(.contacts, .denied)
        let r = await resolver(MockContactsService([Self.lan], emails: ["lan": ["lan@a.vn"]]), permissions: perms)
            .resolve(step(["recipientName": "chị Lan"]), timeZoneId: "Asia/Ho_Chi_Minh")
        #expect(r.isEmpty)
    }

    @Test func emailRule() {
        #expect(DeviceResolver.isEmailAddress("a.b@c.vn"))
        for bad in ["chị Lan", "a@b", "Lan <lan@a.vn>", "a b@c.vn", "a@b.c,d@e.f"] {
            #expect(!DeviceResolver.isEmailAddress(bad), "\(bad)")
        }
    }

    // MARK: - Execute (D-103, D-105, D-124)

    func review(_ api: MockAPIClient, gmail: MockGmailService,
                values: [String: String] = ["recipientName": "chị Lan", "toAddress": "lan@example.com",
                                            "subject": "Xin nghỉ", "body": "Chào chị Lan,\nMai em xin nghỉ ạ."])
        -> ReviewViewModel {
        let e = TaskEngine(repository: repo, executors: [.emailReply: EmailDraftExecutor(api: api, gmail: gmail)])
        let d = TaskDraft(inputMode: .voice, originalInput: "x", timeZoneId: "Asia/Ho_Chi_Minh", steps: [step(values)])
        repo.save(d)
        e.revalidate(stepId: d.steps[0].id, in: d)
        return ReviewViewModel(draftId: d.id, repository: repo, engine: e, permissions: MockPermissionManager())
    }

    @Test func confirmSavesADraftWithTheStepKey() async throws {
        let api = MockAPIClient()
        let vm = review(api, gmail: MockGmailService(accounts: [MockGmailService.sample]))
        #expect(vm.step?.state == .awaitingApproval)
        #expect(api.gmailDraftCalls.isEmpty)                                       // nothing before "Xác nhận"
        await vm.confirm()
        #expect(vm.step?.state == .succeeded)
        #expect(vm.step?.resultEvidence == "gmail:draft:r-5823")
        let call = try #require(api.gmailDraftCalls.first)
        #expect(call.request.to == ["lan@example.com"] && call.request.subject == "Xin nghỉ")
        #expect(call.request.accountId == MockGmailService.sample.accountId && call.request.replyTo == nil)
        #expect(call.key.value == vm.step?.id.uuidString.lowercased())             // D-105
        #expect(vm.resultCard?.detail == UserMessage(key: "result.gmailDraft").text)            // never "sent"
        #expect(vm.resultCard?.secondary?.action == .open(URL(string: ReviewViewModel.gmailDraftsURL)!))
    }

    @Test func failuresKeepTheDraftAndRetryUsesTheSameKey() async throws {
        let api = MockAPIClient()
        api.setGmailDraft(.failure(.network(.offline)))
        let vm = review(api, gmail: MockGmailService(accounts: [MockGmailService.sample]))
        await vm.confirm()
        #expect(vm.step?.state == .failed && vm.step?.errorCode == "network.offline")
        vm.perform(.retry)
        api.setGmailDraft(.success(.mock))
        await vm.confirm()
        #expect(vm.step?.state == .succeeded)
        #expect(Set(api.gmailDraftCalls.map(\.key.value)).count == 1)               // same key both times
    }

    @Test func noAccountOrExpiredFails() async {
        let none = review(MockAPIClient(), gmail: MockGmailService())
        await none.confirm()
        #expect(none.step?.errorCode == "gmail_not_connected")
        let dead = GmailAccount(accountId: "gma_1", email: "k@gmail.com", status: .needsReconnect)
        let expired = review(MockAPIClient(), gmail: MockGmailService(accounts: [dead]))
        await expired.confirm()
        #expect(expired.step?.errorCode == "gmail_reconnect_required")
    }

    @Test func missingAddressBlocksConfirm() {
        let vm = review(MockAPIClient(), gmail: MockGmailService(accounts: [MockGmailService.sample]),
                        values: ["recipientName": "Hùng", "body": "Chào anh"])
        #expect(vm.step?.state == .needsInfo)
        #expect(vm.visibleFields.map(\.id) == ["recipientName", "toAddress", "subject", "body"])   // ids hidden
    }

    @Test func strings() {
        for key in ["field.emailReply.recipientName", "field.emailReply.toAddress", "field.emailReply.subject",
                    "field.emailReply.body", "step.emailReply.create", "result.gmailDraft", "mail.openGmail",
                    "ambiguity.email"] {
            #expect(UserMessage(key: key).text != key, "missing \(key)")
        }
    }
}
