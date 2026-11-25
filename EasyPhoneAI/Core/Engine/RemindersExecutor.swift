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
            case .create: return try await create(step, timeZoneId: draft.timeZoneId)
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

    private func create(_ step: TaskStep, timeZoneId: String) async throws -> ExecutionOutcome {
        guard let input = Self.input(from: step) else { return .failed(code: "eventkit.saveFailed") }
        let tag = StepTag.make(step.id)
        // 5. Idempotency (D-105): stored evidence, then the `easyphone:<stepId>` tag.
        if let id = Self.reminderId(step.resultEvidence), try await reminders.find(identifier: id) != nil {
            return .verified(evidence: Self.evidence(id))
        }
        let outcome: ExecutionOutcome
        if let found = try await reminders.find(stepTag: tag) {
            outcome = .verified(evidence: Self.evidence(found.id))
        } else {
            let id = try await reminders.save(input, stepTag: tag, existing: nil)
            outcome = try await verify(id) { $0.title == input.title && $0.dueDate == input.dueDate }
        }
        guard case .verified = outcome else { return outcome }
        // 4L.5 (D-331): the rest of a lunar yearly / monthly series, one reminder each (looked up first, D-105).
        _ = try await write(LunarSeries.following(step, timeZoneId: timeZoneId), input: input, of: step)
        return outcome
    }

    /// Writes the series items not found by tag. Returns how many were written.
    private func write(_ items: [LunarSeries.Item], input: ReminderInput, of step: TaskStep) async throws -> Int {
        var written = 0
        for item in items {
            let itemTag = LunarSeries.tag(step.id, item.suffix)
            if try await reminders.find(stepTag: itemTag) != nil { continue }
            var next = input
            next.dueDate = item.start
            _ = try await reminders.save(next, stepTag: itemTag, existing: nil)
            written += 1
        }
        return written
    }

    /// 4L.6 (D-331): the next 12 months of a lunar series, after the newest block end still in Reminders (done ones
    /// count). None left (deleted) → nothing.
    func extendSeries(_ step: TaskStep, draft: TaskDraft, now: Date) async -> Int {
        guard permissions.status(.reminders) == .granted, let input = Self.input(from: step),
              let plan = LunarSeries.extensionPlan(step, timeZoneId: draft.timeZoneId, now: now) else { return 0 }
        do {
            // Already extended (the newest item exists) → no more lookups.
            if let last = plan.items.last, try await reminders.find(stepTag: LunarSeries.tag(step.id, last.suffix)) != nil {
                return 0
            }
            for end in plan.ends {
                guard try await reminders.find(stepTag: LunarSeries.tag(step.id, end.suffix)) != nil else { continue }
                return try await write(Array(plan.items.drop { $0.start <= end.start }), input: input, of: step)
            }
        } catch {
            logger.info("lunar series extension failed")
        }
        return 0
    }

    private func update(_ step: TaskStep) async throws -> ExecutionOutcome {
        guard let target = step.targetRef, let input = Self.input(from: step),
              let current = try await reminders.find(identifier: target) else { return .failed(code: "eventkit.saveFailed") }
        // 4L.5 (D-331): the other open reminders of a lunar series keep their own due date and take the rest.
        // The original tag is kept so the create step and the series still find them (D-105).
        let id = try await reminders.save(input, stepTag: current.stepTag ?? StepTag.make(step.id), existing: target)
        for member in try await reminders.series(of: current) where member.id != target {
            var each = input
            each.dueDate = member.dueDate ?? input.dueDate
            _ = try await reminders.save(each, stepTag: member.stepTag ?? StepTag.make(step.id), existing: member.id)
        }
        return try await verify(id) { $0.title == input.title && $0.dueDate == input.dueDate }
    }

    private func delete(_ step: TaskStep) async throws -> ExecutionOutcome {
        guard let target = step.targetRef else { return .failed(code: "eventkit.saveFailed") }
        if let current = try await reminders.find(identifier: target) {      // already gone → no second call
            // 4L.5 (D-331): the open reminders of the lunar series go too; the target last (a retry finds the rest).
            for member in try await reminders.series(of: current) where member.id != target {
                try await reminders.delete(identifier: member.id)
            }
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

    // MARK: - Launch verification (D-125, DATA_MODEL §3.5)

    /// create: evidence / `easyphone:<stepId>` found; update: title + due match; delete: gone; complete:
    /// `isCompleted == completed`. Without full access → nil (stays `unknown`).
    // TODO(spec): snooze cannot be verified on launch — the target date was computed from "now" at execution time.
    func evidenceOnLaunch(_ step: TaskStep) async -> String? {
        guard permissions.status(.reminders) == .granted else { return nil }
        do {
            switch step.operation {
            case .create:
                if let id = Self.reminderId(step.resultEvidence), try await reminders.find(identifier: id) != nil {
                    return Self.evidence(id)
                }
                return try await reminders.find(stepTag: StepTag.make(step.id)).map { Self.evidence($0.id) }
            case .update:
                guard let target = step.targetRef, let input = Self.input(from: step),
                      let saved = try await reminders.find(identifier: target),
                      saved.title == input.title, saved.dueDate == input.dueDate else { return nil }
                return Self.evidence(saved.id)
            case .delete:
                guard let target = step.targetRef, try await reminders.find(identifier: target) == nil else { return nil }
                return Self.evidence(target)
            case .complete:
                guard let target = step.targetRef, let raw = step.field("completed")?.value,
                      let saved = try await reminders.find(identifier: target),
                      saved.isCompleted == (raw == "true") else { return nil }
                return Self.evidence(target)
            default:
                return nil
            }
        } catch {
            return nil
        }
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
