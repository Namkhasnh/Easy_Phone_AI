# EasyPhone AI — DATA_MODEL.md

> Audience: an AI coding agent (Claude Code) working in Xcode on macOS + the FastAPI backend.
> Hierarchy (D-279): `DECISIONS.md` → `EasyPhone-AI-Spec.md` → **this file** → `API_CONTRACT.md` → … This file never re-decides
> anything; it makes the model concrete. Conflict → the higher doc wins; flag with `// TODO(decision):`.
> The model is the foundation: API payloads, UI screens, and LLM prompts all use these exact names.
> Endpoint behavior (errors, quota, headers, examples) lives in `API_CONTRACT.md`.
## 0. Rules for this file
1. **Names are contracts.** Enum raw values, field ids, and JSON keys here are used verbatim in Swift,
   `backend/app/schemas/task_draft.json` (D-035), Pydantic models, and prompts. Rename = change all in one commit.
2. **Casing:** Swift + JSON use `camelCase`; Postgres uses `snake_case`. Enum raw values are `camelCase` strings.
3. **Dates:** ISO 8601 strings on the wire. Date-time **with offset** (`2026-11-09T14:00:00+07:00`);
   date-only `YYYY-MM-DD`. Never send epoch numbers. Swift side uses `Date` + the stored `timeZone`.
4. **IDs:** `UUID` (lowercase string on the wire) for our objects; system identifiers
   (`EKEvent.eventIdentifier`, `CNContact.identifier`) stored as opaque `String`.
5. **Device-only data** (marked 🔒) is **never** sent to the backend (D-056).
6. **Schema version:** every persisted/wire root object carries `schemaVersion: Int` (start at `1`).
7. Swift 6 strict concurrency (D-013): all value models are `struct`s that are `Codable, Sendable, Hashable`.
## 1. Enums
### 1.1 TaskKind

| Raw value | Phase | Meaning | Executes via |
|---|---|---|---|
| `calendarEvent` | 1C | Create/edit/delete one-time event | EventKit |
| `reminder` | 1C | Create/edit/delete/snooze one-time reminder | EventKit |
| `call` | 1C | Start a phone call | `tel://` |
| `sms` | 1C | Draft a message | MessageUI / copy + open app |
| `place` | 1C | Find + save a place / get directions | MapKit |
| `ocr` | 1D | Review text + fields extracted from one photo | Local (no external action) |
| `emailReply` | 2 | Draft a Gmail reply | Backend Gmail (D-150: do not add before Phase 2) |
| `ride` | 3 | Prepare a ride request | Handoff |
| `food` | 3 | Prepare a food order request | Handoff |

`enum TaskKind: String, Codable, Sendable, CaseIterable` with exactly the raw values above.
Backend rejects kinds whose phase is not enabled (`ENABLED_KINDS` in config). Phase 2/3 cases exist in the
enum from day one so persisted data stays decodable, but no UI/code path uses them early.
### 1.2 TaskOperation
A step's verb. Needed because "edit" and "delete" are different actions on the same kind.

```swift
enum TaskOperation: String, Codable, Sendable { case create, update, delete, complete, snooze, open, prepare }
```
Valid pairs: `calendarEvent` {create, update, delete}; `reminder` {create, update, delete, complete, snooze};
`call` {open}; `sms` {open}; `place` {create (save), open (directions)}; `ocr` {create};
`emailReply` {create}; `ride`/`food` {prepare}. Any other pair → invalid draft.
### 1.3 TaskState (D-121, exact list — do not add states)
`draft, needsInfo, awaitingApproval, processing, prepared, handedOff, succeeded, unknown, failed, cancelled, userMarkedDone`

