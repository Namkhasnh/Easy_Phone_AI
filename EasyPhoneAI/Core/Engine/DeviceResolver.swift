import Foundation

/// What device resolution found for one step (ARCHITECTURE §5 `DeviceResolver`). Applied by `TaskEngine` (the only
/// writer of steps). 🔒 values (contact ids, numbers, event ids) stay on the device (D-056).
struct DeviceResolution: Sendable, Hashable {
    /// Field id → new value (`source = .device(origin)`).
    var values: [String: String] = [:]
    /// Field id → ambiguity to show on S04 / S06 (never auto-picked, D-106).
    var ambiguities: [String: Ambiguity] = [:]
    /// The existing item for update / delete (calendar event id), when exactly one matches.
    var targetRef: String?
    /// `.device(origin:)` for `values`: "contacts" / "calendar".
    var origin: String = "contacts"

    var isEmpty: Bool { values.isEmpty && ambiguities.isEmpty && targetRef == nil }
}

/// ARCHITECTURE §5: `recipientName` → `ContactsService.match` → 1 match fills `contactId` / `phoneNumber`
/// (`source = .device("contacts")`), else `Ambiguity(.contact)`; skipped when `channel ≠ sms` (D-247). A phone number as
/// recipient fills `phoneNumber` only (D-253). `update` / `delete` → `CalendarService.search` → one match = `targetRef`.
/// Reads only with usable permission; otherwise nothing is resolved and S04 asks later (D-185).
@MainActor final class DeviceResolver {
    private let contacts: any ContactsService
    private let calendar: any CalendarService
    private let permissions: any PermissionManager

    nonisolated init(contacts: any ContactsService, calendar: any CalendarService, permissions: any PermissionManager) {
        self.contacts = contacts
        self.calendar = calendar
        self.permissions = permissions
    }

    func resolve(_ step: TaskStep, timeZoneId: String) async -> DeviceResolution {
        switch (step.kind, step.operation) {
        case (.call, _): return await resolveRecipient(step)
        case (.sms, _):
            guard (step.field("channel")?.value ?? "sms") == "sms" else { return DeviceResolution() }   // D-247
            return await resolveRecipient(step)
        case (.calendarEvent, .update), (.calendarEvent, .delete):
            return await resolveEvent(step, timeZoneId: timeZoneId)
        default:
            // TODO(spec): reminder update / delete / complete / snooze by voice need a reminder search (RemindersService
            // has none in ARCHITECTURE §4.2); they come from S12 with `targetRef` set.
            return DeviceResolution()
        }
    }

    // MARK: - Contacts (call / sms)

    private func resolveRecipient(_ step: TaskStep) async -> DeviceResolution {
        var r = DeviceResolution(origin: "contacts")
        guard let name = step.field("recipientName")?.value, !name.isEmpty,
              step.field("contactId")?.value == nil, step.field("phoneNumber")?.value == nil else { return r }
        if let number = PhoneNumber.normalize(name) {                   // D-253: a number, not a person
            r.values["phoneNumber"] = number
            return r
        }
        guard permissions.status(.contacts).isUsable,
              let matches = try? await contacts.match(name: name) else { return r }
        switch matches.count {
        case 1:
            let match = matches[0]
            r.values["contactId"] = match.id
            await resolveNumber(of: match, name: name, into: &r)
        case 0:
            // TODO(spec): no-match is an empty `.contact` ambiguity; S06 shows `picker.noMatch` + "Chọn trong danh bạ".
            r.ambiguities["contactId"] = Ambiguity(kind: .contact, question: UserMessage(key: "picker.noMatch").text,
                                                   candidates: [])
        default:
            var candidates: [Candidate] = []
            for match in matches {
                let phones = (try? await contacts.phoneNumbers(contactId: match.id)) ?? []
                candidates.append(Candidate(id: match.id, title: match.displayName,
                                            subtitle: phones.count == 1 ? PhoneNumber.masked(phones[0].number) : nil,
                                            imageRef: match.id))
            }
            let key = step.kind == .sms ? "ambiguity.contact.sms" : "ambiguity.contact.call"
            r.ambiguities["contactId"] = Ambiguity(kind: .contact, question: UserMessage(key: key, args: [name]).text,
                                                   candidates: candidates)
        }
        return r
    }

    /// After the user picked a contact on S06: its number (one → filled, several → `.phoneNumber` ambiguity).
    func numberResolution(contactId: String, name: String) async -> DeviceResolution {
        var r = DeviceResolution(origin: "contacts")
        let match = (try? await contacts.contact(id: contactId))
            ?? ContactMatch(id: contactId, displayName: name, phoneCount: 0)
        await resolveNumber(of: match, name: match.displayName, into: &r)
        return r
    }

    /// One number → filled; several → `.phoneNumber` ambiguity (S06 rows "{label}: •••• 567"); none → left empty.
    func resolveNumber(of match: ContactMatch, name: String, into r: inout DeviceResolution) async {
        let phones = ((try? await contacts.phoneNumbers(contactId: match.id)) ?? [])
            .compactMap { entry in PhoneNumber.normalize(entry.number).map { (entry.label, $0) } }
        switch phones.count {
        case 1: r.values["phoneNumber"] = phones[0].1
        case 0: break   // TODO(spec): a contact without a usable number has no text; the phone row stays "Chưa có".
        default:
            r.ambiguities["phoneNumber"] = Ambiguity(
                kind: .phoneNumber,
                question: UserMessage(key: "ambiguity.phoneNumber", args: [match.viaNickname ? match.displayName : name]).text,
                candidates: phones.map { label, number in
                    Candidate(id: number,
                              title: label.map { UserMessage(key: "picker.phoneLabel",
                                                             args: [$0, String(number.suffix(3))]).text }
                                  ?? PhoneNumber.masked(number))
                })
        }
    }

    // MARK: - Calendar (update / delete)

    private func resolveEvent(_ step: TaskStep, timeZoneId: String) async -> DeviceResolution {
        var r = DeviceResolution(origin: "calendar")
        guard step.targetRef == nil, permissions.status(.calendar) == .granted else { return r }
        let title = step.field("title")?.value
        let near = step.field("startDate")?.value.flatMap(Validator.parseDateTime)
        guard title != nil || near != nil, var found = try? await calendar.search(title: title, near: near) else { return r }
        // A spoken day ("thứ Sáu") limits the search to that day in the draft time zone.
        // TODO(spec): AI_PROMPTS E7 gives the day at 00:00 as a hint; only same-day events are candidates then.
        if let near {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: timeZoneId) ?? .current
            found = found.filter { cal.isDate($0.start, inSameDayAs: near) }
        }
        // D-106: exactly one match only; several / none → S04 "Chọn lịch hẹn" → S06 (1C.9b).
        guard found.count == 1 else { return r }
        let event = found[0]
        r.targetRef = event.id
        // S04 shows the real event, not the AI's hints (title, times), so the user confirms what will change.
        for field in DraftBuilder.step(from: event, operation: step.operation, timeZoneId: timeZoneId).fields
        where field.value != nil && step.field(field.id)?.source != .user {
            if step.operation == .delete || step.field(field.id)?.value == nil { r.values[field.id] = field.value }
        }
        return r
    }
}
