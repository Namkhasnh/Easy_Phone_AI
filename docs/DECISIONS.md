# EasyPhone AI — DECISIONS.md

> Audience: an AI coding agent (Claude Code) working in Xcode on macOS, and any later spec file.
> This file is the **single source of truth for locked decisions**. `EasyPhone-AI-Spec.md` and every
> other doc (DATA_MODEL, API_CONTRACT, AI_PROMPTS, ARCHITECTURE, UI_SCREENS, PROGRESS, CLAUDE.md) must follow it (D-279).
> If another file contradicts this one, **this file wins** — flag the conflict with `// TODO(decision):`.

---

## 0. How to use this file

- **Status values:** `LOCKED` (do not change without the owner), `DEFAULT` (agent may use it now;
  owner can override later), `OPEN` (must be decided before the listed phase — do not guess silently).
- Each decision has an ID (`D-xxx`). Reference IDs in code comments and commits,
  e.g. `// D-012: never claim success for handed-off steps`.
- Changing a `LOCKED` decision: add a new entry that **supersedes** the old ID; never edit history.
- When a choice is not covered here or in the spec: pick the simplest option, mark it `DEFAULT`
  in §12 (Decision log), and leave `// TODO(spec):` in code.

---

## 1. Product identity

| ID | Decision | Status |
|---|---|---|
| D-001 | App name: **EasyPhone AI** (bundle display name "EasyPhone"). URL scheme `easyphone://`. | LOCKED |
| D-002 | Target users: **everyone, including elderly and non-technical users**. Design for the weakest user first. | LOCKED |
| D-003 | Primary language **Vietnamese (`vi`)**; secondary **English (`en`)**. All UI strings in `Localizable.xcstrings`. | LOCKED |
| D-004 | Core loop: input (voice / text / photo) → AI **editable task draft** → user **Review & Confirm** → execute as far as iOS allows → guide the rest. | LOCKED |
| D-005 | Distribution goal: **public App Store release**. TestFlight first. All App Store rules (§10 of spec) apply from day one. | LOCKED — superseded by D-282 |

**Consequence for the agent:** every feature must work on a real iPhone with real data, in Vietnamese,
with large text and VoiceOver. No "English-only first" shortcuts.

---

## 2. Platform & iOS stack

| ID | Decision | Status |
|---|---|---|
| D-010 | Platform: **iPhone only** (no iPad layout, no Mac Catalyst, no watchOS) for MVP. | LOCKED |
| D-011 | Minimum deployment target: **iOS 18.0**. | LOCKED |
| D-012 | Vietnamese Siri phrases require **iOS 18.4+**; on 18.0–18.3 App Shortcuts still exist but Vietnamese phrases may not trigger. Guard with `#available` and keep English phrases as fallback. | LOCKED |
| D-013 | Language: **Swift 6** with strict concurrency enabled. | LOCKED |
| D-014 | UI: **SwiftUI** only. UIKit only via `UIViewControllerRepresentable` where required (e.g. `MFMessageComposeViewController`). | LOCKED |
| D-015 | Architecture: **MVVM with `@Observable`** view models; system frameworks behind **protocol services** (`CalendarService`, `ContactsService`, `RemindersService`, `PlacesService`, `SpeechService`, `OCRService`…) with mock implementations for tests and previews. | LOCKED |
| D-016 | Local persistence: **SwiftData** (tasks, drafts, saved places, nicknames, history, settings). | LOCKED |
| D-017 | Third-party iOS dependencies: **avoid by default**. Allowed exception: the official **Supabase Swift SDK** (auth + session). Anything else needs a `DEFAULT` entry in §12 with a reason. | DEFAULT |
| D-018 | Package manager: **Swift Package Manager** only (no CocoaPods/Carthage). | LOCKED |
| D-019 | Project layout: as in spec §3.2 (`App/`, `Core/`, `Features/`, `Intents/`, `Widgets/`, `Resources/`, `backend/`). | LOCKED |

### 2.1 System frameworks (all on-device)

| Area | Framework / API | Notes |
|---|---|---|
| Calendar, Reminders | EventKit | `requestFullAccessToEvents()`, `requestFullAccessToReminders()`; handle write-only |
| Contacts | Contacts, ContactsUI | Handle iOS 18 **limited access** (`ContactAccessButton`) |
| SMS / iMessage | MessageUI | Only `.sent` result = sent |
| Call | `tel://` URL | Always `handedOff`, never `succeeded` |
| Places / maps | MapKit (`MKLocalSearch`) | Apple Maps default; Google Maps if installed |
| OCR | Vision `VNRecognizeTextRequest` | Check Vietnamese support at runtime |
| Speech-to-text | Speech `SFSpeechRecognizer(locale: vi-VN)` | Backend fallback |
| Text-to-speech | AVFoundation `AVSpeechSynthesizer` (`vi-VN`) | Always stoppable |
| Siri / Action Button / Control Center | App Intents, App Shortcuts, Control widget | `StartListeningIntent` |
| Widgets | WidgetKit | Deep link `easyphone://listen` |
| Purchases | StoreKit 2 | Server-verified |
| Sign in | Google via Supabase (D-283; Sign in with Apple dropped for the thesis) | |

