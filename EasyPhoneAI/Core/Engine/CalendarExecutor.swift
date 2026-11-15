import Foundation
import os

/// calendarEvent create / update / delete (ARCHITECTURE §5.1 steps 4–6, spec §6.4 AC3, DATA_MODEL §3.5).
/// 4. permission re-check → 5. idempotency (evidence, then `easyphone:<stepId>`, D-105 / D-225) → 6. save + re-read.
@MainActor final class CalendarExecutor: StepExecutor {
    private let calendar: any CalendarService
    private let permissions: any PermissionManager
    private let logger = Logger(subsystem: "vn.namkhanh.easyphone", category: "calendarExecutor")

    nonisolated init(calendar: any CalendarService, permissions: any PermissionManager) {
        self.calendar = calendar
        self.permissions = permissions
    }

    func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome {
        // 4. Not usable (incl. notDetermined) → `permission.calendar.denied` (D-249); S04 offers the fallback.
        let access = permissions.status(.calendar)
        guard access.isUsable else { return .failed(code: ServiceError.permissionDenied(.calendar).code) }
        let canRead = access == .granted
        do {
            switch step.operation {
            case .create: return try await create(step, canRead: canRead)
            case .update: return try await update(step, canRead: canRead)
            case .delete: return try await delete(step, canRead: canRead)
            default: return .failed(code: "unsupported")
            }
        } catch let error as ServiceError {
            logger.info("calendar \(step.operation.rawValue, privacy: .public) failed: \(error.code, privacy: .public)")
            return .failed(code: error == .notFound ? "eventkit.saveFailed" : error.code)
        } catch {
            return .failed(code: "eventkit.saveFailed")
        }
    }

    // MARK: - Operations

    private func create(_ step: TaskStep, canRead: Bool) async throws -> ExecutionOutcome {
        guard let input = Self.input(from: step) else { return .failed(code: "eventkit.saveFailed") }
        let tag = StepTag.make(step.id)
        if canRead {
            // 5. A retry after a crash / lost result must not create a second event (D-105).
            if let id = Self.eventId(step.resultEvidence), try await calendar.find(identifier: id) != nil {
                return .verified(evidence: Self.evidence(id))
            }
            if let found = try await calendar.find(stepTag: tag) {
                return .verified(evidence: Self.evidence(found.id))
            }
        }
        let id = try await calendar.save(input, stepTag: tag, existing: nil)
        return try await verify(id, input, canRead: canRead)
    }

    private func update(_ step: TaskStep, canRead: Bool) async throws -> ExecutionOutcome {
        // Write-only access cannot read the event to change (D-185 explains; Settings to fix).
        guard canRead else { return .failed(code: ServiceError.permissionDenied(.calendar).code) }
        guard let target = step.targetRef, let input = Self.input(from: step) else {
            return .failed(code: "eventkit.saveFailed")
        }
        // Saving the same values twice is harmless, so an update needs no lookup before writing.
        let id = try await calendar.save(input, stepTag: StepTag.make(step.id), existing: target)
        return try await verify(id, input, canRead: true)
    }

    private func delete(_ step: TaskStep, canRead: Bool) async throws -> ExecutionOutcome {
        guard canRead else { return .failed(code: ServiceError.permissionDenied(.calendar).code) }
        guard let target = step.targetRef else { return .failed(code: "eventkit.saveFailed") }
        // 5. Already gone (e.g. retry after the delete went through) → done, no second call.
        if try await calendar.find(identifier: target) != nil {
            try await calendar.delete(identifier: target)
        }
        // 6. Re-read: the identifier must no longer be found (DATA_MODEL §3.5).
        guard try await calendar.find(identifier: target) == nil else { return .failed(code: "eventkit.saveFailed") }
        return .verified(evidence: "ek:deleted:\(target)")
    }

    /// 6. Re-read by identifier and compare the fields that matter (spec §6.4 AC3, DATA_MODEL §3.5).
    private func verify(_ id: String, _ input: EventInput, canRead: Bool) async throws -> ExecutionOutcome {
        guard canRead else {
            // TODO(spec): write-only access cannot re-read (ARCHITECTURE §5.1 step 6); EventKit's committed save and
            // its identifier are taken as the evidence (PROGRESS DOC-38).
            return .verified(evidence: Self.evidence(id))
        }
        guard let saved = try await calendar.find(identifier: id), Self.matches(saved, input) else {
            return .failed(code: "eventkit.saveFailed")
        }
        return .verified(evidence: Self.evidence(id))
    }

    // MARK: - Launch verification (D-125, DATA_MODEL §3.5)

    /// create: stored evidence or `easyphone:<stepId>` found; update: target exists and fields match; delete: target
    /// gone. Needs full access (write-only cannot read) — else nil, the step stays `unknown`.
    func evidenceOnLaunch(_ step: TaskStep) async -> String? {
        guard permissions.status(.calendar) == .granted else { return nil }
        do {
            switch step.operation {
            case .create:
                if let id = Self.eventId(step.resultEvidence), try await calendar.find(identifier: id) != nil {
                    return Self.evidence(id)
                }
                return try await calendar.find(stepTag: StepTag.make(step.id)).map { Self.evidence($0.id) }
            case .update:
                guard let target = step.targetRef, let input = Self.input(from: step),
                      let saved = try await calendar.find(identifier: target), Self.matches(saved, input) else { return nil }
                return Self.evidence(saved.id)
            case .delete:
                guard let target = step.targetRef, try await calendar.find(identifier: target) == nil else { return nil }
                return "ek:deleted:\(target)"
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    // MARK: - Pure helpers

    static func evidence(_ id: String) -> String { "ek:event:\(id)" }

    static func eventId(_ evidence: String?) -> String? {
        guard let evidence, evidence.hasPrefix("ek:event:") else { return nil }
        return String(evidence.dropFirst("ek:event:".count))
    }

    /// Step fields → `EventInput` (DATA_MODEL §4). `endDate` empty → start + 60 min (§4 default).
    static func input(from step: TaskStep) -> EventInput? {
        func value(_ id: String) -> String? {
            guard let v = step.field(id)?.value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        guard let title = value("title"), let start = value("startDate").flatMap(Validator.parseDateTime) else {
            return nil
        }
        let end = value("endDate").flatMap(Validator.parseDateTime) ?? start + 60 * 60
        return EventInput(title: title, start: start, end: end, isAllDay: value("allDay") == "true",
                          location: value("location"), notes: value("notes"),
                          alertMinutesBefore: value("alertMinutesBefore").flatMap { Int($0) },
                          calendarId: value("calendarId"))
    }

    static func matches(_ saved: EventSummary, _ input: EventInput) -> Bool {
        // All-day events are stored by EventKit at day boundaries, so only the title and day are compared.
        if input.isAllDay {
            return saved.title == input.title && Calendar.current.isDate(saved.start, inSameDayAs: input.start)
        }
        return saved.title == input.title && saved.start == input.start && saved.end == input.end
    }
}