Final (D-122): `succeeded, failed, cancelled, userMarkedDone`. (`failed` is final but retryable/cancellable, D-243.)
**Closed** (D-244): `succeeded, cancelled, userMarkedDone` — `failed` is final but **not** closed (still needs the user).
### 1.4 TaskEvent (input to the state machine, D-123)
```swift
enum TaskEvent: String, Codable, Sendable {
  case missingRequiredField, allRequiredFilled, userConfirmed, userEdited, actionVerified,
       outcomeUnknownHandoff, dataPrepared, externalServiceOpened, actionFailed, interrupted,
       userMarkedDone, userCancelled, retry
}
```
Meanings: `missingRequiredField`/`allRequiredFilled` = result of `validate()` (§7.1); `userConfirmed` = "Xác nhận"
tapped (or "có" in voice mode — never for delete, D-108); `outcomeUnknownHandoff` = composer / `tel://` / other app
opened; `dataPrepared` = ride/food data ready, nothing executed; `interrupted` = timeout or app killed mid-action.
One-tap "complete reminder" (D-107, D-248): the app builds a `reminder/complete` step with `completed = "true"`,
already in `awaitingApproval`, and the tap emits `userConfirmed`. "Hoàn tác" builds another one-tap `reminder/complete`
step with `completed = "false"` (same `targetRef`).
### 1.5 Transition table (spec §5.2 + D-222, D-242, D-243 — implement exactly)
| From | Event | To |
|---|---|---|
| `draft` | `missingRequiredField` | `needsInfo` |
| `draft`, `needsInfo` | `allRequiredFilled` | `awaitingApproval` |
| `needsInfo` | `userEdited` | `needsInfo` (re-validate → may emit `allRequiredFilled`) |
| `awaitingApproval` | `userConfirmed` | `processing` |
| `awaitingApproval` | `userEdited` | `awaitingApproval` (clear `approvedSnapshotHash`) |
| `awaitingApproval` | `missingRequiredField` | `needsInfo` (user cleared a required field) |
| `processing` | `actionVerified` | `succeeded` |
| `processing` | `outcomeUnknownHandoff` | `handedOff` |
| `processing` | `dataPrepared` | `prepared` |
| `prepared` | `externalServiceOpened` | `handedOff` |
| `processing` | `actionFailed` | `failed` |
| `processing` | `interrupted` | `unknown` |
| `unknown` | `actionVerified` | `succeeded` (launch verification found evidence) |
| `unknown` | `retry` | `awaitingApproval` (run idempotency check first, D-243) |
| `handedOff`, `unknown` | `userMarkedDone` | `userMarkedDone` |
| `prepared` | `userMarkedDone` | `userMarkedDone` (copy-guide path, service not opened by the app, D-242) |
| `failed` | `retry` | `awaitingApproval` (run idempotency check first, D-105) |
| `failed` | `userCancelled` | `cancelled` (D-243) |
| `failed` | `userMarkedDone` | `userMarkedDone` (user finished it another way, e.g. copy fallback, D-243) |
| `succeeded` | `userEdited` | `awaitingApproval` (edit = new `update` action; evidence cleared, `create` → `update` + `targetRef` from evidence, D-290) |
| any non-final | `userCancelled` | `cancelled` |
| `processing` | `userCancelled` + `context.composerDismissed` | `awaitingApproval` (SMS composer `.cancelled`, D-222) |