---

## 3. Backend & infrastructure

| ID | Decision | Status |
|---|---|---|
| D-030 | Backend language/framework: **Python 3.12 + FastAPI**, deployed as **one service** (no microservices). | LOCKED |
| D-031 | Database + auth: **Supabase** (Postgres + Supabase Auth). | LOCKED |
| D-032 | Every endpoint except webhooks requires a **Supabase JWT**; backend verifies it and uses `sub` as user id. | LOCKED |
| D-033 | **Row Level Security ON** for every Supabase table; users read only their own rows; account deletion cascades. | LOCKED |
| D-034 | API versioning: all routes under `/v1/`. Breaking changes → `/v2/`. | LOCKED |
| D-035 | Single JSON schema source: `backend/app/schemas/task_draft.json`, mirrored by Swift `TaskDraft` types. Change both in the same commit. | LOCKED |
| D-036 | Backend hosting provider (Fly.io / Render / Railway / other). | OPEN — needed by Phase 0 |
| D-037 | Until D-036 is locked: run backend locally + expose via a tunnel for device testing; keep config in env vars so hosting is swappable. | DEFAULT |
| D-038 | Backend config via environment variables (`.env` locally, never committed). Model names, quotas, spend cap live in config, not code. | LOCKED |
| D-039 | Backend tests: **pytest**; quota logic and billing verification must have tests. | LOCKED |

### 3.1 Supabase tables (MVP)

```
profiles(id uuid pk = auth.uid, created_at, locale)
subscriptions(user_id, product_id, original_transaction_id, expires_at, status, environment)
usage_events(id, user_id, endpoint, units, idempotency_key, attempt, tokens_in, tokens_out, cost_usd, created_at)   -- units: D-223, idempotency_key: D-230/D-245, attempt: D-246
gmail_accounts(id, user_id, email, encrypted_refresh_token, created_at)   -- Phase 2 only
```

Do **not** create `gmail_accounts` before Phase 2. Full column definitions: `DATA_MODEL.md` §9.

---

## 4. AI provider & data boundaries

| ID | Decision | Status |
|---|---|---|
| D-050 | AI provider: **OpenAI API**, called **only from the backend**. | LOCKED |
| D-051 | **No API key in the app**, ever — not in code, plist, xcconfig, or obfuscated. | LOCKED |
| D-052 | Exact model names (text, vision, transcription) — test Vietnamese quality, latency, cost. | OPEN — needed by Phase 1B |
| D-053 | Model names stored in backend config (`MODEL_PARSE`, `MODEL_EXTRACT`, `MODEL_VISION`, `MODEL_TRANSCRIBE`). Agent must not hard-code a model string. | LOCKED |
| D-054 | Intent parsing uses **structured outputs** with the `task_draft.json` schema. Invalid JSON → **one** repair retry → friendly error. | LOCKED |
| D-055 | **On-device first** for STT, TTS, OCR, contacts, calendar, reminders, maps. Backend only as fallback or for LLM work. | LOCKED |
| D-056 | **Minimal data to backend**: send the name "Minh", not the contact list; send conflict results, not the calendar. | LOCKED |
| D-057 | **Untrusted content** (OCR, email, web) goes to the LLM inside `<untrusted_content>` tags; it can fill fields but never trigger actions or change behavior. | LOCKED |
| D-058 | Requests send `now` (ISO 8601) + device `timezone` + `locale`; relative dates are resolved against them. Ambiguous dates → `needsInfo`. | LOCKED |
| D-059 | Do not log raw user content in production logs; log only ids, endpoint, token counts, cost. | LOCKED |
| D-060 | Whether on-device Vision OCR is good enough for Vietnamese. | OPEN — needed by Phase 1D |
| D-061 | Until D-060 is locked: implement on-device OCR **and** `/v1/ocr` fallback behind one `OCRService` protocol; choose at runtime. | DEFAULT |

---

## 5. Accounts & authentication

| ID | Decision | Status |
|---|---|---|
| D-070 | **Account required** to use AI features (AI costs money and is metered per user). | LOCKED |
| D-071 | Sign-in methods: **Sign in with Apple + Google**, both via Supabase Auth. Apple is always shown whenever Google is (App Store rule). | LOCKED — superseded by D-283 |
| D-072 | No email/password sign-up in MVP. | DEFAULT |
| D-073 | In-app **account deletion** (`DELETE /v1/me`) deletes all server data; local data wiped on device. | LOCKED |
| D-074 | Device-only features (view calendar, call a saved contact, history) should still work when quota is exhausted or offline once signed in. | LOCKED |

---

## 6. Business model & billing (paid plan)

