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
/// (`source = .device("contacts")`), else `Ambiguity(.contact)`; skipped for copy-only channels (D-247; Zalo resolves, D-297). A phone number as
/// recipient fills `phoneNumber` only (D-253). `update` / `delete` → `CalendarService.search` → one match = `targetRef`.
/// Reads only with usable permission; otherwise nothing is resolved and S04 asks later (D-185).
@MainActor final class DeviceResolver {
    /// `sms.channel` values that look up the contact + number (D-247, D-297).
    static let contactChannels: Set<String> = ["sms", "zalo"]

    private let contacts: any ContactsService
    private let calendar: any CalendarService
    private let permissions: any PermissionManager
    private let places: (any PlacesService)?
    private let savedPlaces: (@MainActor () -> [SavedPlace])?

    nonisolated init(contacts: any ContactsService, calendar: any CalendarService, permissions: any PermissionManager,
                     places: (any PlacesService)? = nil, savedPlaces: (@MainActor () -> [SavedPlace])? = nil) {
        self.contacts = contacts
        self.calendar = calendar
        self.permissions = permissions
        self.places = places
        self.savedPlaces = savedPlaces
    }

    func resolve(_ step: TaskStep, timeZoneId: String) async -> DeviceResolution {
        switch (step.kind, step.operation) {
        case (.call, _): return await resolveRecipient(step)
        case (.sms, _):
            // D-247: copy-only channels need no contact; D-297: Zalo opens the person's chat, so it does.
            guard Self.contactChannels.contains(step.field("channel")?.value ?? "sms") else { return DeviceResolution() }
            return await resolveRecipient(step)
        case (.calendarEvent, .update), (.calendarEvent, .delete):
            return await resolveEvent(step, timeZoneId: timeZoneId)
        case (.place, .open), (.place, .create):
            return await resolvePlace(step)
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
        let phones = (try? await contacts.phoneNumbers(contactId: match.id)) ?? []
        Self.addNumber(from: phones, askingFor: match.viaNickname ? match.displayName : name, into: &r)
    }

    /// Pure part of the number rule, also used for a contact picked in the iOS contact picker (1C.9c: the app may
    /// have no Contacts access then, the picker hands over that one contact's numbers).
    static func addNumber(from entries: [PhoneEntry], askingFor name: String, into r: inout DeviceResolution) {
        // The same number written twice ("034 7676916" + "+84 34 7676916") is ONE choice, not an ambiguity (§7.3).
        var seen = Set<String>()
        let phones = entries
            .compactMap { entry in PhoneNumber.normalize(entry.number).map { (entry.label?.isEmpty == false ? entry.label : nil, $0) } }
            .filter { seen.insert($0.1).inserted }
        switch phones.count {
        case 1: r.values["phoneNumber"] = phones[0].1
        case 0: break   // TODO(spec): a contact without a usable number has no text; the phone row stays "Chưa có".
        default:
            r.ambiguities["phoneNumber"] = Ambiguity(
                kind: .phoneNumber,
                question: UserMessage(key: "ambiguity.phoneNumber", args: [name]).text,
                candidates: phones.map { label, number in
                    Candidate(id: number,
                              title: label.map { UserMessage(key: "picker.phoneLabel",
                                                             args: [$0, String(number.suffix(3))]).text }
                                  ?? PhoneNumber.masked(number))
                })
        }
    }

    // MARK: - Places (directions / save)

    /// AI_PROMPTS: "về nhà" → `query = home`, "chỗ làm" → `work`, a custom label → its text. A saved place fills the
    /// destination (`.device("savedPlace")`); else `MKLocalSearch`: one result fills it, several → `.place` ambiguity
    /// on `coordinate` (S06, D-106). Search needs no permission (location is optional).
    private func resolvePlace(_ step: TaskStep) async -> DeviceResolution {
        var r = DeviceResolution(origin: "savedPlace")
        guard step.field("coordinate")?.value == nil, let query = step.field("query")?.value, !query.isEmpty else { return r }
        let key = NameNormalizer.normalize(query)
        if let saved = savedPlaces?().first(where: {
            $0.label == key || ($0.customLabel.map(NameNormalizer.normalize) == key && $0.label == "custom")
        }) {
            r.values = Self.placeValues(name: saved.name, address: saved.address,
                                        coordinate: Coordinate(latitude: saved.latitude, longitude: saved.longitude))
            return r
        }
        r.origin = "maps"
        guard let places, let found = try? await places.search(query, near: nil) else { return r }
        switch found.count {
        case 0: break    // TODO(spec): no place found has no S04 text; the destination rows stay "Chưa có".
        case 1: r.values = Self.placeValues(name: found[0].name, address: found[0].address, coordinate: found[0].coordinate)
        default:
            r.ambiguities["coordinate"] = Ambiguity(
                kind: .place, question: UserMessage(key: "ambiguity.place").text,
                // TODO(spec): S06 shows at most 8 places (no limit in the docs).
                candidates: found.prefix(8).map { Candidate(id: $0.coordinate.encoded, title: $0.name, subtitle: $0.address) })
        }
        return r
    }

    static func placeValues(name: String, address: String, coordinate: Coordinate) -> [String: String] {
        ["name": name, "address": address, "coordinate": coordinate.encoded]
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
        return Self.resolution(for: found[0], step: step, timeZoneId: timeZoneId)
    }

    /// `targetRef` = the event; S04 shows the real event, not the AI's hints, so the user confirms what will change:
    /// delete → every field from the event, update → only fields still empty (the AI values are the new ones).
    static func resolution(for event: EventSummary, step: TaskStep, timeZoneId: String) -> DeviceResolution {
        var r = DeviceResolution(origin: "calendar")
        r.targetRef = event.id
        for field in DraftBuilder.step(from: event, operation: step.operation, timeZoneId: timeZoneId).fields
        where field.value != nil && step.field(field.id)?.source != .user {
            if step.operation == .delete || step.field(field.id)?.value == nil { r.values[field.id] = field.value }
        }
        return r
    }
}
