import Foundation
import Observation

/// S12 Reminders (UI_SCREENS S12, spec §6.5). "Complete" is the only one-tap mutation, with "Hoàn tác" (D-107, D-248);
/// everything else goes through S04. Reading needs full reminders access: step 0 → S18 (D-185).
@Observable @MainActor final class RemindersViewModel {
    struct Row: Identifiable, Hashable {
        let id: String
        let title: String
        let due: String?
    }

    struct Section: Identifiable, Hashable {
        enum Kind: String { case overdue, upcoming }
        let kind: Kind
        let rows: [Row]
        var id: Kind { kind }
        var titleKey: String { "reminders.\(kind.rawValue)" }
    }

    private(set) var sections: [Section] = []
    private(set) var loaded = false
    var pendingPermission: PendingPermission?
    var toast: ToastModel?
    /// Set by "Thêm lời nhắc": the View opens S03 in typing mode for this draft.
    private(set) var newDraftId: UUID?
    /// Ids being completed right now (the circle shows `checkmark.circle.fill` at once).
    private(set) var completing: Set<String> = []

    private var items: [ReminderSummary] = []
    private let reminders: any RemindersService
    private let permissions: any PermissionManager
    private let repository: any TaskRepository
    private let engine: TaskEngine
    private let now: () -> Date
    private let timeZone: TimeZone

    init(reminders: any RemindersService, permissions: any PermissionManager, repository: any TaskRepository,
         engine: TaskEngine, now: @escaping () -> Date = { .now }, timeZone: TimeZone = .current) {
        self.reminders = reminders
        self.permissions = permissions
        self.repository = repository
        self.engine = engine
        self.now = now
        self.timeZone = timeZone
    }

    var isEmpty: Bool { loaded && sections.isEmpty }

    func load() async {
        switch permissions.status(.reminders) {
        case .notDetermined:
            pendingPermission = PendingPermission(capability: .reminders, variant: .explainer)
            return
        case .granted:
            break
        default:
            pendingPermission = PendingPermission(capability: .reminders, variant: .denied)
            loaded = true
            return
        }
        do {
            // TODO(spec): S12 does not say whether recurring reminders are listed; they are hidden (one-time only, §6.5).
            items = try await reminders.incomplete().filter { !$0.isRecurring }
        } catch {
            // TODO(spec): S12 has no load-error text; the empty state is shown.
            items = []
        }
        rebuild()
        loaded = true
    }

    func allowPermission() async {
        guard pendingPermission?.variant == .explainer else { return }
        pendingPermission = nil
        if await permissions.request(.reminders) == .granted {
            await load()
        } else {
            pendingPermission = PendingPermission(capability: .reminders, variant: .denied)
            loaded = true
        }
    }

    func dismissPermission() {
        pendingPermission = nil
        loaded = true
    }

    // MARK: - One-tap complete + undo (D-107, D-248)

    /// The circle: a `reminder/complete` step with `completed = true`, confirmed by this tap (no S04).
    func complete(_ rowId: String) async {
        guard let item = items.first(where: { $0.id == rowId }), !completing.contains(rowId) else { return }
        completing.insert(rowId)
        defer { completing.remove(rowId) }
        let step = await runComplete(item, done: true)
        if step?.state == .succeeded {
            items.removeAll { $0.id == rowId }
            rebuild()
            toast = ToastModel(message: UserMessage(key: "reminders.completed.toast")) { [weak self] in
                Task { await self?.undo(item) }
            }
        } else {
            toast = ToastModel(message: failure(step))
        }
    }

    /// "Hoàn tác": another one-tap `reminder/complete` with `completed = false` on the same reminder (D-248).
    func undo(_ item: ReminderSummary) async {
        let step = await runComplete(item, done: false)
        if step?.state == .succeeded {
            await load()
        } else {
            toast = ToastModel(message: failure(step))
        }
    }

    private func runComplete(_ item: ReminderSummary, done: Bool) async -> TaskStep? {
        guard let draft = engine.startDraft(from: item, operation: .complete,
                                            values: ["completed": done ? "true" : "false"],
                                            timeZoneId: timeZone.identifier),
              let step = draft.steps.first else { return nil }
        // The tap is the confirmation (DATA_MODEL §1.4: built in awaitingApproval, the tap emits userConfirmed).
        guard case .finished = await engine.confirm(stepId: step.id, in: draft) else { return nil }
        return draft.steps.first
    }

    /// The step's `error.<code>` text, else `result.failed`.
    // TODO(spec): S12 has no text for a failed one-tap complete; a toast with the S04 error text is used.
    private func failure(_ step: TaskStep?) -> UserMessage {
        guard let code = step?.errorCode else { return UserMessage(key: "result.failed") }
        let message = UserMessage(key: "error.\(code)", args: ReviewViewModel.errorArgs(code: code, kind: .reminder))
        return message.text == message.key ? UserMessage(key: "error.generic") : message
    }

    // MARK: - Add

    /// "Thêm lời nhắc" → S03 typing mode (same as S11 "Thêm lịch hẹn").
    func addReminder() {
        let draft = TaskDraft(inputMode: .text, originalInput: "")
        repository.save(draft)
        newDraftId = draft.id
    }

    func didOpenNewDraft() { newDraftId = nil }

    // MARK: - Rows

    private func rebuild() {
        let current = now()
        let overdue = items.filter { ($0.dueDate ?? .distantFuture) < current }
        let upcoming = items.filter { ($0.dueDate ?? .distantFuture) >= current }
        sections = [Section(kind: .overdue, rows: overdue.map(row)), Section(kind: .upcoming, rows: upcoming.map(row))]
            .filter { !$0.rows.isEmpty }
    }

    private func row(_ item: ReminderSummary) -> Row {
        Row(id: item.id, title: item.title, due: item.dueDate.map { FieldFormatter.dateTime($0, timeZone: timeZone) })
    }
}