| ID | Decision | Status |
|---|---|---|
| D-080 | Business model: **account required + paid subscription**, with a **Free tier** that has a small AI quota. | LOCKED |
| D-081 | Plans: **Free** (small **daily** AI quota) and **Premium** (auto-renewable, **monthly** and **yearly**). | LOCKED |
| D-082 | Payments only through **StoreKit 2** in-app purchase. No external payment links. | LOCKED |
| D-083 | Purchase sets `appAccountToken = Supabase user id`; app sends the signed transaction to `POST /v1/billing/verify`. | LOCKED |
| D-084 | Backend handles **App Store Server Notifications V2** (`POST /v1/billing/notifications`) for renewal, expiry, refund, revoke. | LOCKED |
| D-085 | **Backend is the single source of truth** for plan + quota. App never decides entitlement locally (it may cache for display). | LOCKED |
| D-086 | Quota check happens **before** calling OpenAI; one `/v1/parse` call = 1 quota unit. Usage logged in `usage_events`. | LOCKED |
| D-087 | **Global monthly spend cap** in backend config; when hit, return `503` with a friendly Vietnamese message. | LOCKED |
| D-088 | Quota exceeded → AI parsing shows the **paywall**; device-only features keep working. (Premium case: D-241.) | LOCKED |
| D-089 | Paywall shows price, period, what is included, **"Khôi phục giao dịch"**, Terms and Privacy links. | LOCKED |
| D-090 | Free quota size, Premium prices, free trial yes/no. | OPEN — needed by Phase 1F |
| D-091 | Until D-090 is locked: `FREE_DAILY_QUOTA=10`, product ids `easyphone.premium.monthly` / `easyphone.premium.yearly`, no trial. Values in config + `.storekit` test file only. | DEFAULT |
| D-092 | Which endpoints consume quota beyond `/v1/parse` (`/v1/extract`, `/v1/ocr`, `/v1/transcribe`). | OPEN — needed by Phase 1F |
| D-093 | Until D-092 is locked: `/v1/extract` and `/v1/ocr` = 1 unit each; `/v1/transcribe` = free but rate-limited. | DEFAULT |

---

## 7. Safety & behavior rules (product-level, apply to all code)

| ID | Decision | Status |
|---|---|---|
| D-100 | **Never act without confirmation.** Create/edit/delete/send/hand-off needs explicit confirm on the Review screen. | LOCKED |
| D-101 | **Editing after approval invalidates it** → step returns to `awaitingApproval` (hash reset). | LOCKED |
| D-102 | **Never claim unverifiable success.** Opened Grab ≠ booked; opened composer ≠ sent; `tel://` ≠ called. | LOCKED |
| D-103 | **No background or automatic sending** of SMS, email, or calls. | LOCKED |
| D-104 | **Drafts survive everything** (kill, offline, app switch, token expiry). Autosave on every field change. | LOCKED |
| D-105 | **Idempotent retries**: verify an action didn't already happen (e.g. EventKit lookup by stored identifier) before retrying. | LOCKED |
| D-106 | **Never auto-pick** among ambiguous contacts or dates — always show a picker. | LOCKED |
| D-107 | "Complete reminder" is the only one-tap mutation (with undo toast); everything else goes through Review. | LOCKED |
| D-108 | Destructive actions (delete) always require a **tap**, even in voice mode. | LOCKED |
| D-109 | Third-party apps (Zalo, Grab, Be…) are only opened if listed in `SupportedServices.json` with `verified: true`. | LOCKED |

---

## 8. Task engine

| ID | Decision | Status |
|---|---|---|
| D-120 | One user request = one `TaskDraft` with one or more `TaskStep`s; **each step has its own state** and is confirmed/reported separately. | LOCKED |
| D-121 | States: `draft, needsInfo, awaitingApproval, processing, prepared, handedOff, succeeded, unknown, failed, cancelled, userMarkedDone`. | LOCKED |
| D-122 | Final states: `succeeded, failed, cancelled, userMarkedDone`. `failed` may be retried → `awaitingApproval`. | LOCKED |
| D-123 | State machine is a **pure function** `transition(state, event) -> TaskState?`; illegal transitions return `nil` and are logged; exhaustive unit tests required. Transition table = spec §5.2 + D-222 (full table in `DATA_MODEL.md` §1.5). | LOCKED |
| D-124 | `succeeded` requires **evidence** stored in `resultEvidence` (e.g. `EKEvent.eventIdentifier`). | LOCKED |
| D-125 | On launch, steps in `processing`/`unknown` run verification. | LOCKED |
| D-126 | Field confidence `< 0.7` → highlighted for review. OCR fields link to their source image region. | LOCKED |
| D-127 | Network: timeout **20s**, **2 retries** with exponential backoff, then "Không có mạng — bản nháp đã được lưu". | LOCKED |

---

## 9. Scope by phase (what is in, what is deferred)

| ID | Decision | Status |
|---|---|---|
| D-140 | **MVP = Phases 0 → 1G.** Build strictly in order; a phase starts only after the previous one meets its exit criteria (spec §4). | LOCKED |
| D-141 | **Gmail is Phase 2**, not MVP. | LOCKED |
| D-142 | **Ride & food handoff is Phase 3**, not MVP. | LOCKED |

### 9.1 Phase map