SMS composer is shown while the step is `processing`: `.sent` → `actionVerified`, `.failed` → `actionFailed`,
`.cancelled` → the last row. Return prompt (D-242): when the app becomes active after a step went `handedOff`, ask once
("Bạn đã gọi xong chưa?") → "Đã xong" emits `userMarkedDone`, "Chưa" keeps `handedOff`. Track "asked" per step.
```swift
func transition(_ state: TaskState, _ event: TaskEvent, context: TransitionContext = .default) -> TaskState?
// TransitionContext.composerDismissed distinguishes the SMS row above. Illegal → nil + Logger.warning.
```
### 1.6 FieldType (how a field's `value` string is encoded)
| Raw | Encoding of `value` | Example |
|---|---|---|
| `text` | free text, trimmed, ≤ 2000 chars | `Khám răng` |
| `longText` | free text, ≤ 10 000 chars | SMS body, OCR text |
| `dateTime` | ISO 8601 with offset | `2026-11-09T14:00:00+07:00` |
| `date` | `YYYY-MM-DD` | `2026-11-14` |
| `durationMinutes` | integer string | `30` |
| `bool` | `true` / `false` | `false` |
| `phone` | E.164 after device normalization; raw OCR text before | `+84901234567` |
| `contactRef` 🔒 | `CNContact.identifier` | opaque |
| `placeRef` 🔒 | `SavedPlace.id` UUID | opaque |
| `address` | single-line address text | `123 Lê Lợi, Q1, TP.HCM` |
| `coordinate` | `lat,lng` decimal | `10.7769,106.7009` |
| `enumChoice` | one of the catalog `options` | `zalo` |
### 1.7 FieldSource
```swift
enum FieldSource: Codable, Sendable, Hashable {
  case user                         // typed or picked by the user
  case ai                           // produced by /v1/parse
  case ocr(span: SourceSpan)        // from /v1/extract over OCR text
  case device(origin: String)       // resolved on device: "contacts", "calendar", "maps", "savedPlace"
  case linked(stepId: UUID, fieldId: String) // copied from another step (§3.3)
  case email(messageId: String)     // Phase 2
}
struct SourceSpan: Codable, Sendable, Hashable {
  var start: Int; var end: Int      // UTF-16 offsets into TaskDraft.originalInput (OCR text)
  var boundingBox: NormalizedRect?  // Vision box (0–1, origin bottom-left) for "Xem ảnh gốc"
}
```
JSON encoding: `{"type":"ocr","span":{...}}`, `{"type":"user"}` etc. (discriminator key `type`).
Rule: any user edit sets `source = .user` and `confidence = nil`.
## 2. Field
```swift
struct Field: Codable, Sendable, Identifiable, Hashable {
  let id: String              // catalog id, e.g. "startDate" (§4)
  var type: FieldType
  var value: String?          // encoded per FieldType; nil = empty
  var required: Bool          // from §4.1 for the step's (kind, operation) + current values (e.g. channel)
  var source: FieldSource
  var confidence: Double?     // 0…1, AI/OCR only; < 0.7 → needsReview (D-126)
  var ambiguity: Ambiguity?   // non-nil blocks "Xác nhận" until resolved (D-106)
  var deviceOnly: Bool        // 🔒 never serialized to backend payloads
}
extension Field {
  var needsReview: Bool { (confidence ?? 1) < 0.7 || source.isOCR || ambiguity != nil }
  var labelKey: String      // "field.<kind>.<id>" in Localizable.xcstrings (vi primary)
}
```
**Labels are not stored** — the spec's `label` property is computed from `labelKey` so UI text stays in
`Localizable.xcstrings` (D-003) and the LLM never writes UI text. (D-220.)
### 2.1 Ambiguity
```swift
struct Ambiguity: Codable, Sendable, Hashable {
  var kind: AmbiguityKind          // .contact, .date, .place, .phoneNumber, .other
  var question: String             // Vietnamese, one short sentence: "Bạn muốn nhắn Minh nào?"
  var candidates: [Candidate]      // empty → free-text answer
}
struct Candidate: Codable, Sendable, Hashable, Identifiable {
  let id: String                   // value to put into Field.value if chosen
  var title: String                // "Minh (Công ty)"
  var subtitle: String?            // masked number "•••• 567", date "Thứ Sáu 13/11"
  var imageRef: String?            // 🔒 contact thumbnail identifier, device only
}
```
- `.contact` and `.phoneNumber` candidates are built **on device** only; the backend only says
  "`recipientName` = Minh" and the app finds matches (D-056).
- `.date` candidates may come from the backend (`/v1/parse` lists plausible dates) or device.
- Resolving: user picks → `value = candidate.id`, `source = .user`, `ambiguity = nil`, re-validate (local, no unit, D-251).
## 3. TaskStep and TaskDraft
### 3.1 TaskStep (value type, stored inside TaskDraft)
```swift
struct TaskStep: Codable, Sendable, Identifiable, Hashable {
  let id: UUID
  var order: Int                         // 0-based execution order within the draft
  var kind: TaskKind
  var operation: TaskOperation
  var state: TaskState
  var fields: [Field]                    // order = catalog order (§4)
  var targetRef: String?                 // existing object for update/delete/complete/snooze (eventIdentifier…)
  var approvedSnapshotHash: String?      // §3.4; set on userConfirmed, cleared whenever the step enters awaitingApproval
  var resultEvidence: String?            // required for succeeded (D-124), §3.5
  var handoffNote: String?               // Vietnamese: what the user still must do
  var handoffPromptShown: Bool           // D-242 return prompt already asked for this hand-off
  var errorMessage: String?              // Vietnamese, user-facing; no stack traces
  var errorCode: String?                 // machine code `<domain>.<reason>`, e.g. "permission.calendar.denied" (D-249)
  var attempt: Int                       // incremented on each processing entry (idempotency)
  var stateChangedAt: Date
  var history: [StateChange]             // append-only audit (from, to, event, at); cap 50
}
struct StateChange: Codable, Sendable, Hashable { var from: TaskState; var to: TaskState; var event: TaskEvent; var at: Date }
```
### 3.2 TaskDraft (SwiftData `@Model`, D-016)
```swift
@Model final class TaskDraft {
  @Attribute(.unique) var id: UUID
  var schemaVersion: Int                 // = 1
  var createdAt: Date
  var updatedAt: Date                    // bumped on every autosave (D-104)
  var inputMode: InputMode               // .text, .voice, .photo, .shortcut
  var originalInput: String              // transcript / typed text / OCR text
  var imageLocalPath: String?            // 🔒 relative path in Application Support/ocr/<id>.jpg
  var timeZoneId: String                 // e.g. "Asia/Ho_Chi_Minh" at creation (D-058)
  var locale: String                     // "vi-VN"
  var followUpQuestion: String?          // the ONE pending question (spec §6.2 AC3)
  var steps: [TaskStep]                  // Codable composite attribute
  var isArchived: Bool                   // user swiped to hide; "Xóa lịch sử" deletes instead
  var serverRequestId: String?           // id from /v1/parse for support/debug
}
enum InputMode: String, Codable, Sendable { case text, voice, photo, shortcut }
```
Computed, not stored: `overallStatus` (History group, §8) and `currentStep` = first step by `order` that is
not closed and not `handedOff`; if none, the last step (D-244). `isClosed` = every step closed.
### 3.3 Linked flows and field bindings (D-120)
A linked flow is one `TaskDraft` with ordered steps. A field may follow a field of an earlier step; the link
is stored in the field itself: `Field.source = .linked(stepId:, fieldId:)`.
1. Example flow 1: `ride.destination` ← `calendarEvent.location`. Derived values (e.g. ride time = event
   start − 30 min) are computed once when the step is built; they are plain `.ai` values, not live links.
