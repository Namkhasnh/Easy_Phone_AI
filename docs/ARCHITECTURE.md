# EasyPhone AI — ARCHITECTURE.md

> Audience: an AI coding agent (Claude Code) working in Xcode on macOS + the FastAPI backend.
> Hierarchy (D-279): `DECISIONS.md` → `EasyPhone-AI-Spec.md` → `DATA_MODEL.md` → `API_CONTRACT.md` → `AI_PROMPTS.md` → **this file** → `UI_SCREENS.md`.
> This file is the **structural map**: layers, modules, service protocols, data flows, error handling and retry.
> It never changes a shape, endpoint, state, rule or quota. Shapes = `DATA_MODEL.md`, wire = `API_CONTRACT.md`.
> Conflict → the other doc wins; flag with `// TODO(decision):`. Choices made here (P-23 – P-30, §14) are approved as D-258 – D-265.
## 0. Rules
1. **Dependencies point down only:** View → ViewModel → Engine/UseCase → Service protocol → framework/network. Never up.
2. **No framework import above the Service layer.** Views/ViewModels never import EventKit, Contacts, MessageUI,
   Speech, Vision, StoreKit or Supabase. They only see protocols from `Core/Services/` (D-015).
3. **Every service has a protocol + `Live…` + `Mock…`** implementation. Previews and tests use mocks (D-206).
4. **One state machine, one place.** Only `TaskEngine` changes `TaskStep.state`, always via `transition()` (D-123).
5. **Backend is the source of truth** for plan + quota (D-085); the device is the source of truth for contacts,
   calendar, reminders, places, drafts (D-055, D-056).
6. Swift 6 strict concurrency (D-013): value models are `Sendable` structs; no `@unchecked Sendable` without a comment.
## 1. System overview
```
 ┌──────────────────────── iPhone (iOS 18+) ────────────────────────┐
 │ SwiftUI Views ─ @Observable ViewModels ─ TaskEngine ─ Services   │
 │   │ SwiftData (drafts, places, nicknames, settings) 🔒            │
 │   │ EventKit · Contacts · MessageUI · MapKit · Vision · Speech   │
 │   │ AVSpeech · StoreKit 2 · App Intents · WidgetKit              │
 │   └─ APIClient (HTTPS, Supabase JWT, Idempotency-Key)            │
 └────────────┬─────────────────────────────┬───────────────────────┘
              │ Supabase Swift SDK          │ /v1/* JSON / multipart
              ▼ (sign-in, token refresh)    ▼
 ┌──────────────────────┐        ┌──────────────────────────────────┐
 │ Supabase Auth        │◀─JWT──▶│ FastAPI backend (one service)    │
 │ (Google, D-283)      │ verify │ routers → services → repositories│
 ├──────────────────────┤        │  ├─ OpenAI client (parse/extract/│
 │ Supabase Postgres    │◀──SQL──│  │   ocr/transcribe)             │
 │ profiles,            │ service│  ├─ App Store JWS verification   │
 │ subscriptions,       │  role  │  └─ Supabase Admin API (delete)  │
 │ usage_events (RLS)   │        └───────────┬──────────────────────┘
 └──────────────────────┘                    │ HTTPS, key from env (D-051)
                                             ▼
                  OpenAI API          Apple App Store Server Notifications V2 → /v1/billing/notifications
```
- The app talks to Supabase **only for auth** (SDK session in Keychain). All data reads/writes go through the backend.
- The backend talks to Postgres with the **service role** (RLS still on, D-033), and to OpenAI with the server key.
- Nothing 🔒 crosses the network boundary (DATA_MODEL §0.5, API_CONTRACT §0.3).
## 2. iOS layers
| Layer | Folder | Contains | May depend on |
|---|---|---|---|
| App | `App/` | `EasyPhoneApp`, `AppState`, `Router`, `AppEnvironment` (DI), deep-link + scene-phase handling | everything below |
| View | `Features/*/` | SwiftUI views, `#Preview` with mocks | its ViewModel, shared UI components |
| ViewModel | `Features/*/` | `@Observable @MainActor final class …ViewModel` | Engine, Services (protocols) |
| Engine | `Core/Engine/` | `TaskEngine`, `TaskStateMachine`, `Validator`, `DraftBuilder`, `DeviceResolver`, `StepExecutor`s, `LaunchVerifier`, `HandoffPromptCoordinator` | Services, Models |
| Services | `Core/Services/` (protocols) + `Core/Services/Live/` | protocol + live + mock | Apple frameworks, `APIClient` |
| Networking | `Core/Networking/` | `APIClient`, DTOs, `RetryPolicy`, `IdempotencyKey`, error mapping | Supabase SDK (token only) |
| Persistence | `Core/Persistence/` | SwiftData `ModelContainer`, `VersionedSchema`, repositories | SwiftData |
| Models | `Core/Models/` | `TaskDraft`, `TaskStep`, `Field`, enums, `FieldCatalog` | Foundation only |

