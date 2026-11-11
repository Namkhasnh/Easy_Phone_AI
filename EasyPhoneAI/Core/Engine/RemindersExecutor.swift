import Foundation
import os

/// reminder create / update / delete / complete / snooze (ARCHITECTURE §5.1 steps 4–6, spec §6.5, D-248,
/// DATA_MODEL §3.5 evidence `ek:reminder:<calendarItemIdentifier>`).
@MainActor final class RemindersExecutor: StepExecutor {
    private let reminders: any RemindersService
    private let permissions: any PermissionManager
    private let now: @MainActor () -> Date
    /// `AppSettings.snoozeMorningHour` (S15) for "sáng mai".
    private let morningHour: @MainActor () -> Int
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "remindersExecutor")

    nonisolated init(reminders: any RemindersService, permissions: any PermissionManager,
                     now: @escaping @MainActor () -> Date = { .now },
                     morningHour: @escaping @MainActor () -> Int = { 8 }) {
        self.reminders = reminders
        self.permissions = permissions
        self.now = now
        self.morningHour = morningHour
    }

    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome {
        // 4. Reminders have no write-only mode: anything but full access → `permission.reminders.denied` (D-249).
        let access = permissions.status(.reminders)
        guard access == .granted else {
            logger.notice("reminders not usable at execute: \(access.rawValue, privacy: .public)")
            return .failed(code: ServiceError.permissionDenied(.reminders).code)
        }
        do {
            switch step.operation {
            case .create: return try await create(step)
            case .update: return try await update(step)
            case .delete: return try await delete(step)
            case .complete: return try await complete(step)
            case .snooze: return try await snooze(step, tz: TimeZone(identifier: draft.timeZoneId) ?? .current)
            default: return .failed(code: "unsupported")
            }
        } catch let error as ServiceError {
            logger.info("reminder \(step.operation.rawValue, privacy: .public) failed: \(error.code, privacy: .public)")
            return .failed(code: error == .notFound ? "eventkit.saveFailed" : error.code)
        } catch {
            return .failed(code: "eventkit.saveFailed")
        }
    }

    // MARK: - Operations

    private func create(_ step: TaskStep) async throws -> ExecutionOutcome {
        guard let input = Self.input(from: step) else { return .failed(code: "eventkit.saveFailed") }
        let tag = StepTag.make(step.id)
        // 5. Idempotency (D-105): stored evidence, then the `easyphone:<stepId>` tag.
        if let id = Self.reminderId(step.resultEvidence), try await reminders.find(identifier: id) != nil {
            return .verified(evidence: Self.evidence(id))
        }
        if let found = try await reminders.find(stepTag: tag) { return .verified(evidence: Self.evidence(found.id)) }
        let id = try await reminders.save(input, stepTag: tag, existing: nil)
        return try await verify(id) { $0.title == input.title && $0.dueDate == input.dueDate }
    }

    private func update(_ step: TaskStep) async throws -> ExecutionOutcome {
        guard let target = step.targetRef, let input = Self.input(from: step) else { return .failed(code: "eventkit.saveFailed") }
        let id = try await reminders.save(input, stepTag: StepTag.make(step.id), existing: target)
        return try await verify(id) { $0.title == input.title && $0.dueDate == input.dueDate }
    }

    private func delete(_ step: TaskStep) async throws -> ExecutionOutcome {
        guard let target = step.targetRef else { return .failed(code: "eventkit.saveFailed") }
        if try await reminders.find(identifier: target) != nil {             // already gone → no second call
            try await reminders.delete(identifier: target)
        }
        guard try await reminders.find(identifier: target) == nil else { return .failed(code: "eventkit.saveFailed") }
        // TODO(spec): DATA_MODEL §3.5 gives `ek:reminder:<id>` for every reminder op, also delete (calendar uses `ek:deleted:`).
        return .verified(evidence: Self.evidence(target))
    }

    /// D-248: `completed = "true"` marks done, `"false"` is "Hoàn tác". Setting the same value twice is harmless.
    private func complete(_ step: TaskStep) async throws -> ExecutionOutcome {
        guard let target = step.targetRef, let raw = step.field("completed")?.value, raw == "true" || raw == "false" else {
            return .failed(code: "eventkit.saveFailed")
        }
        let done = raw == "true"
        try await reminders.setCompleted(target, done)
        return try await verify(target) { $0.isCompleted == done }          // §3.5: isCompleted == completed
    }

    private func snooze(_ step: TaskStep, tz: TimeZone) async throws -> ExecutionOutcome {
        guard let target = step.targetRef, let option = step.field("snoozeOption")?.value,
              let date = Self.snoozeDate(option, from: now(), morningHour: morningHour(), timeZone: tz) else {
            return .failed(code: "eventkit.saveFailed")
        }
        try await reminders.snooze(target, to: date)
        return try await verify(target) { $0.dueDate == date }
    }

    /// 6. Re-read by identifier and check the change (DATA_MODEL §3.5).
    private func verify(_ id: String, _ check: (ReminderSummary) -> Bool) async throws -> ExecutionOutcome {
        guard let saved = try await reminders.find(identifier: id), check(saved) else {
            return .failed(code: "eventkit.saveFailed")
        }
        return .verified(evidence: Self.evidence(id))
    }

    // MARK: - Pure helpers

    static func evidence(_ id: String) -> String { "ek:reminder:\(id)" }

    static func reminderId(_ evidence: String?) -> String? {
        guard let evidence, evidence.hasPrefix("ek:reminder:") else { return nil }
        return String(evidence.dropFirst("ek:reminder:".count))
    }

    static func input(from step: TaskStep) -> ReminderInput? {
        func value(_ id: String) -> String? {
            guard let v = step.field(id)?.value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        guard let title = value("title"), let due = value("dueDate").flatMap(Validator.parseDateTime) else { return nil }
        return ReminderInput(title: title, dueDate: due, notes: value("notes"))
    }

    /// `snoozeOption` → new due date (spec §6.5 AC2): `min15` / `hour1` from now, `tomorrowMorning` = tomorrow at
    /// `snoozeMorningHour` in the draft time zone. Seconds are dropped so the alarm lands on a whole minute.
    // TODO(spec): "15 phút / 1 tiếng" count from the tap, not from the old due date (spec §6.5 AC2 is silent).
    static func snoozeDate(_ option: String, from now: Date, morningHour: Int, timeZone: TimeZone) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let wholeMinute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        switch option {
        case "min15": return wholeMinute + 15 * 60
        case "hour1": return wholeMinute + 60 * 60
        case "tomorrowMorning":
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) else { return nil }
            return cal.date(bySettingHour: morningHour, minute: 0, second: 0, of: tomorrow)
        default: return nil
        }
    }
}