2. When the source field changes, every linked field updates **and** its step gets `userEdited`
   (approval reset, D-101). A user edit on the linked field breaks the link (`source = .user`).
3. Steps execute one at a time, in `order`. Step N+1 can be reviewed before step N finishes, but its
   "Xác nhận" is enabled only when step N is final or `handedOff`/`prepared`.
### 3.4 Approval snapshot hash (D-101)
```
canonical = "<kind>|<operation>|<targetRef ?? "">\n"
            + ALL fields (device-only included) sorted by id, each "<id>=<value ?? "">", joined by "\n"
hash      = SHA256(canonical UTF-8) hex lowercase   (CryptoKit)
```
`userConfirmed` stores the hash. The executor recomputes it right before calling the system framework;
mismatch → do not execute, emit `actionFailed` with `errorCode = "approval.mismatch"` (user retries → Review).
### 3.5 Evidence format (`resultEvidence`)
| Kind / op | Evidence | Verification on launch (D-125) |
|---|---|---|
| calendarEvent create/update | `ek:event:<eventIdentifier>` | `eventStore.event(withIdentifier:)` exists and fields match |
| calendarEvent delete | `ek:deleted:<eventIdentifier>` | identifier no longer found |
| reminder * | `ek:reminder:<calendarItemIdentifier>` | `calendarItem(withIdentifier:)`; for complete check `isCompleted == completed` |
| sms (MessageUI) | `msg:sent:<ISO date>` | none possible — `.sent` result is the evidence |
| place create | `local:place:<SavedPlace.id>` | SwiftData fetch |
| ocr create | `local:confirmed` | — |
| call, place open (directions), sms copy path, handoff | **never** evidence; final state only via `userMarkedDone` (D-102) | — |

Idempotency (D-105): before (re)creating an event/reminder, look up `targetRef`/stored evidence first;
also store `easyphone:<step.id>` in the item's `url` property so a lost identifier can be found by search.
Launch verification that finds no evidence leaves the step `unknown`; the user may then `retry` (D-243).
## 4. Field catalog per TaskKind
Single source: `Core/Models/FieldCatalog.swift` **and** `backend/app/schemas/field_catalog.json`
(generated from the same table; test asserts they match). The ✔ column is for `create`; §4.1 is authoritative
for every `(kind, operation)`. Required = needed to leave `needsInfo`.

| Kind | Field id | Type | Required | Notes |
|---|---|---|---|---|
| calendarEvent | `title` | text | ✔ | for delete it is a search hint only |
| | `startDate` | dateTime | ✔ | ambiguous weekday → `.date` ambiguity |
| | `endDate` | dateTime | | default start + 60 min; must be > start |
| | `allDay` | bool | | default `false` |
| | `location` | address | | |
| | `notes` | longText | | |
| | `alertMinutesBefore` | durationMinutes | | default `60` |
| | `calendarId` 🔒 | text | | nil → default calendar |
| reminder | `title` | text | ✔ | |
| | `dueDate` | dateTime | ✔ | alarm at due date |
| | `notes` | longText | | |
| | `snoozeOption` | enumChoice | op=snooze | `min15`, `hour1`, `tomorrowMorning` (hour from Settings) |
| | `completed` | bool | op=complete | `true` = mark done, `false` = undo (D-248); app-built, never from LLM |
| call | `recipientName` | text | ✔ | LLM gives name/nickname only ("mẹ", "anh Minh") |
| | `contactId` 🔒 | contactRef | ✔ | resolved on device; ambiguity if ≠ 1 match |
| | `phoneNumber` 🔒 | phone | ✔ | ambiguity if contact has several numbers |
| sms | `recipientName`, `contactId` 🔒, `phoneNumber` 🔒 | — | ✔ | same as call; 🔒 ones only when `channel = sms` (D-247) |
| | `body` | longText | ✔ | drafted by LLM, always editable |
| | `channel` | enumChoice | ✔ | `sms` (built in, default; iMessage via system) or a service id (§10) |
| place | `query` | text | ✔ | what to search |
| | `name`, `address`, `coordinate` | text, address, coordinate | ✔ (create, open) | from chosen `MKMapItem` or saved place |
| | `label` | enumChoice | op=create | `home`, `work`, `custom` (+ `customLabel` text) |
| | `mapsApp` | enumChoice | op=open | `appleMaps` (default), `googleMaps` if installed |
| ocr | `extractedText` | longText | ✔ | full OCR text = `originalInput` |
| | `title`, `dateTime`, `address`, `personName`, `phoneNumber` | text, per name | | from `/v1/extract`, each with a span (`title`: D-276) |
| | `nextAction` | enumChoice | | `calendarEvent`, `reminder`, `copyContactInfo`, `ride` (Phase 3) |