`Core/StateMachine/` from spec §3.2 lives inside `Core/Engine/` (P-23). `Core/Permissions/` holds `PermissionManager`.
### 2.1 ViewModel pattern
```swift
@Observable @MainActor final class ReviewViewModel {
  private(set) var draft: TaskDraftSnapshot          // value copy for rendering
  private(set) var banner: UserMessage?              // localized key + args, never raw error text
  var pendingComposer: ComposerRequest?              // UI effect requested by the engine (§5.3)
  var pendingPermission: Capability?                 // shows S18 explainer before confirm (§5.1 step 0)
  private let engine: TaskEngine
  init(draftId: UUID, engine: TaskEngine) { … }
  func edit(fieldId: String, value: String?) async { await engine.edit(draftId, stepId, fieldId, value) }
  func confirm() async { await engine.confirm(draftId, stepId) }   // "Xác nhận"
  func cancel() async { await engine.cancel(draftId, stepId) }     // "Hủy"
}
```
- ViewModels hold **no business rules**: they forward intents to the engine and render snapshots.
- `UserMessage` = `{ key: String, args: [String] }` resolved from `Localizable.xcstrings` (D-003, D-184).
- One ViewModel per screen. Shared state (signed-in user, entitlement, listening mode) lives in `AppState`.
### 2.2 App state, navigation, entry points
```swift
@Observable @MainActor final class AppState {
  var session: SessionState            // .signedOut, .signedIn(userId), .restoring
  var entitlement: CachedEntitlement?  // display only (D-085)
  var startListeningRequested = false  // set by StartListeningIntent / easyphone://listen / widgets (D-172)
  var blockingScreen: BlockingScreen?  // .clientOutdated(minVersion) (426)
}
enum Route: Hashable { case review(UUID), ocr, history, settings, paywall, places, conversation(UUID?),
                       calendarToday, reminders }   // last two: D-266 (S11, S12)
```
- `Router` owns one `NavigationStack(path:)`. "Reopen at the exact step" (spec §6.10 AC2) = `Route.review(draftId)`;
  Review scrolls to `draft.currentStep` (DATA_MODEL §3.2, D-244).
- `onOpenURL` handles `easyphone://listen` → `startListeningRequested = true` → Home starts `SpeechService`.
- `StartListeningIntent` has `openAppWhenRun = true` and sets the same flag (Siri, Action Button, Control, D-170).
- `scenePhase` changes go to `AppLifecycle`: `.active` → `LaunchVerifier` (first time) + `HandoffPromptCoordinator`;
  `.background` → flush autosave.
## 3. Dependency injection
```swift
struct AppEnvironment: Sendable {   // built once in EasyPhoneApp; injected via .environment(\.appEnv, …)
  var api: any APIClientProtocol
  var auth: any AuthService
  var calendar: any CalendarService;  var reminders: any RemindersService
  var contacts: any ContactsService;  var messages: any MessagesService
  var call: any CallService;          var places: any PlacesService
  var speech: any SpeechService;      var tts: any TTSService
  var ocr: any OCRService;            var purchases: any PurchaseService
  var permissions: any PermissionManager
  var system: any SystemService       // open URL, clipboard, canOpenURL
  var clock: any ClockService         // now + timeZone, mockable for date tests
  var drafts: any TaskRepository;     var localData: any LocalDataRepository
  static func live() -> AppEnvironment
  static func mock(_ scenario: MockScenario = .default) -> AppEnvironment
}
```
- `TaskEngine(env:)` is created once and shared (it is an `@MainActor` class, §5).
- Debug vs Release only changes `APIClient` base URL and StoreKit config (D-208), never the wiring.
## 4. Service protocols (`Core/Services/`)
All methods are `async`; failures throw `ServiceError` (§9.1). All protocols are `Sendable`.
### 4.1 Network & account
```swift
protocol AuthService: Sendable {
  var sessionUpdates: AsyncStream<SessionState> { get }
  func signInWithGoogle() async throws   // Google only (D-283); Apple = add a method later
  func accessToken(forceRefresh: Bool) async throws -> String   // reads/refreshes Supabase SDK session
  func signOut() async
}
protocol APIClientProtocol: Sendable {
  func health() async throws -> HealthResponse
  func me() async throws -> MeResponse
  func deleteAccount() async throws
  func parse(_ r: ParseRequest, key: IdempotencyKey) async throws -> ParsedDraft
  func extract(_ r: ExtractRequest, key: IdempotencyKey) async throws -> ExtractResponse
  func ocr(jpeg: Data, meta: MediaMeta, key: IdempotencyKey) async throws -> OCRResponse
  func transcribe(m4a: Data, meta: MediaMeta) async throws -> TranscribeResponse
  func verifyTransaction(jws: String) async throws -> MeResponse
  var quotaUpdates: AsyncStream<Quota> { get }                  // from X-Quota-* headers
}
protocol PurchaseService: Sendable {
  func products() async throws -> [ProductInfo]                  // ids from config (D-091)
  func purchase(_ id: String, appAccountToken: UUID) async throws -> PurchaseOutcome  // .verified(jws), .cancelled, .pending
  func currentEntitlementJWS() async -> [String]                 // for "Khôi phục giao dịch"
  var transactionUpdates: AsyncStream<String> { get }            // JWS from Transaction.updates
  func finish(jws: String) async
}
```

