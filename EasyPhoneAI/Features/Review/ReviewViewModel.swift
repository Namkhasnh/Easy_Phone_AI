import Foundation
import Observation

/// S04 Review (UI_SCREENS S04, spec §5.3, ARCHITECTURE §2.1). Forwards intents to `TaskEngine`; no business rules.
/// Holds the `@Model` draft itself (observable) instead of a value snapshot so edits made by the engine show at once.
@Observable @MainActor final class ReviewViewModel {
    private(set) var draft: TaskDraft?
    private(set) var stepId: UUID?
    /// Field whose editor (S05, 1A.12) should open.
    var editingFieldId: String?
    /// Set after "Hủy" / "Để sau": the View pops back.
    private(set) var didClose = false
    /// Set after "Xong": the View returns to Home (S02).
    private(set) var didFinish = false
    /// S18 sheet before "Xác nhận" executes (ARCHITECTURE §5.1 step 0, D-185), or before reading contacts (1C.9).
    var pendingPermission: PendingPermission?
    /// S06 picker (UI_SCREENS S06, D-106): the field whose ambiguity is shown.
    var pickingFieldId: String?
    /// Name of the 🔒 `contactId` for the S04 contact row (read on device, never stored in the draft).
    private(set) var contactName: String?
    /// S07 after a copy hand-off (Zalo…, D-162).
    var copyGuide: CopyGuide?
    /// The prefilled system SMS composer (ARCHITECTURE §5.3); the step stays `processing` while it is open.
    private(set) var pendingComposer: (recipients: [String], body: String)?
    /// The iOS contact picker is shown ("Chọn trong danh bạ", 1C.9c).
    var showsContactPicker = false
    /// "Chọn trong danh bạ" was tapped on S06: the iOS picker opens only once the S06 sheet is fully gone
    /// (BUG-006: presenting while the sheet was still closing left the picker frozen / off screen).
    private(set) var contactPickerAfterSheet = false
    /// Names of contacts handed over by the iOS picker (readable even without Contacts access).
    private var pickedNames: [String: String] = [:]
    /// S06 for the event of a calendar update / delete without `targetRef` (`ambiguity.event`).
    var eventChoice: Ambiguity?
    private var eventCandidates: [EventSummary] = []
    /// `picker.saveNickname` offer after a contact was picked for a word that is not in its name (spec §6.6 AC3).
    struct NicknameOffer: Equatable { let nickname: String; let contactId: String; let contactName: String }
    private(set) var nicknameOffer: NicknameOffer?
    /// What the S18 explainer was shown for (the same capability can be needed to confirm or to read).
    private enum PermissionPurpose { case confirm, readContacts, readEvents }
    private var permissionPurpose: PermissionPurpose = .confirm

    private let engine: TaskEngine
    private let permissions: any PermissionManager
    private let contacts: any ContactsService
    private let calendar: any CalendarService
    private let localData: (any LocalDataRepository)?
    private let system: any SystemService
    private let services: SupportedServices
    private let snoozeMorningHour: Int
    private let catalog: FieldCatalog
    private let now: () -> Date

    init(draftId: UUID, repository: any TaskRepository, engine: TaskEngine, permissions: any PermissionManager,
         contacts: any ContactsService = MockContactsService(),
         calendar: any CalendarService = MockCalendarService(), localData: (any LocalDataRepository)? = nil,
         system: any SystemService = MockSystemService(), services: SupportedServices = .bundled,
         snoozeMorningHour: Int = 8, catalog: FieldCatalog = .mvp, now: @escaping () -> Date = { .now }) {
        self.contacts = contacts
        self.calendar = calendar
        self.localData = localData
        self.system = system
        self.services = services
        self.snoozeMorningHour = snoozeMorningHour
        self.engine = engine
        self.permissions = permissions
        self.catalog = catalog
        self.now = now
        draft = repository.draft(draftId)
        stepId = draft?.currentStep?.id            // reopen at the exact step (D-244, spec §6.10 AC2)
    }

    // MARK: - Rendering