- calendarEvent: device computes `conflicts` for Review (spec §6.4 AC2) — transient UI state, not persisted.
- ocr: choosing `nextAction` appends a new step to the same draft with `.linked` fields (`title` → `title`,
  `dateTime` → `startDate`/`dueDate`, `address` → `location`).
  `copyContactInfo` = copy name + phone to clipboard (no Contacts write in MVP, D-226).
### 4.1 Required fields per (kind, operation) (D-248) — `targetRef` is required where listed
| Kind.operation | Required |
|---|---|
| calendarEvent.create | `title`, `startDate` |
| calendarEvent.update | `targetRef`, `title`, `startDate` |
| calendarEvent.delete | `targetRef` only (`title`/`startDate` = search hints) |
| reminder.create | `title`, `dueDate` |
| reminder.update | `targetRef`, `title`, `dueDate` |
| reminder.complete | `targetRef`, `completed` |
| reminder.snooze | `targetRef`, `snoozeOption` |
| reminder.delete | `targetRef` only |
| call.open | `recipientName`, `phoneNumber`; + `contactId` unless `recipientName` is a phone number (D-253) |
| sms.open | `recipientName`, `body`, `channel`; + `phoneNumber` (and `contactId`, D-253) when `channel = sms` (D-247) |
| place.create | `query`, `name`, `address`, `coordinate`, `label` (+ `customLabel` when `label = custom`) |
| place.open | `query`, `name`, `address`, `coordinate`, `mapsApp` |
| ocr.create | `extractedText` |

`Field.required` is recomputed whenever `channel` or `label` changes. The LLM prompt's `field_catalog` block
(AI_PROMPTS §1.1) is generated from this table, minus 🔒 and app-built fields (`completed`).
### Phase 2–3 kinds (define fully only when the phase starts)
- `emailReply`: `accountEmail`, `threadId`, `messageId`, `subject`, `body`, `summary` (longText).
- `ride`: `service`, `pickup`, `destination`, `time`, `vehicleType`, `note`.
- `food`: `service`, `dishes`, `quantity`, `options`, `budget`, `address`, `time`.
`service` options come only from `SupportedServices.json` (D-109). Never a `price` field (D-160).
## 5. Local-only models (SwiftData, all 🔒)
```swift
@Model final class SavedPlace {
  @Attribute(.unique) var id: UUID
  var label: String            // "home" | "work" | "custom"
  var customLabel: String?     // "Nhà con gái"
  var name: String; var address: String; var latitude: Double; var longitude: Double; var createdAt: Date
}
@Model final class Nickname {
  @Attribute(.unique) var id: UUID
  var nickname: String         // "mẹ", "sếp" — stored as typed
  var normalized: String       // diacritic- and case-folded key, §7.2; unique
  var contactId: String; var createdAt: Date   // CNContact.identifier
}
@Model final class AppSettings {   // exactly one row
  var voiceEnabled: Bool = true
  var speechRate: Double = 0.45     // AVSpeechUtterance rate
  var simpleMode: Bool = false      // "Chế độ đơn giản"
  var snoozeMorningHour: Int = 8
  var preferredMapsApp: String = "appleMaps"
  var lastSeenEntitlement: CachedEntitlement?  // display only (D-085)
}
struct CachedEntitlement: Codable, Sendable { var plan: Plan; var quotaRemaining: Int; var resetsAt: Date; var fetchedAt: Date }
enum Plan: String, Codable, Sendable { case free, premium }
```
- Saved places may be sent to the backend **only** as a label (`"home"`) so the LLM can write `pickup = home`;
  the device swaps in the address. Never send the address unless the user typed it in the request.