### 4.2 Device actions (EventKit, Contacts, MessageUI, MapKit, URLs)
```swift
protocol CalendarService: Sendable {
  func events(in range: DateInterval) async throws -> [EventSummary]
  func conflicts(start: Date, end: Date) async throws -> [EventSummary]        // spec §6.4 AC2
  func find(identifier: String) async throws -> EventSummary?
  func find(stepTag: String) async throws -> EventSummary?                     // url = easyphone:<stepId> (D-225)
  func search(title: String?, near: Date?) async throws -> [EventSummary]      // targetRef resolution
  func save(_ e: EventInput, stepTag: String, existing: String?) async throws -> String // eventIdentifier
  func delete(identifier: String) async throws
}
protocol RemindersService: Sendable {
  func find(identifier: String) async throws -> ReminderSummary?
  func find(stepTag: String) async throws -> ReminderSummary?
  func save(_ r: ReminderInput, stepTag: String, existing: String?) async throws -> String
  func setCompleted(_ id: String, _ done: Bool) async throws     // reminder/complete, `completed` field (D-248)
  func snooze(_ id: String, to: Date) async throws
  func delete(identifier: String) async throws
}
protocol ContactsService: Sendable {
  func match(name: String) async throws -> [ContactMatch]   // DATA_MODEL §7.2 normalization + Nickname lookup
  func phoneNumbers(contactId: String) async throws -> [PhoneEntry]
}
protocol MessagesService: Sendable { var canSendText: Bool { get } }   // composer itself is a View (§5.3)
protocol CallService: Sendable { func start(e164: String) async throws }        // tel:// → handedOff only
protocol PlacesService: Sendable {
  func search(_ query: String, near: Coordinate?) async throws -> [PlaceResult]
  func openDirections(to: PlaceResult, app: MapsApp) async throws
}
protocol SystemService: Sendable {
  func open(_ url: URL) async -> Bool; func canOpen(_ url: URL) -> Bool; func copy(_ text: String)
}
```

### 4.3 Input & output
```swift
protocol SpeechService: Sendable {
  func start(locale: Locale) -> AsyncThrowingStream<Transcript, Error>   // partial + final, on device
  func stop() async
  func recordedAudio() async -> Data?          // m4a for /v1/transcribe fallback
}
protocol TTSService: Sendable { func speak(_ text: String, rate: Double) async; func stop() }
protocol OCRService: Sendable { func recognize(_ image: ImageData) async throws -> OCRResult }  // text + lines + boxes
```
`OCRService` live = `RoutingOCRService`: Vision first; if `vi` unsupported or result empty/low quality → `/v1/ocr`
(D-061). The quality threshold is config (`OCR_FALLBACK_MIN_CONFIDENCE`, P-24). `SpeechService` fallback to
`/v1/transcribe` is decided by the ViewModel when on-device recognition is unavailable or confidence is low.
### 4.4 Permissions & persistence
```swift
enum Capability: Sendable { case calendar, reminders, contacts, microphone, speech, camera, photos, location }
enum PermissionStatus: Sendable { case notDetermined, granted, limited, writeOnly, denied, restricted }
protocol PermissionManager: Sendable {
  func status(_ c: Capability) -> PermissionStatus
  func request(_ c: Capability) async -> PermissionStatus   // called only after the explainer screen (D-185)
}
@MainActor protocol TaskRepository {
  func draft(_ id: UUID) -> TaskDraft?; func save(_ d: TaskDraft)          // save = autosave (D-104)
  func steps(in states: Set<TaskState>) -> [(UUID, TaskStep)]           // launch verification
  func history(group: HistoryGroup) -> [TaskDraft]; func deleteClosed(); func wipeAll()   // deleteClosed: D-244
}
```
`LocalDataRepository` covers `SavedPlace`, `Nickname`, `AppSettings` (DATA_MODEL §5).
## 5. Task engine (`Core/Engine/`)
```
ParsedDraft ─▶ DraftBuilder ─▶ DeviceResolver ─▶ Validator ─▶ TaskStateMachine
                (defaults,      (contacts, places,  (§7.1)       (pure transition)
                 source=.ai)     conflicts, targetRef)                │
                                                                     ▼
                       Review ◀── TaskEngine (@MainActor, owns all mutations) ──▶ StepExecutor(kind)
                                        │                                       │
                                  TaskRepository (autosave)              Services (EventKit…)
```
- **`TaskEngine`** is the only writer of `TaskStep`. Every mutation = `apply(event)`: call `transition()`, on `nil` log and
  keep the state; else set `state`, `stateChangedAt`, append `history` (cap 50), handle hash rules (DATA_MODEL §3.4), save.