    var step: TaskStep? { draft?.steps.first { $0.id == stepId } }

    /// `step.<kind>.<operation>` (UI_SCREENS §10.1).
    var titleKey: String? { step.map { "step.\($0.kind.rawValue).\($0.operation.rawValue)" } }

    /// 1-based position and count for `StepIndicator` (shown only when > 1 step).
    var stepPosition: (current: Int, total: Int)? {
        guard let draft, let step, draft.steps.count > 1 else { return nil }
        let ordered = draft.steps.sorted { $0.order < $1.order }
        return ((ordered.firstIndex { $0.id == step.id } ?? 0) + 1, ordered.count)
    }

    /// Catalog order; rows only required under a condition that does not hold now are hidden
    /// (e.g. `contactId` / `phoneNumber` when `channel ≠ sms`, `customLabel` unless `label = custom`).
    var visibleFields: [Field] {
        guard let step, let rule = catalog.rule(step.kind, step.operation) else { return [] }
        let conditionalOnly = Set(rule.conditional.flatMap(\.fields)).subtracting(rule.fields)
        let required = Validator.requiredFieldIds(step, catalog: catalog)
        return catalog.fields(step.kind, step.operation).compactMap { spec in
            if conditionalOnly.contains(spec.id) && !required.contains(spec.id) { return nil }
            // TODO(spec): the 🔒 `calendarId` row (calendar name) and the contact photo are not shown yet.
            if spec.id == "calendarId" { return nil }
            // TODO(spec): S04 says `coordinate` → small map; the filled coordinate row is hidden (name + address show it).
            if spec.id == "coordinate", let f = step.field("coordinate"), f.value != nil, f.ambiguity == nil { return nil }
            return step.field(spec.id) ?? Field(id: spec.id, type: spec.type, deviceOnly: spec.deviceOnly)
        }
    }

    // MARK: - Compact layout (D-292)

    /// "Thêm chi tiết" is open.
    var showsDetails = false

    /// Rows shown at once (D-292): required, filled (a `false` switch does not count), needs review or ambiguous, and
    /// the contact row. Calendar `endDate` is folded into the "Thời gian" row of `startDate`.
    var primaryFields: [Field] { visibleFields.filter(isPrimary) }

    /// Everything else, under "Thêm chi tiết".
    var detailFields: [Field] { visibleFields.filter { !isPrimary($0) } }

    private func isPrimary(_ field: Field) -> Bool {
        if isCalendarTime, field.id == "endDate" { return false }
        if field.required || field.needsReview || field.ambiguity != nil || field.type == .contactRef { return true }
        guard let value = field.value, !value.isEmpty else { return false }
        return !(field.type == .bool && value == "false")
    }

    private var isCalendarTime: Bool { step?.kind == .calendarEvent && step?.field("startDate") != nil }

    /// `review.row.time` for the merged calendar start–end row, else `field.<kind>.<id>`.
    func labelKey(_ field: Field) -> String? {
        isCalendarTime && field.id == "startDate" ? "review.row.time" : nil
    }

    /// Summary card (D-292): the main value of the step, bold.
    var summaryTitle: String? {
        guard let step else { return nil }
        for id in ["title", "recipientName", "name", "query", "label"] {
            if let field = step.field(id), let text = displayValue(field), !text.isEmpty { return text }
        }
        return nil
    }

    /// Summary card time line: calendar start–end, reminder due date.
    var summaryTime: String? {
        guard let step else { return nil }
        switch step.kind {
        case .calendarEvent: return step.field("startDate").flatMap(displayValue)
        case .reminder: return step.field("dueDate").flatMap(displayValue)
        default: return nil
        }
    }