- "Xóa dữ liệu ghi nhớ" deletes `Nickname` + `SavedPlace`. "Xóa lịch sử" deletes `TaskDraft` rows whose steps are
  **all closed** (D-244); drafts with a `failed`, `unknown`, `handedOff` or open step are kept.
  Account deletion wipes the whole SwiftData store + `ocr/` images (D-073).
## 6. Wire models (backend ↔ app)
Full endpoint behavior, headers, quota and examples: `API_CONTRACT.md`. This section defines the shapes.
### 6.1 Common
- Headers: `Authorization: Bearer <supabase JWT>`, `X-Client-Version`, `Accept-Language: vi`,
  `Idempotency-Key` on metered POSTs (D-230, one key per endpoint call, D-245).
- Error body (all endpoints, D-233):
```json
{ "error": { "code": "quota_exceeded", "message": "Bạn đã dùng hết lượt hôm nay.", "retryable": false,
             "requestId": "req_01JC...", "details": { } } }
```
Codes, HTTP status, `details`, and app behavior: `API_CONTRACT.md` §3 (D-233, D-054, D-087).
`unsupported` is not an error: `200` with an `unsupported` payload (§6.2).
### 6.2 `POST /v1/parse`
Request:
```json
{ "schemaVersion": 1, "text": "Nhắn anh Minh là chiều nay em đến muộn", "inputMode": "voice",
  "now": "2026-11-08T18:07:00+07:00", "timezone": "Asia/Ho_Chi_Minh", "locale": "vi-VN",
  "savedPlaceLabels": ["home", "work"],
  "context": { "draftId": null, "answeringFieldId": null, "currentDraft": null } }
```
`context` is used when answering a follow-up question: send the current draft as `ParsedDraft` (no 🔒 fields).

Response = **`ParsedDraft`** = `ParsedDraftLLM` (§6.3, the LLM output) + `schemaVersion` + `requestId` added by the backend (D-277):
```json
{ "schemaVersion": 1, "requestId": "req_01H...",
  "steps": [{ "kind": "sms", "operation": "open",
    "fields": [
      { "id": "recipientName", "value": "anh Minh", "confidence": 0.95, "sourceQuote": "anh Minh" },
      { "id": "body", "value": "Chiều nay em đến muộn nhé.", "confidence": 0.85, "sourceQuote": null },
      { "id": "channel", "value": "sms", "confidence": 0.6, "sourceQuote": null }
    ],
    "dateCandidates": [] }],
  "followUpQuestion": null, "unsupported": null }
```
- `unsupported`: `{ "reason": "recurringEvent", "message": "Chưa hỗ trợ lịch lặp lại." }` → UI shows
  "Chưa hỗ trợ" and builds no steps (spec §11).
- `dateCandidates`: `[{ "fieldId": "startDate", "value": "...", "label": "Thứ Sáu 13/11" }]` when ambiguous.
- The LLM **never** outputs: `state`, `id`s, labels, `contactId`, `phoneNumber` for contacts, evidence, hashes.

**App mapping `ParsedDraft` → `TaskDraft`:** new UUIDs; `state = draft`; fill catalog defaults; set
`source = .ai`; run device resolution (contacts, saved places, conflicts); build `Ambiguity`s; run validation →
emit `missingRequiredField` or `allRequiredFilled`.
### 6.3 JSON Schema rules for `task_draft.json` (OpenAI structured outputs)
- It describes **`ParsedDraftLLM`** = `{ steps, followUpQuestion, unsupported }` only — no `schemaVersion`, no `requestId` (D-277).
- `additionalProperties: false` on every object; every property listed in `required`;
  optional values use `"type": ["string", "null"]`.
- `kind`, `operation`, field `id` are `enum`s generated from §1 and §4 (per-phase `ENABLED_KINDS`).
- `value` is always a string (or null); `confidence` is a number (or null when `value` is null). The backend validates
  the encoding per `FieldType` after the call and drops/flags invalid values (`confidence = 0`) instead of failing.