| Phase | Scope |
|---|---|
| 0 | Skeleton, SwiftData, backend hello-world, Supabase auth (Google, D-283), APIClient |
| 1A | TaskDraft model, state machine, Review screen, persistence, History |
| 1B | Home, text + voice input, TTS, `/v1/parse` |
| 1C | Calendar, Reminders, Contacts, Call, SMS, Places |
| 1D | OCR (camera/photo → text → fields → draft) |
| 1E | App Shortcuts (Siri), Action Button, Control Center, widgets |
| 1F | StoreKit 2, paywall, server verification, quotas |
| 1G | Demo prep: account deletion, privacy manifest, accessibility + resilience pass, demo script (D-284) |
| 2 | Gmail |
| 3 | Ride & food handoff |

### 9.2 Gmail decisions (Phase 2 — do not build earlier)

| ID | Decision | Status |
|---|---|---|
| D-150 | No Gmail code, scopes, tables, or UI before Phase 2. In MVP, Settings may show "Gmail — sắp có" (disabled). | LOCKED |
| D-151 | OAuth handled **by the backend**; refresh tokens stored **encrypted server-side**; never on device. | LOCKED |
| D-152 | Multiple Gmail accounts supported; every result shows its source account. | LOCKED |
| D-153 | **No send API** in Phase 2: reply drafts stay in EasyPhone → edit / copy / open Gmail or `mailto:`. | LOCKED |
| D-154 | Summaries in Vietnamese, each point cites its source message. | LOCKED |
| D-155 | Gmail read scopes are **restricted**; run in Google **Testing mode** until verification passes. | LOCKED |
| D-156 | Google OAuth verification plan (security assessment, timeline, cost). | OPEN — needed by Phase 2 |

### 9.3 Handoff decisions (Phase 3)

| ID | Decision | Status |
|---|---|---|
| D-160 | EasyPhone **prepares** ride/food requests only; it never books, pays, shows price, or says "đã đặt". | LOCKED |
| D-161 | Verified service list (Zalo, Grab, Be, Xanh SM, ShopeeFood, GrabFood) with URL schemes. | OPEN — Zalo needed by 1C, others by Phase 3 |
| D-162 | Until D-161 is locked: `SupportedServices.json` ships with all services `verified: false` → copy-to-clipboard + step-by-step guide only. | DEFAULT |

### 9.4 Explicitly out of scope (MVP)

- Direct ride/food booking, payment, price comparison, order tracking.
- Sending email via API, Outlook, auto-detecting emails that need replies.
- Recurring events/reminders, invitations, others' free time.
- Multi-page OCR, PDFs, receipt analysis, translation.
- User-saved workflows, scheduled summaries, proactive automation.
- Always-on custom wake word; UI automation of other apps.
- iPad, Mac, Apple Watch, Android, web app.

If a user asks for an out-of-scope feature, show **"Chưa hỗ trợ"** — do not partially implement it.

---

## 10. Entry points (Siri-like invocation)

| ID | Decision | Status |
|---|---|---|
| D-170 | Entry points: app icon, **App Shortcuts / Siri phrase**, **Action Button**, **Control Center control**, Home & Lock Screen **widgets**. All open the app in **listening mode**. | LOCKED |
| D-171 | Siri phrases must contain the app name, e.g. "EasyPhone ơi", "Mở EasyPhone" (+ English equivalents). | LOCKED |
| D-172 | One shared intent: `StartListeningIntent`; widgets use deep link `easyphone://listen`. | LOCKED |
| D-173 | No always-listening wake word (iOS does not allow it for third-party apps). | LOCKED |

---

## 11. Accessibility, UX & App Store

| ID | Decision | Status |
|---|---|---|
| D-180 | Every core flow completable with **text + buttons only** (no voice required). | LOCKED |
| D-181 | Dynamic Type up to **AX5** with no truncated buttons; VoiceOver labels on every control. | LOCKED |
| D-182 | Primary tap targets **≥ 56pt**, full width; **max 2 primary buttons** per screen (Review screen: "Xác nhận" primary, "Sửa"/"Hủy" secondary). Home mic button ≥ 120pt. | LOCKED |
| D-183 | Contrast ≥ 4.5:1; state never shown by color alone (icon + text). | LOCKED |
| D-184 | Plain Vietnamese, short sentences, no jargon ("Xác nhận", not "Submit"). | LOCKED |
| D-185 | Permissions requested **only on first use**, after a Vietnamese explainer screen; denial → explain what still works + "Mở Cài đặt". | LOCKED |
| D-186 | Usage descriptions (Info.plist) in Vietnamese for microphone, speech, camera, photos, calendars, reminders, contacts, location. | LOCKED |
| D-187 | Ship `PrivacyInfo.xcprivacy`; App Privacy labels state contacts/calendar are processed on device; disclose third-party AI provider. | LOCKED |
| D-188 | Privacy policy + Terms URLs required in app and App Store Connect before TestFlight external testing. | LOCKED — relaxed by D-284 (in-app text only) |
| D-189 | Demo/simulated data always labeled **"Dữ liệu mẫu"**. | LOCKED |

---

## 12. Development workflow