    /// "Thứ Năm, 12/11 lúc 09:30–10:30" (same day) or "… lúc 09:30 – Thứ Sáu, 13/11 lúc 10:30".
    private func timeRange(_ step: TaskStep) -> String? {
        let tz = TimeZone(identifier: draft?.timeZoneId ?? "") ?? .current
        guard let start = step.field("startDate")?.value.flatMap(Validator.parseDateTime) else { return nil }
        let allDay = step.field("allDay")?.value == "true"
        if allDay { return "\(FieldFormatter.day(start, timeZone: tz)) · \(UserMessage(key: "calendar.allDay").text)" }
        let from = FieldFormatter.dateTime(start, timeZone: tz)
        guard let end = step.field("endDate")?.value.flatMap(Validator.parseDateTime), end > start else { return from }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal.isDate(start, inSameDayAs: end)
            ? "\(from)–\(FieldFormatter.time(end, timeZone: tz))"
            : "\(from) – \(FieldFormatter.dateTime(end, timeZone: tz))"
    }

    /// 🔒 rows (UI_SCREENS S04): `contactId` → the contact's name; a number taken from Contacts → "•••• 567" (§7.3).
    func displayValue(_ field: Field) -> String? {
        if isCalendarTime, field.id == "startDate", let step { return timeRange(step) }
        if field.type == .contactRef { return field.value == nil ? nil : contactName }
        if field.id == "phoneNumber", let value = field.value, field.source == .device(origin: "contacts") {
            return PhoneNumber.masked(value)
        }
        return FieldFormatter.display(field, timeZoneId: draft?.timeZoneId ?? TimeZone.current.identifier)
    }

    /// Reads the contact name for the S04 row (on appear and after a pick).
    func loadContactName() async {
        guard let id = step?.field("contactId")?.value else { contactName = nil; return }
        contactName = (try? await contacts.contact(id: id))?.displayName ?? pickedNames[id]
    }

    /// The bottom bar (Xác nhận / Sửa / Hủy) is shown before execution; afterwards the result card (1A.11b).
    var showsActionBar: Bool {
        guard let state = step?.state else { return false }
        return state == .draft || state == .needsInfo || state == .awaitingApproval
    }

    var isDelete: Bool { step?.operation == .delete }

    var blocker: ConfirmBlocker? {
        guard let draft, let stepId else { return .notConfirmable }
        return engine.confirmBlocker(stepId: stepId, in: draft)
    }

    var disabledReasonKey: String? {
        if needsEventChoice { return "review.disabled.ambiguity" }      // which event: a choice, not an empty field
        switch blocker {
        case .missing: return "review.disabled.missing"
        case .ambiguity: return "review.disabled.ambiguity"
        case .previousStep: return "review.disabled.previousStep"
        case .notConfirmable, nil: return nil
        }
    }

    /// `approval.mismatch` (§8) or "Bạn vừa sửa thông tin, hãy xác nhận lại." after an edit following approval.
    var banner: UserMessage? {
        guard let step else { return nil }
        if step.errorCode == "approval.mismatch" { return UserMessage(key: "error.approval.mismatch") }
        if step.state == .awaitingApproval, step.history.last?.event == .userEdited,
           step.history.contains(where: { $0.event == .userConfirmed }) {
            return UserMessage(key: "review.editedAfterApproval")
        }
        return nil
    }

    var originalInput: String? {
        guard let text = draft?.originalInput, !text.isEmpty else { return nil }
        return UserMessage(key: "review.originalInput", args: [text]).text
    }

    // MARK: - Result card (UI_SCREENS S04 result strings + "Buttons per state", D-250)

    enum ResultAction: Sendable, Hashable {
        case nextStep(UUID), done, markDone, later, retry, cancel
    }

    struct ResultButton: Sendable, Hashable {
        let title: String                 // already localized
        let action: ResultAction
    }

    /// Texts are resolved from `Localizable.xcstrings` (or the executor's Vietnamese `handoffNote`).
    struct ResultCard: Sendable, Hashable {
        let state: TaskState
        let message: String
        /// Second line: error text (`error.<code>`) for `failed`, the step's own result when more steps follow.
        let detail: String?
        let primary: ResultButton?
        let secondary: ResultButton?
    }