- **`DraftBuilder`**: `ParsedDraft` → `TaskDraft` (DATA_MODEL §6.2 mapping). Merges follow-up answers without
  overwriting `source = .user` fields (API_CONTRACT §7.1 Example B).
- **`DeviceResolver`**: `recipientName` → `ContactsService.match` → 1 match fills `contactId`/`phoneNumber`
  (`source = .device("contacts")`), else `Ambiguity(.contact)`. Skipped when `channel ≠ sms` (D-247).
  Saved-place labels → address. `update/delete` → `CalendarService.search` → `targetRef` or picker.
  Calendar conflicts → transient Review state.
- **`Validator`**: pure `validate(step) -> [ValidationIssue]` using DATA_MODEL §4.1; result emits `allRequiredFilled` /
  `missingRequiredField`. Recomputes `Field.required` when `channel` / `label` change.
- **Linked steps** (DATA_MODEL §3.3): on source-field edit the engine updates `.linked` fields and emits `userEdited`
  on those steps; "Xác nhận" of step N+1 is enabled only when step N is final, `handedOff` or `prepared`.
### 5.1 StepExecutor
```swift
enum ExecutionOutcome: Sendable {
  case verified(evidence: String)          // → actionVerified
  case handedOff(note: String)             // → outcomeUnknownHandoff
  case prepared                            // → dataPrepared (Phase 3)
  case needsUI(UIEffect)                   // engine keeps `processing`, ViewModel presents it (composer)
  case failed(code: String)                // → actionFailed, errorMessage from `error.<code>`
}
@MainActor protocol StepExecutor { func execute(_ step: TaskStep, draft: TaskDraft) async -> ExecutionOutcome }
```
Executors: `CalendarExecutor`, `RemindersExecutor`, `CallExecutor`, `SMSExecutor`, `PlaceExecutor`, `OCRConfirmExecutor`
(Phase 3: `HandoffExecutor`). `TaskEngine.confirm()` flow:
0. **Before** calling `confirm`, the ViewModel checks `permissions.status(capability)` for the step's kind.
   `notDetermined` → set `pendingPermission` → S18 explainer → `request()` → then `confirm()` (D-185).
   Denied/restricted → S18 denied variant; the user may still confirm to get the fallback path below.
1. Require `state == awaitingApproval`, no ambiguity, linked-step rule OK, network not needed (device actions are offline).
2. Store `approvedSnapshotHash`, `attempt += 1`, `apply(.userConfirmed)` → `processing`, **save before executing**.
3. Recompute hash; mismatch → `.failed("approval.mismatch")` (DATA_MODEL §3.4).
4. Check permission again; not granted (incl. `notDetermined`) → `.failed("permission.<capability>.denied")` (D-249)
   + offer fallback (copy text, "Mở Cài đặt", D-185). After using the fallback the user may tap "Tôi đã làm xong"
   (`failed` → `userMarkedDone`) or "Hủy" (`failed` → `cancelled`) (D-243).
5. **Idempotency check** (D-105): look up `resultEvidence`/`targetRef`/`stepTag`; already done → `.verified`.
6. Call the service, then **re-read** the item (calendar/reminder) → `.verified("ek:event:<id>")` (DATA_MODEL §3.5).
### 5.2 Evidence-less kinds
`CallExecutor` → `CallService.start` → `.handedOff("Cần hoàn tất cuộc gọi")`. Never `succeeded` (D-102).
`PlaceExecutor` for `place/open` → `PlacesService.openDirections` → `.handedOff(…)`.
Copy-to-Zalo (`SMSExecutor`, unverified channel, D-162) → `SystemService.copy` → `.handedOff(…)`.
### 5.3 SMS composer (UIKit bridge)
`SMSExecutor` returns `.needsUI(.composer(recipients:, body:))`. `ReviewViewModel` sets `pendingComposer`; the View shows
`MessageComposerView: UIViewControllerRepresentable` (D-014). Its delegate result goes back to
`engine.composerFinished(stepId, result)`: `.sent` → `actionVerified("msg:sent:<date>")`, `.failed` → `actionFailed`,
`.cancelled` → `userCancelled` + `composerDismissed` → `awaitingApproval` (D-222). App killed while composer open →
step stays `processing` → launch verification → `interrupted` → `unknown` (spec §5.2).
### 5.4 Launch verification & hand-off prompt
- `LaunchVerifier` (first `.active` per process): for each step in `processing` → `interrupted` → `unknown`; for each
  `unknown` with a verifiable kind → look up evidence/`stepTag` → `actionVerified` or stay `unknown` (D-125).
  A step left `unknown` shows "Tôi đã làm xong" and, for calendar/reminder, "Thử lại" (`unknown` → `retry`, D-243, D-250).
- `HandoffPromptCoordinator`: on `.active`, finds the newest `handedOff` step with `handoffPromptShown == false`, shows
  one sheet "Bạn đã … xong chưa?" → "Đã xong" (`userMarkedDone`) / "Chưa"; sets `handoffPromptShown = true` (D-242).