| ID | Decision | Status |
|---|---|---|
| D-200 | Development tool: **Claude Code + Xcode on the owner's Mac** (vibe coding). Docs are written for an AI agent. | LOCKED |
| D-201 | Docs language: **English**; each doc **Markdown, under 500 lines**. UI strings remain Vietnamese. | LOCKED |
| D-202 | Doc hierarchy: `DECISIONS.md` (this) → `EasyPhone-AI-Spec.md` → feature/tech docs (`DATA_MODEL.md` → `API_CONTRACT.md` …). Later docs must not re-decide anything here. | LOCKED |
| D-203 | Version control: **git**, small commits, one feature/fix per commit, commit message references phase + decision ids when relevant. | DEFAULT |
| D-204 | Testing: **Swift Testing** (`@Test`) for unit tests, XCUITest for UI flows 1 & 2; pytest for backend. | DEFAULT |
| D-205 | Required unit tests before MVP done: state machine, relative date resolution, Vietnamese contact matching (diacritic-insensitive), quota logic. | LOCKED |
| D-206 | Every new screen gets a SwiftUI `#Preview` using mock services. | DEFAULT |
| D-207 | Secrets (Supabase keys, OpenAI key, App Store shared secrets) never committed; `.gitignore` covers `.env`, `*.p8`, `Secrets.xcconfig`. Only the Supabase **anon** key + URL may be in the app. | LOCKED |
| D-208 | Environments: `Debug` → local/dev backend + StoreKit config file; `Release` → production backend + App Store Sandbox/production. | DEFAULT |

### 12.1 Data model decisions (detail in `DATA_MODEL.md`)

| ID | Decision | Status |
|---|---|---|
| D-220 | Field labels are **not stored**; computed from `labelKey` (`field.<kind>.<id>`) in `Localizable.xcstrings`. Refines spec §5.1 `Field.label`. | DEFAULT |
| D-221 | `TaskStep` has `operation: TaskOperation` (`create, update, delete, complete, snooze, open, prepare`). | DEFAULT |
| D-222 | Extra transition: `processing` + `userCancelled` with `composerDismissed` → `awaitingApproval` (SMS composer `.cancelled`, spec §6.8 AC2). | DEFAULT |
| D-223 | `usage_events.units int` stores the quota cost of each request (D-086, D-093). | DEFAULT |
| D-224 | Quota day boundary = calendar day in `QUOTA_DAY_TZ` (config, default `Asia/Ho_Chi_Minh`). | DEFAULT |
| D-225 | Store `easyphone:<stepId>` in the EventKit item `url` for idempotent lookup (D-105). | DEFAULT |
| D-226 | OCR "save contact info" in MVP = copy name + phone to clipboard; no Contacts write. | DEFAULT |

### 12.2 API contract decisions (detail in `API_CONTRACT.md`)

| ID | Decision | Status |
|---|---|---|
| D-230 | Metered POSTs (`/v1/parse`, `/v1/extract`, `/v1/ocr`) require an `Idempotency-Key` header (UUID, reused across automatic retries of one user action). One `usage_events` row per `(user_id, idempotency_key)`, 24 h window. A user action is charged **at most once**, and only if its last attempt returned 2xx. | DEFAULT |
| D-231 | Quota is **reserved** (row inserted with `units`) before the OpenAI call, inside a per-user advisory lock; **refunded** (`units = 0`, tokens/cost kept) on any non-2xx. `200` responses with `unsupported` or `followUpQuestion` are charged. | DEFAULT |
| D-232 | Premium has a fair-use daily limit `PREMIUM_DAILY_QUOTA = 200` (config). Final numbers remain part of D-090. | DEFAULT |
| D-233 | Error envelope = `{ error: { code, message, retryable, requestId, details? } }`. Extra codes: `billing_account_mismatch` (403), `billing_invalid` (400), `not_found` (404), `payload_too_large` (413), `client_outdated` (426), `rate_limited` (429), `upstream_error` (503). The app shows its own `error.<code>` string; `message` is a fallback. | DEFAULT |
| D-234 | Responses carry `X-Request-Id`; metered endpoints and `/v1/me` also carry `X-Quota-Limit`, `X-Quota-Remaining`, `X-Quota-Resets-At`. | DEFAULT |
| D-235 | `GET /v1/health` without auth for Phase 0 checks and uptime monitoring. | DEFAULT |
| D-236 | `profiles` row is auto-created (upsert) on a user's first authenticated request; no sign-up endpoint. | DEFAULT |
| D-237 | `/v1/transcribe` rate limit `TRANSCRIBE_PER_HOUR = 30` per user (config) → `429 rate_limited`. | DEFAULT |
| D-238 | Request text limits: `text` ≤ 2000 chars, `ocrText` ≤ 10 000 chars. Transcribe `confidence` may be `null`. | DEFAULT |
| D-239 | `/v1/billing/verify`: if `appAccountToken` ≠ JWT `sub` **and** the token's user no longer exists (account deleted), reassign the subscription to the current user; otherwise `403 billing_account_mismatch`. | DEFAULT |
| D-240 | Dev backend accepts StoreKit transactions with environment `Xcode` (Debug builds using the local `.storekit` file), verified with the Xcode StoreKit test certificate, only when `ALLOW_XCODE_STOREKIT=true`. Never in production. `subscriptions.environment` allows `Xcode`. | DEFAULT |
| D-241 | Refines D-088: a **Premium** user over the daily quota sees "Bạn đã dùng hết lượt hôm nay" + reset time, not the paywall. Free users still see the paywall. | DEFAULT |
| D-242 | **Return prompt for hand-offs:** when the app becomes active again after a step went `handedOff` (call, directions, copy-to-other-app SMS, ride/food), show **one** question with two buttons, e.g. "Bạn đã gọi xong chưa?" → **"Đã xong"** (`userMarkedDone`) / **"Chưa"** (stays `handedOff`, shown in History). Asked once per hand-off; "có" accepted in voice mode. Never auto-complete. Also adds transition `prepared` + `userMarkedDone` → `userMarkedDone` (copy-guide path, D-162). | DEFAULT |