    /// Replaces the bottom bar once the step has left draft / needsInfo / awaitingApproval.
    var resultCard: ResultCard? {
        guard let step, !showsActionBar else { return nil }
        let next = nextStep
        let advance = next.map {
            ResultButton(title: UserMessage(key: "result.nextStep",
                                            args: [UserMessage(key: "step.\($0.kind.rawValue).\($0.operation.rawValue)").text]).text,
                         action: .nextStep($0.id))
        } ?? ResultButton(title: UserMessage(key: "common.done").text, action: .done)
        let markDone = ResultButton(title: UserMessage(key: "result.markDone").text, action: .markDone)
        let later = ResultButton(title: UserMessage(key: "common.later").text, action: .later)

        switch step.state {
        case .processing:
            return ResultCard(state: .processing, message: UserMessage(key: "result.processing").text,
                              detail: nil, primary: nil, secondary: nil)
        case .succeeded:
            // TODO(spec): "Mở trong Lịch" / "Mở trong Lời nhắc" (secondary) need the calendar / reminders services (1C).
            let message = next == nil && draft?.isClosed == true ? UserMessage(key: "result.allDone").text : successMessage(step)
            return ResultCard(state: .succeeded, message: message, detail: next == nil ? nil : successMessage(step),
                              primary: advance, secondary: nil)
        case .handedOff, .prepared:
            return ResultCard(state: step.state, message: handOffMessage(step), detail: nil,
                              primary: markDone, secondary: later)
        case .unknown:
            let canRetry = step.kind == .calendarEvent || step.kind == .reminder          // D-243, D-250
            return ResultCard(state: .unknown, message: UserMessage(key: "result.unknown").text, detail: nil,
                              primary: markDone,
                              secondary: canRetry ? ResultButton(title: UserMessage(key: "common.retry").text, action: .retry) : later)
        case .failed:
            // TODO(spec): `permission.<c>.denied` → Primary `perm.<c>.fallback` + "Tôi đã làm xong" comes with the executors that re-check permission (1C.3, 1C.5).
            return ResultCard(state: .failed, message: UserMessage(key: "result.failed").text, detail: errorMessage(step),
                              primary: ResultButton(title: UserMessage(key: "common.retry").text, action: .retry),
                              secondary: ResultButton(title: UserMessage(key: "common.cancel").text, action: .cancel))
        case .userMarkedDone, .cancelled:
            return ResultCard(state: step.state, message: UserMessage(key: step.state.labelKey).text, detail: nil,
                              primary: advance, secondary: nil)
        case .draft, .needsInfo, .awaitingApproval:
            return nil
        }
    }

    /// The next step by `order` that still needs the user (not closed).
    var nextStep: TaskStep? {
        guard let draft, let step else { return nil }
        return draft.steps.filter { $0.order > step.order && !$0.state.isClosed }.min { $0.order < $1.order }
    }

    private func successMessage(_ step: TaskStep) -> String {
        successKey(step).text
    }

    private func successKey(_ step: TaskStep) -> UserMessage {
        switch (step.kind, step.operation) {
        case (.calendarEvent, .create): UserMessage(key: "result.calendarEvent.created")
        case (.calendarEvent, .update): UserMessage(key: "result.calendarEvent.updated")
        case (.calendarEvent, .delete): UserMessage(key: "result.calendarEvent.deleted")
        case (.reminder, .create): UserMessage(key: "result.reminder.created")
        case (.reminder, .complete): UserMessage(key: "result.reminder.completed")
        case (.reminder, .snooze):
            // The snoozed-to time is recomputed with the executor's rule at the moment the step succeeded.
            UserMessage(key: "result.reminder.snoozed", args: [snoozedTo(step) ?? ""])
        case (.sms, _): UserMessage(key: "result.sms.sent")
        case (.place, .create):
            UserMessage(key: "result.place.saved",
                        args: [step.field("customLabel")?.value
                               ?? step.field("label").flatMap(displayValue) ?? ""])
        case (.ocr, _): UserMessage(key: "result.ocr.confirmed")
        default:
            // TODO(spec): no result text for reminder update / delete; the state label "Đã xong" is shown.
            UserMessage(key: TaskState.succeeded.labelKey)
        }
    }