## 6. Data flows (iOS ↔ backend ↔ Supabase ↔ OpenAI)
### 6.1 Sign-in (Phase 0)
```
App ─ Supabase SDK ─▶ Supabase Auth (Google) ─▶ session (access + refresh token, Keychain)
App ─ GET /v1/me (Bearer) ─▶ Backend: verify JWT (sub) → upsert profiles (D-236) → plan + quota ─▶ MeResponse
App: AppState.session = .signedIn, entitlement = cached copy (display only)
```

### 6.2 Request → draft (Phase 1B, linked flow 2)
```
User speaks ─▶ SpeechService (vi-VN, on device) ─▶ editable transcript (never auto-sent, API_CONTRACT §7.4)
User taps send ─▶ ConversationVM: new IdempotencyKey ─▶ APIClient.parse
  Backend: auth → version → validate → idempotency (+attempt) → spend cap → reserve 1 unit (advisory lock)
         → build prompt (AI_PROMPTS §1) → OpenAI structured output (18 s budget) → validate (+1 repair) → post-process
         → commit tokens/cost → 200 ParsedDraft + X-Quota-*
App: DraftBuilder → DeviceResolver (contacts on device) → Validator → state needsInfo / awaitingApproval
     → autosave → Router: .review(draftId)
```
Follow-up: `needsInfo` → app asks **one** question (`followUpQuestion` or `followup.<kind>.<fieldId>`, chosen by D-281).
Only `Validator` decides whether to ask; a `followUpQuestion` with no validation issue is ignored.
A chip / picker answer is applied on device (no call, D-251). A typed/spoken answer is sent as a new `/v1/parse`
with `context` (new key, 1 unit) → `DraftBuilder.merge`.
### 6.3 Review → execute (calendar, offline-capable)
```
Review "Xác nhận" ─▶ TaskEngine.confirm ─▶ CalendarExecutor ─▶ EventKit save (url = easyphone:<stepId>)
  ─▶ re-read by identifier ─▶ actionVerified(ek:event:<id>) ─▶ succeeded ─▶ autosave ─▶ "Đã xong"
```
No backend call. Works with no network once the draft exists (D-074).
### 6.4 Photo → OCR → draft (Phase 1D, linked flow 1)
```
PhotosPicker/camera ─▶ save JPEG to Application Support/ocr/<draftId>.jpg 🔒
  ─▶ OCRService: Vision (vi) ── fallback ─▶ POST /v1/ocr (resized JPEG ≤ 2048 px, key A, 1 unit)
  ─▶ text empty? → retake screen, no /v1/extract call (saves quota)
  ─▶ POST /v1/extract (key B ≠ A, D-245; ocrText wrapped as <untrusted_content> by backend, 1 unit) ─▶ fields + spans
App: ocr step (fields source .ocr(span), box from Vision lines) → Review "Xem ảnh gốc"
     → "Tiếp tục" = userConfirmed on the ocr step (local:confirmed) → new step with .linked fields
       (calendarEvent, reminder, copyContactInfo)
```

### 6.5 Purchase (Phase 1F)
```
Paywall ─▶ PurchaseService.purchase(id, appAccountToken = userId) ─▶ StoreKit 2 ─▶ verified JWS
  ─▶ POST /v1/billing/verify ─▶ Backend: verify JWS chain, bundle, product, env, token == sub
     → upsert subscriptions ─▶ 200 MeResponse ─▶ AppState.entitlement ─▶ finish(transaction)
Apple ─▶ POST /v1/billing/notifications (JWS) ─▶ Backend: verify, dedupe, map status ─▶ 200
App learns the change on next GET /v1/me (launch / Settings / 402).
```
`Transaction.updates` is observed from app launch for the whole process lifetime (renewals, Ask to Buy, refunds).
### 6.6 Account deletion (Phase 1G)
```
Settings "Xóa tài khoản" ─▶ confirm sheet (+ cancel-subscription note) ─▶ DELETE /v1/me
  ─▶ Backend: Supabase Admin API delete auth user ─▶ FK cascade profiles/subscriptions/usage_events ─▶ 204
App: TaskRepository.wipeAll + LocalDataRepository.wipeAll + delete ocr/ ─▶ AuthService.signOut ─▶ sign-in screen
```