### 12.3 Cross-doc logic review, round 2 (detail in the docs named)

| ID | Decision | Status |
|---|---|---|
| D-243 | Extends D-123 table: `failed` + `userCancelled` → `cancelled`; `failed` + `userMarkedDone` → `userMarkedDone` (user finished it another way, e.g. a copy fallback); `unknown` + `retry` → `awaitingApproval` (idempotency check first, D-105). `failed` stays final for the state machine but is not "closed" (D-244). (DATA_MODEL §1.5) | DEFAULT |
| D-244 | **Closed** states = `succeeded, cancelled, userMarkedDone`. "Việc chưa xong" (Home, widget count, toasts) = drafts whose History group is "Cần bạn làm tiếp" or "Đang chờ". "Xóa lịch sử" deletes only drafts whose steps are all closed. `currentStep` = first step by `order` that is not closed and not `handedOff`; none → last step. (DATA_MODEL §3.2, §8) | DEFAULT |
| D-245 | `Idempotency-Key` is per **endpoint call** of one user action: e.g. a photo action sends one key to `/v1/ocr` and a different key to `/v1/extract`. A key reused on a different endpoint → `422 invalid_input` (`details.reason = "idempotencyKeyEndpointMismatch"`). Refines D-230. (API_CONTRACT §4.4) | DEFAULT |
| D-246 | Backend time budget per attempt `REQUEST_BUDGET_SECONDS = 18` (< app 20 s, D-127). LLM call timeout = `min(LLM_TIMEOUT_SECONDS = 12, remaining)`; the repair call runs only if ≥ 5 s remain, else `503 upstream_error`. `usage_events.attempt` is incremented under the lock; only the attempt that still holds the latest `attempt` number may commit or refund units ("last attempt wins", D-230). (API_CONTRACT §4.3–4.4, ARCHITECTURE §7) | DEFAULT |
| D-247 | `channel = "sms"` is built in and always valid; any other `channel` / `service` id must exist in `SupportedServices.json`. When `channel ≠ sms`, `contactId` and `phoneNumber` are **not required** (copy-only path); `recipientName` and `body` stay required. (DATA_MODEL §4.1, §7.1) | DEFAULT |
| D-248 | Required fields are defined per **(kind, operation)** (DATA_MODEL §4.1). Reminder complete/undo uses field `completed` (bool): "Hoàn tác" = a new one-tap `reminder/complete` step with `completed = false` (D-107). `place/open` requires a destination (`name`, `address`, `coordinate`). | DEFAULT |
| D-249 | Error/step code scheme `<domain>.<reason>`; permission codes are `permission.<capability>.denied` (e.g. `permission.calendar.denied`), UI key `error.<code>`. Replaces `eventkit.denied` / `<kind>.denied` in examples. (DATA_MODEL §3.1, ARCHITECTURE §9, UI_SCREENS §8) | DEFAULT |
| D-250 | Review result card wording: `handedOff` / `unknown` → primary **"Tôi đã làm xong"** + secondary **"Để sau"** (never "Đã xong" next to "Xong"); `unknown` for calendar/reminder adds "Thử lại" instead of "Để sau". `failed` → "Thử lại" + "Hủy" (valid via D-243). (UI_SCREENS S04) | DEFAULT |
| D-251 | Picking a `dateCandidates` chip (S03) or a picker row (S06) resolves the field **on device**; no `/v1/parse` call, no unit. Only a free-text/voice answer to a follow-up calls `/v1/parse`. (UI_SCREENS S03, ARCHITECTURE §6.2) | DEFAULT |

### 12.4 Approved proposals (P-xx → D-(235+xx); full text stays in the source doc's proposal table)