    func snoozedTo(_ step: TaskStep) -> String? {
        let tz = TimeZone(identifier: draft?.timeZoneId ?? "") ?? .current
        guard let option = step.field("snoozeOption")?.value,
              let date = RemindersExecutor.snoozeDate(option, from: step.stateChangedAt, morningHour: snoozeMorningHour,
                                                      timeZone: tz) else { return nil }
        return FieldFormatter.dateTime(date, timeZone: tz)
    }

    private func handOffMessage(_ step: TaskStep) -> String {
        switch (step.kind, step.operation) {
        case (.call, _): return UserMessage(key: "result.call.handedOff").text
        case (.place, .open):
            let app = step.field("mapsApp").flatMap(displayValue) ?? ""
            return UserMessage(key: "result.directions.handedOff", args: [app]).text
        default:
            // TODO(spec): no result text for other hand-offs (copy path, D-162); the executor's `handoffNote` or
            // the state label is shown.
            if let note = step.handoffNote { return note }
            return UserMessage(key: step.state.labelKey, args: [""]).text
        }
    }

    /// `error.<code>` (D-249); unknown code → `error.generic` (UI_SCREENS §8). Fills `{feature}` / `{app}`.
    func errorMessage(_ step: TaskStep) -> String? {
        guard let code = step.errorCode else { return nil }
        let key = "error.\(code)"
        let text = UserMessage(key: key, args: Self.errorArgs(code: code, kind: step.kind)).text
        return text == key ? UserMessage(key: "error.generic").text : text
    }

    static func errorArgs(code: String, kind: TaskKind) -> [String] {
        if let capability = Capability.allCases.first(where: { code == "permission.\($0.rawValue).denied" }) {
            // TODO(spec): `{feature}` = `perm.<c>.feature` (PROGRESS DOC-37).
            return [UserMessage(key: "perm.\(capability.rawValue).feature").text]
        }
        if code == "eventkit.saveFailed" {
            // TODO(spec): `{app}` names: only `app.phone` is in UI_SCREENS; `app.calendar` / `app.reminders` added.
            return [UserMessage(key: kind == .reminder ? "app.reminders" : "app.calendar").text]
        }
        return []
    }

    // MARK: - Intents

    /// "Sửa": the first field needing review, else the first editable field (P-37).
    func startEdit() {
        let fields = visibleFields.filter { Self.isEditableInS05($0.type) }
        editingFieldId = (fields.first(where: \.needsReview) ?? fields.first)?.id
    }

    /// Row tap → S05, except types set by pickers: a field with an ambiguity or the contact row → S06.
    func tapRow(_ field: Field) async {
        // TODO(spec): `coordinate` / `placeRef` rows open S13 (1C.13).
        if field.ambiguity != nil || field.type == .contactRef {
            await choose(field)
        } else if Self.isEditableInS05(field.type) {
            editingFieldId = field.id
        }
    }

    // MARK: - S06 picker (D-106, D-251)

    /// "Chọn" / contact row: an existing ambiguity opens S06; an unresolved contact row first needs Contacts
    /// (S18 step 0, D-185), then device resolution (1C.9) — which may fill it or bring an ambiguity.
    func choose(_ field: Field) async {
        if field.ambiguity != nil {
            pickingFieldId = field.id
            return
        }
        guard field.type == .contactRef || field.id == "phoneNumber" else { return }
        permissionPurpose = .readContacts
        switch permissions.status(.contacts) {
        case .notDetermined:
            pendingPermission = PendingPermission(capability: .contacts, variant: .explainer)
        case .denied, .restricted, .writeOnly:
            // The iOS contact picker needs no Contacts access: offer it at once instead of a dead end.
            // TODO(spec): S18 denied fallback for contacts is "Nhập số điện thoại"; the system picker is used (fewer taps).
            showsContactPicker = true
        case .granted, .limited:
            await resolveContacts()
        }
    }