## 7. Backend architecture (`backend/app/`)
| Module | Responsibility |
|---|---|
| `main.py` | FastAPI app, routers, exception handlers (§9.3), request-id middleware, CORS off |
| `config.py` | `pydantic-settings`: `MODEL_*` (D-278), quotas, units, caps, URLs, `ENABLED_KINDS`, timeouts + budget (D-038, D-246) |
| `deps.py` | `Depends`: `current_user` (JWT), `client_version`, `idempotency_key`, `db` connection |
| `routers/` | `health.py`, `me.py`, `parse.py`, `extract.py`, `media.py` (ocr, transcribe), `billing.py` — thin |
| `schemas/` | Pydantic models (`extra="forbid"` on requests), `task_draft.json`, `field_catalog.json` (D-035) |
| `services/quota.py` | reserve / commit / refund, spend cap, `Quota` calc (API_CONTRACT §4) |
| `services/metering.py` | `metered()` pipeline, attempt numbers, time budget (§7.1) |
| `services/llm.py` | `LLMClient` wrapper: model from config, structured output, timeout, repair retry, token/cost |
| `services/prompt_context.py`, `untrusted.py`, `prompts/` | prompt assembly (AI_PROMPTS §1–§2) |
| `services/parse_service.py`, `extract_service.py` | call LLM + post-processing (API_CONTRACT §7.1, AI_PROMPTS §9) |
| `services/billing.py` | App Store JWS verification, subscription upsert, notification mapping |
| `services/accounts.py` | profile upsert, Supabase Admin API delete |
| `repositories/` | SQL for `profiles`, `subscriptions`, `usage_events` (no business rules) |
### 7.1 Metered request pipeline (one handler, reused)
```python
async def metered(endpoint, units, user, key, run):          # services/metering.py
    budget = Deadline(settings.REQUEST_BUDGET_SECONDS)        # 18 s (D-246)
    async with db.transaction():                             # step 4–6 (API_CONTRACT §4.3)
        await db.execute("select pg_advisory_xact_lock(hashtext($1))", user.id)
        row = await usage.find_or_create(user.id, key, endpoint)      # 24 h window; other endpoint → 422 (D-245)
        my_attempt = await usage.next_attempt(row)                    # attempt += 1, returns new number
        await spend_cap.check()                                       # 503 spend_cap
        await quota.reserve(user, row, units)                         # 402 quota_exceeded
    cost = Cost.zero()
    try:
        result, cost = await run(budget)                     # OpenAI call(s) outside the lock; budget-aware
        await usage.add_cost(row, cost)                      # tokens/cost always added
        return result
    except BaseException as e:                               # AppError, timeout, unexpected → refund (500 internal)
        await usage.add_cost(row, cost)
        await usage.refund_if_latest(row, my_attempt)        # units = 0 only if row.attempt == my_attempt (D-246)
        raise
```
- The OpenAI call is **outside** the DB transaction so a slow model never holds the lock (P-25).
- DB access for quota uses a direct Postgres connection (asyncpg) to the Supabase database, because advisory locks need
  a real transaction; the Supabase REST client is not used for this (P-26).
### 7.2 OpenAI client
- One `AsyncOpenAI` instance, key from env (D-051). SDK internal retries **off** (`max_retries=0`): retries are owned by
  our code so time budgets stay predictable (P-27).
- Per-call timeout = `min(LLM_TIMEOUT_SECONDS = 12, budget.remaining)`; the repair call runs only when
  `budget.remaining ≥ 5 s`, else `upstream_error`. One backend attempt therefore ends within 18 s, before the app's
  20 s timeout (D-127, D-246). Timeout / 5xx / 429 from OpenAI → `upstream_error` (503, retryable).
- Invalid structured output → one repair call (AI_PROMPTS §6) → still invalid → `llm_invalid_output` (502).
## 8. Concurrency model (Swift 6)
| Component | Isolation | Why |
|---|---|---|
| Views, ViewModels, `AppState`, `Router`, `TaskEngine`, `TaskRepository` | `@MainActor` | SwiftData main `ModelContext`; one writer = no races on steps |
| `APIClient` | `actor` | serializes token refresh (one refresh for parallel 401s) |
| Live services | `final class` + `Sendable`; EventKit store held in an `actor` | framework objects are not `Sendable` |
| `SpeechService`, `TTSService` | `@MainActor` (audio session) | AVAudioSession + UI-driven |
| Models / DTOs | `struct …: Sendable` | crossing isolation safely |
- Long work (`/v1/*`, OCR) runs in `Task {}` from the ViewModel; results return to the main actor before `TaskEngine` applies them.
- Cancellation: leaving a screen cancels its network `Task`; the draft is already saved, so nothing is lost.
- SwiftData work stays small on the main context (P-28); if launch verification gets slow, move it to a `@ModelActor`.
## 9. Error handling
### 9.1 Error taxonomy (iOS)
```swift
enum AppError: Error, Sendable {
  case network(NetworkFailure)                  // offline, timeout, TLS
  case api(code: String, retryable: Bool, details: APIErrorDetails?, requestId: String?)  // API_CONTRACT §3
  case service(ServiceError)                    // device frameworks
  case decoding(requestId: String?)             // contract bug
}
enum ServiceError: Error, Sendable {
  case permissionDenied(Capability), limitedAccess(Capability)
  case notFound, unavailable(String)            // e.g. "speech.vi.unavailable", "messages.cannotSend"
  case framework(code: String)                  // EKError etc., mapped to a stable code, e.g. "eventkit.saveFailed"
}
```
- Every error maps to (a) a **stable code** `<domain>.<reason>` (`permission.calendar.denied`, `eventkit.saveFailed`,
  `network.offline`) or an API code (`quota_exceeded`) (D-249), (b) a `UserMessage` via `error.<code>` in
  `Localizable.xcstrings`, (c) a UI behavior, (d) a step effect if inside an action.