| ID | From | Decision | Status |
|---|---|---|---|
| D-252 | P-17 | Several recipients → one `sms` step per recipient, same `body` | DEFAULT |
| D-253 | P-18 | A spoken/typed phone number goes in `recipientName`; when it is a number, `contactId` is not required and `phoneNumber` = normalized digits (DATA_MODEL §4.1) | DEFAULT |
| D-254 | P-19 | Backend injects `calendar_next_14_days` + weekday names into parse/extract prompts | DEFAULT |
| D-255 | P-20 | Extract LLM returns `quote`; backend computes the UTF-16 `span` | DEFAULT |
| D-256 | P-21 | Hour without a day part: 6–11 morning, 12 noon, 1–5 afternoon, confidence 0.6 | DEFAULT |
| D-257 | P-22 | Prompts are versioned files; `promptVersion` logged (no content) | DEFAULT |
| D-258 | P-23 | **Supersedes D-019:** layout = spec §3.2 plus `Core/Engine/` (holds the state machine), `Core/Services/{Live,Mock}/`, `Core/UI/` | LOCKED |
| D-259 | P-24 | `OCR_FALLBACK_MIN_CONFIDENCE` (default 0.5) decides Vision → `/v1/ocr` | DEFAULT |
| D-260 | P-25 | OpenAI call runs outside the DB transaction | DEFAULT |
| D-261 | P-26 | Backend uses asyncpg for quota/usage; Supabase Admin API only for user deletion | DEFAULT |
| D-262 | P-27 | OpenAI SDK `max_retries=0`, `LLM_TIMEOUT_SECONDS=12` inside the D-246 budget | DEFAULT |
| D-263 | P-28 | `TaskEngine` + `TaskRepository` are `@MainActor` on the main `ModelContext` | DEFAULT |
| D-264 | P-29 | `ExecutionOutcome.needsUI` for system UI (composer, pickers) | DEFAULT |
| D-265 | P-30 | `UserMessage { key, args }` is the only error/notice type a View renders | DEFAULT |
| D-266 | P-31 | `Route.calendarToday`, `Route.reminders` | DEFAULT |
| D-267 | P-32 | Custom color tokens (UI_SCREENS §1.1) | DEFAULT |
| D-268 | P-33 | Text floor `.callout`; values and buttons `.title3` | DEFAULT |
| D-269 | P-34 | Voice: app = "mình", user = "bạn" | DEFAULT |
| D-270 | P-35 | `alertMinutesBefore` choices 0 / 15 / 60 / 1440 | DEFAULT |
| D-271 | P-36 | No onboarding carousel; first run = S01 → S02 with a tip | DEFAULT |
| D-272 | P-37 | "Sửa" opens the first `needsReview` field, else the first field | DEFAULT |
| D-273 | P-38 | String key scheme `<screen>.<element>`, `common.*`, `step.*`, `field.*`, `option.*`, `followup.*`, `error.*` | DEFAULT |
| D-274 | P-39 | Delete step primary = "Xác nhận xóa" in `danger` style | DEFAULT |
| D-275 | P-40 | Simple mode hides Home quick links (except "Lịch hôm nay") and Settings ★ rows | DEFAULT |
| D-276 | DOC-17 | `/v1/extract` also returns `title` (appointment / clinic name as written); it fills `title` of the linked `calendarEvent` / `reminder` step | DEFAULT |

### 12.5 Final doc clean-up (DOC-1, 2, 5, 6, 7)

| ID | Decision | Status |
|---|---|---|
| D-277 | Two names for the parse schema: **`ParsedDraftLLM`** = what the LLM returns (`steps`, `followUpQuestion`, `unsupported`), validated by `task_draft.json`; **`ParsedDraft`** = wire response = `ParsedDraftLLM` + `schemaVersion` + `requestId`, added by the backend. (DATA_MODEL §6.2–6.3) | DEFAULT |
| D-278 | **Supersedes D-053:** model names in backend config are exactly `MODEL_PARSE`, `MODEL_EXTRACT`, `MODEL_VISION` (`/v1/ocr`), `MODEL_TRANSCRIBE`, `MODEL_SUMMARIZE` (Phase 2 only). Never hard-code a model string. | LOCKED |
| D-279 | **Supersedes D-202:** doc hierarchy (higher wins) = `DECISIONS` → `EasyPhone-AI-Spec` → `DATA_MODEL` → `API_CONTRACT` → `AI_PROMPTS` → `ARCHITECTURE` → `UI_SCREENS` → `PROGRESS` → `CLAUDE.md`. Lower docs never re-decide. | LOCKED |
| D-280 | Bulk actions ("xóa hết lịch tuần này", "nhắn cho tất cả") are out of scope in MVP: `/v1/parse` returns `unsupported.reason = "bulkAction"`; the app offers to open the list (S11 / S12) so the user acts one item at a time. Never build several delete steps from one sentence. | DEFAULT |
| D-281 | Follow-up rule: the app's `validate()` alone decides **whether** to ask. If it finds an issue, the app uses `followUpQuestion` only when it targets that same first field, else `followup.<kind>.<fieldId>`. If it finds none, a non-null `followUpQuestion` is ignored and the step goes to `awaitingApproval`. Unit-tested. | DEFAULT |

### 12.6 Thesis scope (owner, 2026-11-08) — read this before §1, §5, §6 and §11

The project is built as a **university thesis (khoá luận)** at near-zero cost. These rows supersede the ones named;
everything else (safety rules, engine, data model, API, accessibility) is unchanged.