    /// S06 bottom actions for a contact choice (1C.9c).
    var canOpenContacts: Bool { picking?.ambiguity.kind == .contact }

    /// Limited access (iOS 18): Apple's search button for the spoken name.
    var limitedQuery: String? {
        guard picking?.ambiguity.kind == .contact, permissions.status(.contacts) == .limited else { return nil }
        return step?.field("recipientName")?.value.map(NameNormalizer.matchKey)
    }

    func openContacts() {
        contactPickerAfterSheet = true
        pickingFieldId = nil
    }

    /// The S06 sheet finished closing (`onDismiss`): now the iOS contact picker can be presented.
    func pickerSheetDismissed() {
        guard contactPickerAfterSheet else { return }
        contactPickerAfterSheet = false
        showsContactPicker = true
    }

    /// A contact shared through `ContactAccessButton`: search again (it may now be the only match).
    func limitedShared() async {
        pickingFieldId = nil
        await resolveContacts()
    }

    /// "Chọn trong danh bạ" result: the picked contact + its numbers (D-251: on device, no quota).
    func pickedFromContacts(_ contact: PickedContact) {
        guard let draft, let stepId else { return }
        let spoken = step?.field("recipientName")?.value
        pickedNames[contact.id] = contact.displayName
        engine.pickContact(id: contact.id, displayName: contact.displayName, phones: contact.phones,
                           stepId: stepId, in: draft)
        contactName = contact.displayName
        offerNickname(spoken: spoken, contactId: contact.id, name: contact.displayName)
        if step?.field("phoneNumber")?.ambiguity != nil { pickingFieldId = "phoneNumber" }
    }

    private func offerNickname(spoken: String?, contactId: String, name: String) {
        guard let spoken, localData != nil,
              !ContactMatcher.contains(ContactRecord(id: contactId, givenName: name, familyName: "", phoneCount: 0),
                                       NameNormalizer.matchKey(spoken)) else { return }
        // "mẹ" → Nguyễn Thị Lan: the word is not part of the name, so remembering it saves the pick next time.
        nicknameOffer = NicknameOffer(nickname: spoken, contactId: contactId, contactName: name)
    }

    /// The S06 field and its ambiguity.
    var picking: (field: Field, ambiguity: Ambiguity)? {
        guard let id = pickingFieldId, let field = step?.field(id), let ambiguity = field.ambiguity else { return nil }
        return (field, ambiguity)
    }

    /// Row tap in S06: resolved on device (D-251), then the contact name / next ambiguity is shown.
    /// `fieldId` is captured when the sheet opens: closing the sheet clears `pickingFieldId` before this task runs
    /// (owner iPhone test 2026-11-11: picks were lost).
    func pick(_ candidate: Candidate, fieldId: String) async {
        guard let draft, let stepId else { return }
        pickingFieldId = nil
        if fieldId == "coordinate" {                                          // S06 place pick (1C.13b)
            engine.pickPlace(candidate, stepId: stepId, in: draft)
            return
        }
        let spoken = step?.field("recipientName")?.value
        await engine.pick(candidate.id, fieldId: fieldId, stepId: stepId, in: draft)
        await loadContactName()
        if fieldId == "contactId", let name = contactName {
            offerNickname(spoken: spoken, contactId: candidate.id, name: name)
        }
        if let next = step?.field("phoneNumber"), next.ambiguity != nil { pickingFieldId = next.id }   // then the number
    }

    /// "Lưu": the nickname is stored on the phone only (spec §6.6 AC3, DATA_MODEL §5) for the next match (§7.2).
    func saveNickname() {
        guard let offer = nicknameOffer else { return }
        localData?.saveNickname(offer.nickname, contactId: offer.contactId)
        nicknameOffer = nil
    }

    func dismissNicknameOffer() { nicknameOffer = nil }

    // MARK: - Event choice (calendar update / delete without `targetRef`)