- Raw `error.localizedDescription`, stack traces and backend `message` are never shown when a localized key exists.
### 9.2 Error → behavior table (iOS)
| Error | Where | UI | Step / draft effect |
|---|---|---|---|
| `network.*` after retries | parse / extract / ocr | "Không có mạng — bản nháp đã được lưu" + "Thử lại" | draft unchanged, autosaved |
| `401 unauthorized` | any API | silent refresh + retry once; still 401 → sign-in screen | drafts kept (D-104) |
| `402 quota_exceeded` | metered | Free → paywall; Premium → "hết lượt hôm nay" + `resetsAt` (D-241) | draft kept; device features work |
| `426 client_outdated` | any API | blocking "Cập nhật ứng dụng" | — |
| `429 rate_limited` | transcribe | switch to keyboard | transcript kept |
| `502 llm_invalid_output` | parse / extract | friendly error + "Thử lại" (new key) | draft kept |
| `503 upstream_error`, `500 internal` | AI | auto-retry (§10) → "Có lỗi, bản nháp đã được lưu" | draft kept |
| `503 spend_cap` | AI | "Dịch vụ AI tạm dừng" | device features work |
| `422 invalid_input`, decoding | any | generic error; log `requestId` | draft kept; `// bug` |
| `permission.<capability>.denied` | executor | explain + "Mở Cài đặt" + fallback (copy text) | step `failed`; then retry / "Tôi đã làm xong" / "Hủy" (D-243) |
| `eventkit.saveFailed` / verify error | executor | "Không thành công" + "Thử lại" | `failed` → `retry` → idempotency check |
| `approval.mismatch` | executor | "Thông tin đã thay đổi, vui lòng xác nhận lại" | `failed(approval.mismatch)` |
| app killed mid-action | lifecycle | "Chưa rõ kết quả" until verified | `unknown` → launch verification → retry allowed (D-243) |
| illegal transition | engine | none | state unchanged, `Logger.warning` |
### 9.3 Backend error handling
- One exception type `AppError(code, http_status, retryable, message_key, details)`; a global handler renders the
  envelope (API_CONTRACT §3.1) with `requestId` and the `Accept-Language` message.
- `RequestValidationError` → `422 invalid_input` with `details.field` (first error only, no input values).
- Unhandled exception → `500 internal`; log type + `requestId`, no content (D-059). Metered calls refund (§7.1).
- OpenAI errors are mapped in `services/llm.py` only; routers never see SDK exceptions.
- Webhook: invalid JWS → `400`; any processed or ignored notification → `200` (avoid endless Apple retries).
## 10. Retry strategy (all levels)
| Level | Who retries | Trigger | Policy | Idempotency guard |
|---|---|---|---|---|
| HTTP (app) | `APIClient` | network error, `500`, `503 upstream_error` | 20 s timeout, 2 retries, backoff 1 s / 3 s + jitter (D-127) | same `Idempotency-Key` for that endpoint call (D-230, D-245) |
| Auth (app) | `APIClient` | `401` | refresh token once, retry once | same key |
| Rate limit (app) | `APIClient` | `429` | wait `Retry-After`, 1 attempt; transcribe → keyboard | — |
| User "Thử lại" | ViewModel | final failure, `502` | new user action | **new** key |
| LLM output (backend) | `services/llm.py` | schema-invalid output | 1 repair call if ≥ 5 s budget left, 0 extra units (D-054, D-246) | same usage row |
| OpenAI transport (backend) | none (SDK `max_retries=0`) | timeout/5xx/429 | → `503 upstream_error`, app retries | refund on failure, last attempt wins (D-231, D-246) |
| Step action (device) | user via `retry` event | `failed` or `unknown` | → `awaitingApproval` → confirm again (D-243) | evidence / `easyphone:<stepId>` lookup (D-105) |
| Interrupted action | `LaunchVerifier` | `processing`/`unknown` at launch | verify once per launch | evidence lookup |
| StoreKit | StoreKit + app | `verify` network/`400`/`5xx` | transaction left unfinished → redelivered | upsert by `original_transaction_id` |
| App Store webhook | Apple | non-2xx | Apple's schedule | dedupe `notificationUUID`, out-of-order rule |
Never retried automatically: any send/call/delete action, `402`, `403`, `413`, `422`, `426`, `502`, `503 spend_cap`.
### 10.1 Idempotency key lifecycle (app)
```swift
struct IdempotencyKey: Sendable { let value: String = UUID().uuidString.lowercased() }
// created by the ViewModel for each endpoint call of a user action (send = 1 key; photo = 1 key for /v1/ocr
// + 1 key for /v1/extract, D-245); passed down; reused only by RetryPolicy for that same call.
```
The key lives only in memory for that call. A relaunch or "Thử lại" creates a new key (a new user action).
## 11. Offline & resilience
- Every field edit → `TaskEngine.edit` → `TaskRepository.save` immediately (D-104). `.background` flushes pending saves.
- Offline: parse/extract/ocr fail fast with the offline message; Review, execution of device actions, History, calls to
  resolved contacts all work offline (D-074).