### 6.4 `POST /v1/extract`
Request: `{ "schemaVersion", "ocrText", "now", "timezone", "locale" }` (backend wraps `ocrText` in `<untrusted_content>`, D-057).
Response: `{ "schemaVersion", "requestId", "fields": [{ "id", "value", "confidence", "span": { "start", "end" } | null }],
"suggestedNextAction" }`. Spans are UTF-16 offsets (§1.7). Full example + span rules: `API_CONTRACT.md` §7.2.
Device maps span → Vision box.
### 6.5 Other endpoints (every JSON response root also carries `schemaVersion`; AI endpoints also carry `requestId`)
- `POST /v1/ocr` (multipart `image`, JPEG ≤ 4 MB, long side ≤ 2048 px) → `{ "text": "...", "lines": [{ "text", "box" }] }`
- `POST /v1/transcribe` (multipart `audio`, m4a ≤ 60 s) → `{ "text": "...", "confidence": 0.0–1.0 | null }` (D-238)
- `GET /v1/me` → `{ "userId", "locale": "vi", "plan": "free", "quota": { "limit": 10, "used": 3, "remaining": 7,
  "resetsAt": "2026-11-09T00:00:00+07:00" }, "subscription": null | { "productId", "status", "expiresAt", "environment" } }`
- `POST /v1/billing/verify` → `{ "signedTransaction": "<JWS>" }` → same body as `GET /v1/me`.
- `DELETE /v1/me` → `204`. `GET /v1/health` (no auth, D-235) → `{ "status": "ok", "version", "schemaVersion" }`.
## 7. Validation & normalization (shared logic, unit-tested — D-205)
### 7.1 Draft validation (pure function `validate(step) -> [ValidationIssue]`)
1. Every field required by §4.1 for the `(kind, operation)` (and current `channel`/`label`) has a non-empty,
   correctly encoded value; `targetRef` is set where §4.1 lists it.
2. No field has `ambiguity != nil`.
3. Cross-field: `endDate > startDate`; `dueDate`/`startDate` not more than 5 min in the past (else ask).
4. `channel = "sms"` is always valid (built in). Any other `channel`/`service` value must exist in
   `SupportedServices.json`; unverified → copy-only path (D-162, D-247). Unknown id → issue on that field.
Result empty → `allRequiredFilled`; else `missingRequiredField` + `followUpQuestion` for the **first** issue only.
The LLM's `followUpQuestion` is wording only: used if it targets that first field, ignored if `validate()` finds no issue (D-281).
### 7.2 Vietnamese name normalization (contacts + nicknames, spec §6.6 AC1)
`normalize(s) = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: vi)`
then replace `đ/Đ → d`, collapse whitespace, trim. Strip leading kinship words for matching only
(`anh, chị, em, cô, chú, bác, ông, bà, cháu, con`) but keep the original in `recipientName`.
Match order: exact nickname → normalized nickname → given/family/full name contains → none.
Never auto-pick when count ≠ 1 (D-106).
### 7.3 Phone normalization
Vietnamese local `0xxxxxxxxx` → `+84xxxxxxxxx`; strip spaces/dots/dashes. UI shows masked `•••• 567` in pickers.
## 8. State → UI mapping (single table, used by Home, History, Review, VoiceOver)
| State | Vietnamese label (`state.<raw>`) | Icon (SF Symbol) | History group |
|---|---|---|---|
| draft | Bản nháp | `square.and.pencil` | Cần bạn làm tiếp |
| needsInfo | Cần thêm thông tin | `questionmark.circle` | Cần bạn làm tiếp |
| awaitingApproval | Chờ bạn xác nhận | `hand.raised` | Cần bạn làm tiếp |
| processing | Đang thực hiện | `hourglass` | Đang chờ |
| prepared | Đã chuẩn bị — cần mở {service} | `tray.full` | Cần bạn làm tiếp |
| handedOff | Cần hoàn tất trong {app} | `arrow.up.forward.app` | Đang chờ |
| unknown | Chưa rõ kết quả | `exclamationmark.circle` | Cần bạn làm tiếp |
| succeeded | Đã xong | `checkmark.circle` | Đã xong |
| userMarkedDone | Bạn đã làm xong | `checkmark.seal` | Đã xong |
| failed | Không thành công | `xmark.octagon` | Cần bạn làm tiếp |
| cancelled | Đã hủy | `minus.circle` | Đã hủy |