    /// The step needs the user to say which event (no single match on the spoken day, or no calendar access then).
    var needsEventChoice: Bool {
        guard let step, showsActionBar, step.kind == .calendarEvent, step.targetRef == nil else { return false }
        return step.operation == .update || step.operation == .delete
    }

    /// "Chọn" under `ambiguity.event`: needs calendar read access (S18 step 0), then S06 with the matching events.
    func chooseEvent() async {
        permissionPurpose = .readEvents
        switch permissions.status(.calendar) {
        case .notDetermined: pendingPermission = PendingPermission(capability: .calendar, variant: .explainer)
        case .granted: await loadEventChoice()
        default: pendingPermission = PendingPermission(capability: .calendar, variant: .denied)
        }
    }

    private func loadEventChoice() async {
        guard let step else { return }
        let near = step.field("startDate")?.value.flatMap(Validator.parseDateTime)
        let tz = TimeZone(identifier: draft?.timeZoneId ?? "") ?? .current
        // Wider than the resolver's same-day rule: ±30 days around the spoken date, else the next year.
        // TODO(spec): S06 for events has no window rule; `CalendarService.search` windows are used.
        eventCandidates = (try? await calendar.search(title: step.field("title")?.value, near: near)) ?? []
        eventChoice = Ambiguity(kind: .other, question: UserMessage(key: "ambiguity.event").text,
                                candidates: eventCandidates.map {
                                    Candidate(id: $0.id, title: $0.title,
                                              subtitle: $0.isAllDay ? FieldFormatter.day($0.start, timeZone: tz)
                                                                    : FieldFormatter.dateTime($0.start, timeZone: tz))
                                })
    }

    func pickEvent(_ candidate: Candidate) {
        eventChoice = nil
        guard let draft, let stepId, let event = eventCandidates.first(where: { $0.id == candidate.id }) else { return }
        engine.pickTarget(event, stepId: stepId, in: draft)
    }

    /// S04 appears with a contact / number still to choose → S06 opens by itself (one tap less for the user).
    // TODO(spec): UI_SCREENS S04 shows "Chọn" under the row; opening S06 at once is an owner request (2026-11-11).
    func openPendingPicker() {
        guard showsActionBar, pickingFieldId == nil, pendingPermission == nil, editingFieldId == nil,
              let field = visibleFields.first(where: { ($0.type == .contactRef || $0.id == "phoneNumber" || $0.id == "coordinate")
                                                       && $0.ambiguity != nil && !($0.ambiguity?.candidates.isEmpty ?? true) })
        else { return }
        pickingFieldId = field.id
    }

    /// Same for a calendar update / delete that still needs its event: with read access the list opens by itself
    /// (owner iPhone test 2026-11-11: the card was below the fields and not seen). No access → the card's "Chọn" asks.
    func openPendingEventChoice() async {
        guard needsEventChoice, eventChoice == nil, pendingPermission == nil, permissions.status(.calendar) == .granted
        else { return }
        await loadEventChoice()
        if eventChoice?.candidates.isEmpty == true { eventChoice = nil }   // nothing to pick: keep the card
    }

    private func resolveContacts() async {
        guard let draft else { return }
        await engine.resolveDevice(in: draft)
        await loadContactName()
        if let field = step?.fields.first(where: { ($0.type == .contactRef || $0.id == "phoneNumber") && $0.ambiguity != nil }) {
            pickingFieldId = field.id
        }
    }

    static func isEditableInS05(_ type: FieldType) -> Bool {
        type != .contactRef && type != .placeRef && type != .coordinate
    }

    /// S05 for `editingFieldId`; "Lưu" → `TaskEngine.edit` (D-101, D-104).
    var editor: FieldEditorViewModel? {
        guard let id = editingFieldId, let step, let draft,
              let field = visibleFields.first(where: { $0.id == id }) else { return nil }
        return FieldEditorViewModel(field: field, step: step, timeZoneId: draft.timeZoneId, now: now,
                                    snoozeMorningHour: snoozeMorningHour) { [weak self] value in
            self?.edit(fieldId: id, value: value)
        }
    }