- `CachedEntitlement` is display-only; the app never blocks a request locally based on it (API_CONTRACT §4.5).
- Gmail token expiry (Phase 2) follows the same pattern: state kept, "Kết nối lại Gmail".
## 12. Security & privacy boundaries
- App secrets: only Supabase URL + anon key (in `Config.xcconfig`, D-207). Session tokens in Keychain via the SDK.
- Backend secrets in env: `OPENAI_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`, DB URL, Apple certs.
- 🔒 data never leaves `Core/Services/Live/` + SwiftData. DTO test asserts no 🔒 keys (API_CONTRACT §11).
- Untrusted content (OCR/email) only reaches the LLM through `wrap_untrusted()` (AI_PROMPTS §2.2).
- OCR images stay on device unless the `/v1/ocr` fallback runs; the backend never stores images or audio.
- Logging: iOS `os.Logger` categories `engine`, `network`, `services`, `billing` with `privacy: .private` for any
  user value; backend logs ids, endpoint, status, units, tokens, cost, latency, `promptVersion` only (D-059, P-22).
## 13. Testing architecture
| Target | What | Tools |
|---|---|---|
| `EasyPhoneTests` | state machine, validator, hash, DraftBuilder merge, DeviceResolver with mock contacts, executors with mock services, retry policy with a mock `URLProtocol`, date resolution with `MockClock` | Swift Testing (D-204) |
| `EasyPhoneUITests` | linked flows 1 & 2 with `AppEnvironment.mock(.uiTest)` via launch argument `-uiTestScenario` | XCUITest |
| `backend/tests` | contract fixtures, quota/idempotency/attempt/budget, billing, prompts (mocked LLM); `-m live` for real model | pytest (D-039) |
- Contract fixtures in `backend/tests/fixtures/contract/` are shared by both sides (API_CONTRACT §11).
- `MockAPIClient` serves those fixtures; `MockScenario` covers offline, quota exceeded, permission denied, 3 "Minh".
### 13.1 Build order of architecture pieces (matches spec §4)
| Phase | Architecture work |
|---|---|
| 0 | `AppEnvironment`, `AppState`, `Router`, SwiftData container, `AuthService`, `APIClient` (health, me), backend skeleton + `deps.py` |
| 1A | Models, `TaskStateMachine`, `Validator`, `TaskEngine`, `TaskRepository`, Review + History |
| 1B | `SpeechService`, `TTSService`, `/v1/parse` + metering + `LLMClient`, `DraftBuilder` |
| 1C | device services + executors, `DeviceResolver`, `PermissionManager`, composer bridge, hand-off prompt, `LaunchVerifier` |
| 1D | `OCRService` (Vision + fallback), `/v1/ocr`, `/v1/extract` |
| 1E | `StartListeningIntent`, App Shortcuts, Control widget, widgets, deep link |
| 1F | `PurchaseService`, billing router, notifications, paywall, quota UI |
| 1G | account deletion end-to-end, privacy manifest, release config |
## 14. Proposals — approved by the owner as D-258 – D-265 (`DECISIONS.md` §12.4; D-258 supersedes D-019)
| ID | Proposal | Why |
|---|---|---|
| P-23 | `Core/StateMachine/` lives inside `Core/Engine/`; add `Core/Services/` (protocols + `Live/` + `Mock/`) | keeps engine pieces together; spec §3.2 layout otherwise unchanged |
| P-24 | `OCR_FALLBACK_MIN_CONFIDENCE` (app config, default 0.5 mean line confidence) decides Vision → `/v1/ocr` | makes D-061 "choose at runtime" concrete; tunable when D-060 is locked |
| P-25 | OpenAI call runs outside the DB transaction; reserve/refund in short transactions | the advisory lock is never held during a slow model call |
| P-26 | Backend uses asyncpg over the Supabase Postgres connection string for quota/usage; Admin API only for auth user deletion | advisory locks need real transactions |
| P-27 | OpenAI SDK `max_retries=0`, `LLM_TIMEOUT_SECONDS=12` (config) inside the D-246 18 s budget; app owns retries | fits the 20 s client timeout (D-127); no hidden retries |
| P-28 | `TaskEngine` + `TaskRepository` are `@MainActor` on the main `ModelContext` | single writer for steps; simplest Swift 6–safe option |
| P-29 | `ExecutionOutcome.needsUI` pattern for system UI (SMS composer, future pickers) | engine stays UI-free; ViewModel presents UIKit bridges |
| P-30 | `UserMessage { key, args }` is the only error/notice type a View renders | guarantees Vietnamese, localized, jargon-free text (D-184) |