| ID | Decision | Status |
|---|---|---|
| D-282 | **Supersedes D-005:** goal = thesis demo, **no public App Store release**, no TestFlight. Runs on the iOS Simulator and on the owner's iPhone via Xcode with a **free Apple ID (Personal Team)**; the 7-day signing expiry is accepted (reinstall from Xcode before demos). App Store rules (spec §10) are good practice, not gates. A capability a Personal Team cannot sign → simplest workaround + `// TODO(decision): D-282`, noted in PROGRESS §5.2. | LOCKED |
| D-283 | **Supersedes D-071:** sign-in = **Google only**, via Supabase Auth. No Sign in with Apple (needs a paid account; the "Apple whenever Google" rule applies only to App Store apps). `AuthService` keeps one provider; adding Apple later = new provider, no other change. D-070 (account required for AI) stays. | LOCKED |
| D-284 | **Billing and release, thesis variant.** Refines D-082, D-084, D-090, D-188, D-036: (a) Phase 1F tests purchases only with the local `.storekit` file in Xcode; `/v1/billing/verify` accepts the `Xcode` environment (D-240 applies to the thesis backend); no App Store Connect products. (b) `/v1/billing/notifications` (D-084) is optional — build it only if time allows. (c) D-090 / D-036 no longer block: keep D-091 / D-037 defaults (free tier hosting allowed). (d) Phase 1G = account deletion, privacy manifest, usage strings, accessibility + resilience pass, demo script; no TestFlight, no public Terms/Privacy URLs (in-app text is enough). (e) Widgets: if App Groups are unavailable on the Personal Team, the widget shows only the "Bấm để nói" CTA without the unfinished count. | DEFAULT |
| D-285 | **Cost guard:** `MONTHLY_SPEND_CAP_USD` default **5** for the thesis backend (D-087). Live evals (`pytest -m live`) only when the owner asks. | DEFAULT |

---

## 13. Open decisions summary (owner must lock)

| ID | Question | Needed by | Current default |
|---|---|---|---|
| D-036 | Backend hosting provider | not blocking (D-284) | Local + tunnel or a free tier (D-037) |
| D-052 | Exact OpenAI models | Phase 1B | Config placeholders (D-053) |
| D-060 | On-device OCR good enough for Vietnamese? | Phase 1D | Both paths behind protocol (D-061) |
| D-090 | Free quota size, prices, trial | not blocking (D-284) | Free 10/day, Premium 200/day, no trial (D-091, D-232) |
| D-092 | Which endpoints cost quota | Phase 1F | D-093 |
| D-156 | Google OAuth verification plan | Phase 2 | Testing mode only |
| D-161 | Verified third-party service list | 1C (Zalo) / 3 | All `verified: false` (D-162) |

**Agent rule:** when you reach a phase that needs an `OPEN` decision, stop and ask the owner before
building on top of the default in a way that is hard to undo (e.g. App Store product ids, DB schema).

---

## 14. Decision log (append-only)

| Date | ID | Change | By |
|---|---|---|---|
| 2026-11-08 | D-001 – D-208 | Initial decisions recorded from `EasyPhone-AI-Spec.md` and owner discussion | Owner + Claude |
| 2026-11-08 | D-220 – D-226 | Added data model decisions from `DATA_MODEL.md` (proposals P-1 – P-7), approved by owner | Owner + Claude |
| 2026-11-08 | D-230 – D-238 | Added API contract decisions from `API_CONTRACT.md` (proposals P-8 – P-16), approved by owner | Owner + Claude |
| 2026-11-08 | D-230 (reworded), D-239 – D-241 | Cross-doc logic review: idempotency charge rule made precise; account-transfer, Xcode StoreKit, premium-over-quota rules added | Owner + Claude |
| 2026-11-08 | D-242 | Owner chose option A: one return prompt after every hand-off; `prepared → userMarkedDone` transition added | Owner + Claude |
| 2026-11-08 | D-243 – D-251 | Cross-doc logic review round 2 (DOC-8 – DOC-16 in PROGRESS §5.2): stuck `failed`/`unknown` steps, closed states, per-endpoint idempotency key, time budget + last-attempt-wins, sms channel rule, per-operation required fields, error code scheme, result card wording, local chip resolution. Owner asked to fix | Owner + Claude |
| 2026-11-08 | D-252 – D-276 | Owner approved all proposals P-17 – P-40 (D-258 supersedes D-019) and `title` in `/v1/extract` (DOC-17, DOC-18) | Owner + Claude |
| 2026-11-08 | D-277 – D-281 | Final clean-up DOC-1, 2, 5, 6, 7: `ParsedDraftLLM` vs `ParsedDraft`, model list (supersedes D-053), full doc hierarchy (supersedes D-202), bulk actions unsupported, follow-up rule | Owner + Claude |

| 2026-11-08 | D-282 – D-285 | Owner: project is a thesis at near-zero cost — no App Store/TestFlight, free Apple ID, Google-only sign-in (supersede D-005, D-071), `.storekit`-only billing, spend cap 5 USD | Owner + Claude |

<!-- Append new rows below. To change a LOCKED decision, add a new ID that "supersedes D-xxx". -->