Draft group = highest-priority step group: Cần bạn làm tiếp > Đang chờ > Đã xong > Đã hủy.
"Việc chưa xong" (Home list, widget count, `handoff.notYet.toast`) = drafts in "Cần bạn làm tiếp" or "Đang chờ" (D-244).
Color is decoration only — icon + text always shown (D-183).
## 9. Backend data (Supabase Postgres, D-031/D-033)
```sql
create table profiles (id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(), locale text not null default 'vi');
create table subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  product_id text not null,                                   -- easyphone.premium.monthly|yearly (D-091)
  original_transaction_id text not null unique,
  expires_at timestamptz, updated_at timestamptz not null default now(),
  status text not null check (status in ('active','expired','inGracePeriod','billingRetry','revoked','refunded')),
  environment text not null check (environment in ('Sandbox','Production','Xcode')));  -- 'Xcode': dev only (D-240)
create table usage_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  endpoint text not null,                                     -- '/v1/parse'
  units int not null default 1,                               -- quota units (D-086, D-093); 0 = refunded (D-231)
  idempotency_key text,                                       -- D-230/D-245; null for unmetered rows
  attempt int not null default 0,                             -- D-246: latest attempt number; only it may commit/refund
  tokens_in int not null default 0, tokens_out int not null default 0,
  cost_usd numeric(10,6) not null default 0, created_at timestamptz not null default now());
create index on usage_events (user_id, created_at);
create unique index on usage_events (user_id, idempotency_key) where idempotency_key is not null;
-- gmail_accounts: Phase 2 only (D-150). Do not create.
```
- RLS on all tables: `select` where `user_id = auth.uid()` (`id = auth.uid()` for profiles). **No** client
  `insert/update/delete` policies — the backend writes with the service role key.
- `profiles` row is upserted on the first authenticated request (D-236).
- Plan = `premium` iff a `subscriptions` row has `status in ('active','inGracePeriod','billingRetry')` and
  `expires_at > now()`. Else `free`.
- Quota day = calendar day in `QUOTA_DAY_TZ` (config, default `Asia/Ho_Chi_Minh`); `used = sum(units)` today.
  Limits: `FREE_DAILY_QUOTA` (D-091), `PREMIUM_DAILY_QUOTA` (D-232).
- Monthly spend cap: `sum(cost_usd)` for the current month across all users vs `MONTHLY_SPEND_CAP_USD`.
- Never store request text or LLM output in tables (D-059).
## 10. Static config files (bundled, read-only)
`Resources/SupportedServices.json`:
```json
{ "schemaVersion": 1, "services": [
  { "id": "zalo", "name": "Zalo", "kinds": ["sms"], "urlScheme": "zalo://", "verified": false,
    "guideSteps": ["Mở Zalo", "Chọn người nhận", "Dán tin nhắn", "Bấm Gửi"] },
  { "id": "grab", "name": "Grab", "kinds": ["ride", "food"], "urlScheme": "grab://", "verified": false, "guideSteps": [] }
] }
```
All `verified: false` until D-161 is locked (D-162). `urlScheme` is only used when `verified: true`
and the scheme is in `LSApplicationQueriesSchemes`. Strings in `guideSteps` are Vietnamese UI text.
`sms` is built in and is **not** listed here (D-247).
## 11. Decisions used by this file
D-220 – D-226 (§12.1), D-230 – D-233, D-236, D-238, D-240 (§12.2), D-243 – D-251 (§12.3), D-252 – D-276 (§12.4), D-277 – D-281 (§12.5).
## 12. Versioning & migration
- Bump `schemaVersion` on any breaking wire/persisted change; backend accepts current + previous for one release.
- SwiftData: use `VersionedSchema` + `SchemaMigrationPlan` from v1. Unknown enum raw values on decode →
  map step to `unknown` state / skip field, never crash.
- New `TaskKind` = update §1.1, §4, §4.1, `field_catalog.json`, `task_draft.json`, `Localizable.xcstrings`,
  and §8 in **one commit**.
## 13. Required tests for this model
| Test | Where |
|---|---|
| Every row of §1.5 succeeds (incl. D-222, D-242, D-243 rows); every other `(state, event)` pair returns `nil` | Swift Testing |
| Edit after approval clears hash and returns to `awaitingApproval` | Swift Testing |
| Hash changes when any field changes; stable across field order | Swift Testing |
| `validate()` per §4.1 row, incl. cross-field rules, `channel = sms` vs `zalo` required sets | Swift Testing |
| Follow-up rule (D-281): LLM question for another field → `followup.<kind>.<fieldId>`; question but no issue → ignored | Swift Testing |
| `currentStep`, History group, `isClosed` for drafts with `failed` / `handedOff` / closed steps | Swift Testing |
| Name normalization: "minh" ↔ "Minh"/"Mính", "đức" ↔ "Duc", kinship stripping | Swift Testing |
| Phone normalization `0901 234 567` → `+84901234567` | Swift Testing |
| `ParsedDraft` JSON fixtures decode in Swift **and** validate against `task_draft.json` in pytest | both |
| Swift `FieldCatalog` == `field_catalog.json` | pytest + Swift (shared fixture) |
| Launch verification: `processing`/`unknown` → `succeeded` when evidence found, else stays `unknown` | Swift Testing |
| Quota: units summed per `QUOTA_DAY_TZ` day; blocked before OpenAI call; same `Idempotency-Key` charged once | pytest |