    func edit(fieldId: String, value: String?) {
        guard let draft, let stepId else { return }
        engine.edit(fieldId: fieldId, value: value, stepId: stepId, in: draft)
    }

    /// "Xác nhận". Step 0 (ARCHITECTURE §5.1, D-185): a capability never asked → S18 explainer first;
    /// denied / restricted → S18 denied variant. Otherwise the engine confirms (it re-checks everything).
    func confirm() async {
        guard let step else { return }
        permissionPurpose = .confirm
        if let capability = Capability.required(for: step.kind) {
            switch permissions.status(capability) {
            case .notDetermined:
                pendingPermission = PendingPermission(capability: capability, variant: .explainer)
                return
            case .denied, .restricted:
                pendingPermission = PendingPermission(capability: capability, variant: .denied)
                return
            case .granted, .limited, .writeOnly:
                break
            }
        }
        await execute()
    }

    /// S18 "Cho phép": the system alert, then confirm (or read contacts) when usable; a "no" shows the denied variant.
    func allowPermission() async {
        guard let pending = pendingPermission, pending.variant == .explainer else { return }
        pendingPermission = nil
        let status = await permissions.request(pending.capability)
        if status.isUsable {
            switch permissionPurpose {
            case .readContacts: await resolveContacts()
            case .readEvents: if status == .granted { await loadEventChoice() }
            case .confirm: await execute()
            }
        } else {
            pendingPermission = PendingPermission(capability: pending.capability, variant: .denied)
        }
    }

    /// S18 "Để sau" / "Mở Cài đặt" / swipe down: nothing runs; the step stays `awaitingApproval` (D-100).
    func dismissPermission() {
        pendingPermission = nil
    }

    private func execute() async {
        guard let draft, let stepId else { return }
        if case .needsUI(.composer(let recipients, let body)) = await engine.confirm(stepId: stepId, in: draft) {
            pendingComposer = (recipients, body)
        }
        showCopyGuideIfNeeded()
    }

    /// S07 right after a copy hand-off ("Đã sao chép — dán và gửi trong Zalo"), spec §6.8 AC3.
    private func showCopyGuideIfNeeded() {
        guard let step, step.kind == .sms, step.state == .handedOff,
              let channel = step.field("channel")?.value, channel != "sms",
              let service = services.service(channel) else { return }
        copyGuide = CopyGuide(serviceName: service.name, body: step.field("body")?.value ?? "", steps: service.guideSteps)
    }

    /// S07 "Đã xong": the user says it was sent (`handedOff` → `userMarkedDone`, D-242). Never automatic.
    func copyGuideDone() {
        copyGuide = nil
        perform(.markDone)
    }

    /// S07 "Sao chép lại".
    func copyAgain() async {
        guard let body = copyGuide?.body else { return }
        await system.copy(body)
    }

    /// Composer delegate (or the sheet closed without one = cancelled): `.sent` → succeeded with `msg:sent:<date>`,
    /// `.cancelled` → back to `awaitingApproval` (D-222), `.failed` → failed (ARCHITECTURE §5.3).
    func composerFinished(_ result: ComposerResult) {
        guard pendingComposer != nil, let draft, let stepId else { return }
        pendingComposer = nil
        engine.composerFinished(stepId: stepId, result: result, in: draft)
    }

    /// Result card buttons. `done` / `later` are navigation; the View handles them (`didClose` / pop to Home).
    func perform(_ action: ResultAction) {
        guard let draft, let stepId else { return }
        switch action {
        case .nextStep(let id): self.stepId = id
        case .markDone: engine.markDone(stepId: stepId, in: draft)
        case .retry: engine.retry(stepId: stepId, in: draft)
        case .cancel: engine.cancel(stepId: stepId, in: draft)
        case .later: didClose = true
        case .done: didFinish = true
        }
    }

    /// "Hủy": cancels the step (draft kept, D-104) and leaves the screen.
    func cancel() {
        guard let draft, let stepId else { return }
        engine.cancel(stepId: stepId, in: draft)
        didClose = true
    }
}
