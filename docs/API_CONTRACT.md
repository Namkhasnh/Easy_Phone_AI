# EasyPhone AI — API_CONTRACT.md

> Audience: an AI coding agent (Claude Code) building the iOS `APIClient` **and** the FastAPI backend.
> Hierarchy (D-279): `DECISIONS.md` → `EasyPhone-AI-Spec.md` → `DATA_MODEL.md` → **this file** → `AI_PROMPTS.md` → …
> This file defines the **wire contract only**. Object shapes come from `DATA_MODEL.md` and are used verbatim.
> Contract-level decisions made for this file are D-230 – D-241 and D-245 – D-246 (approved by the owner, recorded in
> `DECISIONS.md` §12.2–12.3 and summarized in §12 below).
> Conflict with a higher doc → the higher doc wins; flag with `// TODO(decision):`.

## 0. Rules
1. **One contract, two implementations.** Every request/response here = one Pydantic model in
   `backend/app/schemas/` + one `Codable` struct in `Core/Networking/DTO/`. Same names, same casing (`camelCase`).
2. **Unknown keys:** the backend rejects them in requests (`extra="forbid"` → 422). The app **ignores** unknown keys in
   responses, so the backend can add fields without breaking old builds.
3. **Never on the wire:** 🔒 device-only data (D-056): `contactId`, contact phone numbers, contact lists, calendar
   contents, saved-place addresses, `targetRef`, `resultEvidence`, image paths. A test asserts DTOs have none of these.
4. **Dates:** ISO 8601 with offset (`2026-11-09T14:00:00+07:00`); date-only `YYYY-MM-DD`. No epoch numbers.
5. **`schemaVersion`:** every JSON request and response root carries it (currently `1`). Backend accepts current +
   previous version for one release (DATA_MODEL §12). Unsupported version → `422 invalid_input`.
6. **Text limits:** `text`/`ocrText` max **2000 / 10 000** chars (FieldType `text`/`longText`). (D-238)
7. **No raw content in logs** (D-059): log `requestId`, `userId`, endpoint, status, units, tokens, cost, latency only.

## 1. Transport & headers
- Base URL: `API_BASE_URL` (config per build, D-208). All routes are under `/v1/` (D-034). HTTPS only.
- Content type: `application/json; charset=utf-8`, except `/v1/ocr` and `/v1/transcribe` (`multipart/form-data`).

| Request header | Required | Value |
|---|---|---|
| `Authorization` | all except `/v1/health` and the webhook | `Bearer <Supabase access token>` (D-032) |
| `X-Client-Version` | all app calls | `CFBundleShortVersionString` + `(build)`, e.g. `1.0.0(12)` |
| `Accept-Language` | all app calls | `vi` (or `en`); used for the `message` language in errors |
| `Idempotency-Key` | metered POSTs = `/v1/parse`, `/v1/extract`, `/v1/ocr` (§4.4) | lowercase UUID, **one per endpoint call**, the same for every automatic retry of that call (D-230, D-245) |

| Response header | When | Value |
|---|---|---|
| `X-Request-Id` | always | `req_<ulid>`; same as `requestId` in bodies; shown in support/debug (D-234) |
| `X-Quota-Limit`, `X-Quota-Remaining` | metered endpoints + `/v1/me` | integers, after this request (D-234) |
| `X-Quota-Resets-At` | same | ISO 8601 with offset |
| `Retry-After` | `429`, `503` | seconds |

## 2. Authentication
- App signs in with the Supabase Swift SDK (Google only, D-283). The SDK refreshes tokens; `APIClient` always
  reads the current access token from the SDK session.
- Backend verifies the JWT with `SUPABASE_JWT_SECRET` (HS256) or the project JWKS, checks `exp` and `aud=authenticated`, and uses
  `sub` as `userId` (lowercase UUID).
- **Profile auto-create (D-236):** the first authenticated request of a user upserts `profiles(id=sub)`, setting
  `locale` from `Accept-Language`. No separate sign-up endpoint. Skipped for `DELETE /v1/me`. If the upsert fails
  because the auth user no longer exists (account deleted, token not yet expired) → `401 unauthorized`.
- Invalid/expired token → `401 unauthorized`. The app refreshes the session **once** and retries. If it fails again, the app
  signs out to the sign-in screen. Local drafts are kept (D-104).

## 3. Error model
### 3.1 Envelope (every non-2xx response, all endpoints)
```json
{ "error": { "code": "quota_exceeded", "message": "Bạn đã dùng hết lượt hôm nay.",
             "retryable": false, "requestId": "req_01JC...", "details": { } } }
```
- `code` is the contract. `message` is a Vietnamese/English **fallback**. The app shows its own localized text from
  `Localizable.xcstrings` key `error.<code>`. It shows `message` only for codes it doesn't know.
- `details` is optional and typed per code (below). (D-233) adds `requestId` + `details` to the DATA_MODEL §6.1 envelope.
- `unsupported` is **not** an error: it is a `200` `ParsedDraft` with a non-null `unsupported` object (§7.1).

### 3.2 Codes
| HTTP | `code` | `retryable` | When | `details` | App behavior |
|---|---|---|---|---|---|
| 400 | `billing_invalid` | false | JWS signature/bundle/env check fails (D-233) | — | "Không xác minh được giao dịch" |
| 401 | `unauthorized` | false* | missing/invalid/expired JWT | — | refresh once → retry → else sign-in screen |
| 402 | `quota_exceeded` | false | metered call, no units left (D-088) | `{ "plan", "quota": Quota }` | `free` → **paywall**; `premium` → "Bạn đã dùng hết lượt hôm nay" + `resetsAt` (D-241); device-only features still work |
| 403 | `billing_account_mismatch` | false | JWS `appAccountToken` ≠ JWT `sub` (D-233) | — | show "Giao dịch thuộc tài khoản khác" |
| 404 | `not_found` | false | unknown route/resource (D-233) | — | generic error |
| 413 | `payload_too_large` | false | image/audio/text over limits (D-233) | `{ "maxBytes" }` or `{ "maxChars" }` | recompress/shorten once, else message |
| 422 | `invalid_input` | false | schema/validation failure, bad `schemaVersion`, bad date, idempotency key problems (§4.4) | `{ "field": "now", "reason": "missingOffset" }` | bug → log + generic error; draft kept |
| 426 | `client_outdated` | false | `X-Client-Version` < `MIN_CLIENT_VERSION` (D-233) | `{ "minVersion" }` | blocking "Cập nhật ứng dụng" screen |
| 429 | `rate_limited` | true | rate limit hit (e.g. `/v1/transcribe`) (D-233) | `{ "retryAfterSeconds" }` | fall back to typing; retry after delay |
| 500 | `internal` | true | unexpected server error | — | retry policy §10 → "Có lỗi, bản nháp đã được lưu" |
| 502 | `llm_invalid_output` | true | LLM output invalid after **one** repair retry (D-054) | — | friendly error + "Thử lại"; draft kept |
| 503 | `upstream_error` | true | OpenAI timeout/5xx/overload, or time budget exhausted (D-233, D-246) | — | retry policy §10 |
| 503 | `spend_cap` | false | global monthly spend cap hit (D-087) | — | "Dịch vụ AI tạm dừng"; device features work |

`retryable` = the same request may succeed later, so the UI may offer "Thử lại". Automatic retries follow §10 only.
\* `401` is not retried by the generic retry loop. Only the single refresh-then-retry applies.
Rule: a 4xx is never retried automatically except `401` (once) and `429` (after `Retry-After`).

## 4. Quota & metering (backend is the single source of truth, D-085)
### 4.1 Units per endpoint
| Endpoint | Units | Source | Notes |
|---|---|---|---|
| `POST /v1/parse` | **1** | D-086 (LOCKED) | includes follow-up answers; the internal repair retry costs 0 extra |
| `POST /v1/extract` | **1** | D-093 (DEFAULT, D-092 OPEN) | |
| `POST /v1/ocr` | **1** | D-093 (DEFAULT) | only called when on-device OCR is unusable (D-061) |
| `POST /v1/transcribe` | **0** | D-093 (DEFAULT) | rate-limited: `TRANSCRIBE_PER_HOUR=30` per user (D-237) |
| everything else | 0 | — | `/v1/me`, billing, health, webhook |

All values are in config (`UNITS_PARSE`, `UNITS_EXTRACT`, `UNITS_OCR`, `UNITS_TRANSCRIBE`), never hard-coded (D-038).
Picking a date chip or picker row on device costs nothing (D-251).

### 4.2 Limits
| Plan | Daily limit | Source |
|---|---|---|
| `free` | `FREE_DAILY_QUOTA` = **10** | D-091 (DEFAULT until D-090) |
| `premium` | `PREMIUM_DAILY_QUOTA` = **200** (fair-use, protects spend cap) | D-232 (DEFAULT; prices/limits still part of OPEN D-090) |

- Plan = `premium` iff a `subscriptions` row has `status in ('active','inGracePeriod','billingRetry')` and
  `expires_at > now()`, else `free` (DATA_MODEL §9).
- **Day** = calendar day in `QUOTA_DAY_TZ` (default `Asia/Ho_Chi_Minh`, D-224). `resetsAt` = next local midnight.
- `used` = `sum(units)` of the user's `usage_events` with `created_at` in the current quota day.
- Upgrading mid-day: the new limit applies immediately. `used` is kept.

### 4.3 Order of checks (every metered endpoint)
```
1 auth (401) → 2 client version (426) → 3 body/schema validation (422/413)
→ 4 idempotency lookup + attempt++ (§4.4) → 5 spend cap (503 spend_cap) → 6 quota reserve (402)
→ 7 OpenAI call(s) → 8 output validation (+1 repair) → 9 commit usage → 10 respond
```
- Steps 5–6 happen **before** any OpenAI call (D-086). Invalid requests (step 3) never cost units.
- **Reserve/commit/refund (D-231):** in one transaction protected by `pg_advisory_xact_lock(hashtext(user_id))`:
  compute `used`; if `used + units > limit` → 402; else insert a `usage_events` row with `units` (the reservation).
  After the OpenAI call, update that row with `tokens_in`, `tokens_out`, `cost_usd`.
  **Refund** (set `units = 0`, keep tokens/cost for the spend cap) when the response is non-2xx (`llm_invalid_output`,
  `upstream_error`, `internal`, any unhandled exception). A `200` with `unsupported` or `followUpQuestion` **is charged**,
  because the LLM ran.
- **Time budget (D-246):** each attempt has `REQUEST_BUDGET_SECONDS = 18` (below the app's 20 s timeout, D-127).
  LLM timeout = `min(LLM_TIMEOUT_SECONDS = 12, remaining)`. The repair call runs only if ≥ 5 s remain; otherwise →
  `503 upstream_error` (refund). So a backend attempt always ends before the app gives up on it.
- `/v1/transcribe` uses the same order, but step 4 is skipped and step 6 is the rate limit (429). It inserts a row
  with `units = 0` so its cost counts toward the spend cap.
- **Spend cap:** `sum(cost_usd)` for the current UTC month across all users ≥ `MONTHLY_SPEND_CAP_USD` → 503.

### 4.4 Idempotency — no double charge on retries (D-230, D-245, D-246)
- The app generates one `Idempotency-Key` per **endpoint call of a user action** and reuses it for that call's
  automatic retries (§10). A photo action therefore uses one key for `/v1/ocr` and another for `/v1/extract` (2 units).
  A new user action (e.g. "Thử lại" button after a final error) gets new keys.
- Backend keeps **one `usage_events` row per `(user_id, idempotency_key)`** (unique index). Rule: a call is
  charged **at most once**, and only if its **last** attempt returned 2xx.
- First attempt: insert the row (reservation, §4.3). Same key again within 24 h: reuse that row.
  The quota check excludes this row's own units, so a retry is never blocked by its own earlier charge.
- Each attempt, under the lock, increments `attempt` and remembers its number. It sets `units = cost` before the
  OpenAI call. When it finishes, it may set `units = 0` (non-2xx) **only if** the row's `attempt` still equals its
  number; an older attempt that finishes late changes nothing except adding its tokens/cost ("last attempt wins").
- `tokens_in`, `tokens_out`, `cost_usd` are **added** on every attempt, so the spend cap sees real cost.
- The advisory lock serializes reservation only; the OpenAI call runs outside it (P-25), so overlapping attempts are
  possible but harmless under the rule above. Responses are not cached (D-059): a retry re-runs the LLM.
- Same key after 24 h → `422 invalid_input` (`details.reason = "idempotencyKeyExpired"`).
- Same key on a different endpoint → `422 invalid_input` (`details.reason = "idempotencyKeyEndpointMismatch"`).
- Missing key on a metered POST → `422 invalid_input` (`details.field = "Idempotency-Key"`).

### 4.5 `Quota` object (used in `/v1/me`, 402 `details`)
```json
{ "limit": 10, "used": 3, "remaining": 7, "resetsAt": "2026-11-09T00:00:00+07:00" }
```
`remaining = max(0, limit - used)`. The app caches it in `AppSettings.lastSeenEntitlement` for **display only**.
It updates from `X-Quota-*` headers after each metered call. The app never blocks a request locally based on the cache.

## 5. Endpoint index
| Method | Path | Auth | Units | Phase | Section |
|---|---|---|---|---|---|
| GET | `/v1/health` | none | 0 | 0 | §6.1 (D-235) |
| GET | `/v1/me` | JWT | 0 | 0 | §6.2 |
| DELETE | `/v1/me` | JWT | 0 | 1G | §6.3 |
| POST | `/v1/parse` | JWT | 1 | 1B | §7.1 |
| POST | `/v1/extract` | JWT | 1 | 1D | §7.2 |
| POST | `/v1/ocr` | JWT | 1 | 1D | §7.3 |
| POST | `/v1/transcribe` | JWT | 0 | 1B | §7.4 |
| POST | `/v1/billing/verify` | JWT | 0 | 1F | §8.1 |
| POST | `/v1/billing/notifications` | Apple JWS | 0 | 1F | §8.2 |
| * | `/v1/gmail/*` | JWT | TBD | 2 | §9 — do not build (D-150) |

## 6. Account endpoints
### 6.1 `GET /v1/health` (D-235)
No auth. Used for Phase 0 checks and uptime monitoring.
```json
200 { "status": "ok", "version": "0.1.0", "schemaVersion": 1 }
```

### 6.2 `GET /v1/me`
Returns the profile, plan, and quota. Phase 0 exit check ("backend returns user id"). The app calls it on launch,
after sign-in, after purchase/restore, and when Settings opens.
```json
200 { "schemaVersion": 1, "userId": "6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11", "locale": "vi",
      "plan": "free",
      "quota": { "limit": 10, "used": 3, "remaining": 7, "resetsAt": "2026-11-09T00:00:00+07:00" },
      "subscription": null }
```
Premium example of `subscription`:
```json
{ "productId": "easyphone.premium.monthly", "status": "active",
  "expiresAt": "2026-12-08T18:00:00+07:00", "environment": "Sandbox" }
```
`status` ∈ `active, expired, inGracePeriod, billingRetry, revoked, refunded`; `environment` ∈ `Sandbox, Production, Xcode`
(`Xcode` only on the dev backend, D-240) (DATA_MODEL §9).
If the user has several subscription rows, `subscription` is the row with the latest `expires_at`. This type is named `MeResponse`.

### 6.3 `DELETE /v1/me` (D-073)
Deletes all server data: the backend deletes the Supabase auth user with the admin API. FK cascades remove `profiles`,
`subscriptions`, and `usage_events` (Phase 2: also revoke and delete Gmail tokens).
- Request: no body. Response: `204` (no body). Idempotent: deleting an already-deleted user → `204`.
- Before calling, the app shows confirmation and a note that an App Store subscription must be cancelled in
  iOS Settings (the backend cannot cancel it). After `204`: wipe SwiftData + `ocr/` images, sign out.

## 7. AI endpoints
### 7.1 `POST /v1/parse` — text → `ParsedDraft` (1 unit)
**Request** (`ParseRequest`):
| Key | Type | Req | Rule |
|---|---|---|---|
| `schemaVersion` | int | ✔ | `1` |
| `text` | string | ✔ | 1–2000 chars, trimmed; transcript, typed text, or follow-up answer |
| `inputMode` | enum | ✔ | `text, voice, photo, shortcut` (InputMode) |
| `now` | string | ✔ | device time, ISO 8601 **with offset** (D-058) |
| `timezone` | string | ✔ | IANA id, e.g. `Asia/Ho_Chi_Minh` |
| `locale` | string | ✔ | `vi-VN` or `en-US` |
| `savedPlaceLabels` | [string] | ✔ | labels only (`home`, `work`, custom label text), never addresses (DATA_MODEL §5) |
| `context` | object | ✔ | `{ draftId, answeringFieldId, currentDraft }`, all nullable |

`context.currentDraft` is a `ParsedDraft` (no 🔒 fields) when answering a follow-up question; otherwise all `null`.

**Response** `200` (`ParsedDraft` = LLM output `ParsedDraftLLM` + `schemaVersion` + `requestId`, D-277, DATA_MODEL §6.2–6.3):
| Key | Type | Notes |
|---|---|---|
| `schemaVersion` | int | `1` |
| `requestId` | string | same as `X-Request-Id`; stored in `TaskDraft.serverRequestId` |
| `steps` | [ParsedStep] | ordered; empty when `unsupported` is set |
| `steps[].kind` / `.operation` | enum | only `ENABLED_KINDS` + valid pairs (DATA_MODEL §1.2) |
| `steps[].fields[]` | `{ id, value, confidence, sourceQuote }` | `id` from catalog §4; `value` string or null; `confidence` 0–1 or null (null when `value` is null) |
| `steps[].dateCandidates[]` | `{ fieldId, value, label }` | non-empty only when a date is ambiguous |
| `followUpQuestion` | string? | preferred Vietnamese wording for the first missing field |
| `unsupported` | `{ reason, message }`? | out-of-scope request (spec §11) |

Backend post-processing (before responding):
1. Validate against `task_draft.json`. If it fails, run one repair call (time budget permitting, §4.3). If that fails, return `502 llm_invalid_output` (refund).
2. Drop catalog-unknown field ids. Check each `value` encoding per FieldType. If invalid, set `value: null` and `confidence: 0`.
3. Drop steps with a disabled kind or an invalid `(kind, operation)` pair. If none remain, set `unsupported.reason = "phaseNotEnabled"`.
4. Never return 🔒 fields, `state`, ids, labels, hashes, or evidence (DATA_MODEL §6.2).

Fields may be **partial**: the app fills catalog defaults, runs device resolution and `validate()` (DATA_MODEL §7.1).
The app's `validate()` decides **whether** to ask a follow-up question (D-281). `followUpQuestion` is used as the wording when it
targets that same field, otherwise the app uses `followup.<kind>.<fieldId>`. If `validate()` finds no issue, `followUpQuestion` is ignored.
Update/delete requests: `targetRef` is resolved **on device** (search EventKit by `title`/`startDate` fields), never by the backend.

**Example A — SMS (linked flow 2)**
```json
POST /v1/parse
{ "schemaVersion": 1, "text": "Nhắn anh Minh là chiều nay em đến muộn", "inputMode": "voice",
  "now": "2026-11-08T18:07:00+07:00", "timezone": "Asia/Ho_Chi_Minh", "locale": "vi-VN",
  "savedPlaceLabels": ["home", "work"],
  "context": { "draftId": null, "answeringFieldId": null, "currentDraft": null } }

200
{ "schemaVersion": 1, "requestId": "req_01JC8Z4K3M",
  "steps": [{ "kind": "sms", "operation": "open",
    "fields": [
      { "id": "recipientName", "value": "anh Minh", "confidence": 0.95, "sourceQuote": "anh Minh" },
      { "id": "body", "value": "Chiều nay em đến muộn nhé.", "confidence": 0.85, "sourceQuote": null },
      { "id": "channel", "value": "sms", "confidence": 0.6, "sourceQuote": null } ],
    "dateCandidates": [] }],
  "followUpQuestion": null, "unsupported": null }
```

**Example B — missing field, then follow-up answer (2 calls = 2 units)**
```json
POST /v1/parse  { ..., "text": "Nhắc tôi uống thuốc", "inputMode": "text", ... }
200 { "schemaVersion": 1, "requestId": "req_01JC8Z5A01",
  "steps": [{ "kind": "reminder", "operation": "create",
    "fields": [ { "id": "title", "value": "Uống thuốc", "confidence": 0.9, "sourceQuote": "uống thuốc" },
                { "id": "dueDate", "value": null, "confidence": null, "sourceQuote": null } ],
    "dateCandidates": [] }],
  "followUpQuestion": "Bạn muốn được nhắc lúc mấy giờ?", "unsupported": null }

POST /v1/parse
{ "schemaVersion": 1, "text": "8 giờ sáng mai", "inputMode": "voice",
  "now": "2026-11-08T18:10:00+07:00", "timezone": "Asia/Ho_Chi_Minh", "locale": "vi-VN",
  "savedPlaceLabels": ["home", "work"],
  "context": { "draftId": "0b9e3c1a-5f7d-4e2b-8a6c-3d1f2e4a5b6c", "answeringFieldId": "dueDate",
    "currentDraft": { "schemaVersion": 1, "requestId": "req_01JC8Z5A01", "steps": [ "...as above..." ],
                      "followUpQuestion": "Bạn muốn được nhắc lúc mấy giờ?", "unsupported": null } } }
200 { ..., "steps": [{ "kind": "reminder", "operation": "create", "fields": [
          { "id": "title", "value": "Uống thuốc", "confidence": 0.9, "sourceQuote": "uống thuốc" },
          { "id": "dueDate", "value": "2026-11-09T08:00:00+07:00", "confidence": 0.95, "sourceQuote": "8 giờ sáng mai" } ],
        "dateCandidates": [] }], "followUpQuestion": null, "unsupported": null }
```
The app **merges** the answer: it updates only fields that changed, and keeps fields the user already edited (`source = .user`).

**Example C — ambiguous date (said on Friday 2026-11-13)**
```json
POST /v1/parse { ..., "text": "Hẹn nha sĩ thứ Sáu 9 giờ", "now": "2026-11-13T07:30:00+07:00", ... }
200 { ..., "steps": [{ "kind": "calendarEvent", "operation": "create",
    "fields": [ { "id": "title", "value": "Hẹn nha sĩ", "confidence": 0.9, "sourceQuote": "Hẹn nha sĩ" },
                { "id": "startDate", "value": null, "confidence": null, "sourceQuote": "thứ Sáu 9 giờ" } ],
    "dateCandidates": [
      { "fieldId": "startDate", "value": "2026-11-13T09:00:00+07:00", "label": "Thứ Sáu 13/11 (hôm nay)" },
      { "fieldId": "startDate", "value": "2026-11-20T09:00:00+07:00", "label": "Thứ Sáu 20/11" } ] }],
  "followUpQuestion": "Bạn muốn hẹn thứ Sáu nào?", "unsupported": null }
```
The app builds an `Ambiguity(kind: .date)` from `dateCandidates`. "Xác nhận" stays disabled until the user picks (D-106).
Picking a candidate is resolved on device — no second `/v1/parse` call (D-251).

**Example D — unsupported (charged, 1 unit)**
```json
200 { "schemaVersion": 1, "requestId": "req_01JC8Z6B77", "steps": [], "followUpQuestion": null,
      "unsupported": { "reason": "recurringEvent", "message": "Chưa hỗ trợ lịch lặp lại." } }
```
`reason` ∈ `recurringEvent, invitation, emailSend, booking, payment, multiPageOcr, bulkAction, phaseNotEnabled, other`
(`bulkAction` = one sentence asking to change many items, D-280).
The UI shows "Chưa hỗ trợ" + `message`, and creates no steps.

### 7.2 `POST /v1/extract` — OCR text → fields with spans (1 unit)
Request (`ExtractRequest`). The backend wraps `ocrText` in `<untrusted_content>` (D-057):
```json
{ "schemaVersion": 1,
  "ocrText": "PHÒNG KHÁM NHA KHOA AN BÌNH\nLịch hẹn: 09:30 ngày 14/11/2026\nĐịa chỉ: 215 Hồng Bàng, Q5\nBS. Trần Văn Hùng - 0901 234 567",
  "now": "2026-11-08T18:20:00+07:00", "timezone": "Asia/Ho_Chi_Minh", "locale": "vi-VN" }
```
Response `200` (`ExtractResponse`):
```json
{ "schemaVersion": 1, "requestId": "req_01JC8Z7C10",
  "fields": [
    { "id": "title", "value": "Phòng khám Nha khoa An Bình", "confidence": 0.8, "span": { "start": 0, "end": 27 } },
    { "id": "dateTime", "value": "2026-11-14T09:30:00+07:00", "confidence": 0.85, "span": { "start": 38, "end": 59 } },
    { "id": "address", "value": "215 Hồng Bàng, Q5", "confidence": 0.8, "span": { "start": 69, "end": 86 } },
    { "id": "personName", "value": "Trần Văn Hùng", "confidence": 0.75, "span": { "start": 91, "end": 104 } },
    { "id": "phoneNumber", "value": "0901 234 567", "confidence": 0.9, "span": { "start": 107, "end": 119 } } ],
  "suggestedNextAction": "calendarEvent" }
```
- `fields[].id` ∈ `title, dateTime, address, personName, phoneNumber` (catalog §4 `ocr`). Missing info = field omitted.
- `title` (D-276) = the appointment or place name as written (clinic heading, "Lịch hẹn …" label); case may be
  normalized. The app copies it into the linked step's `title`; still editable and highlighted like every OCR field.
- **Spans are UTF-16 offsets** into `ocrText` (DATA_MODEL §1.7). Python indexes by code point, so the backend must convert
  (`len(s[:i].encode("utf-16-le")) // 2`). There is a fixture with Vietnamese diacritics + emoji to test this.
- Backend checks that the span substring matches `value` (normalized). If not, it returns `span: null` and `confidence ≤ 0.5`.
- `phoneNumber` stays as raw OCR text. The device normalizes it to E.164 (DATA_MODEL §7.3).
- `suggestedNextAction` ∈ `calendarEvent, reminder, copyContactInfo, ride` (`ride` only if Phase 3 is enabled) or `null`.
- Empty/blurry text → `200` with `fields: []`, `suggestedNextAction: null` (still charged). The app shows retake (spec §6.3 AC5).
  The app should not call `/v1/extract` when the OCR text is empty, to save quota.

### 7.3 `POST /v1/ocr` — image → text (1 unit, fallback only, D-061)
Request: `multipart/form-data` with parts `image` (JPEG, ≤ 4 MB, long side ≤ 2048 px) and `meta` (JSON string
`{ "schemaVersion": 1, "locale": "vi-VN" }`). The app resizes/compresses before upload. Larger → `413 payload_too_large`;
not JPEG → `422 invalid_input`. The image is processed in memory and **never stored** server-side.
```json
200 { "schemaVersion": 1, "requestId": "req_01JC8Z8D22",
      "text": "PHÒNG KHÁM NHA KHOA AN BÌNH\nLịch hẹn: 09:30 ngày 14/11/2026",
      "lines": [ { "text": "PHÒNG KHÁM NHA KHOA AN BÌNH", "box": { "x": 0.08, "y": 0.86, "width": 0.84, "height": 0.05 } },
                 { "text": "Lịch hẹn: 09:30 ngày 14/11/2026", "box": { "x": 0.08, "y": 0.78, "width": 0.70, "height": 0.04 } } ] }
```
`box` uses the same space as Vision's `NormalizedRect`: 0–1, **origin bottom-left**, so "Xem ảnh gốc" works the same for both paths.
`text` = `lines[].text` joined by `\n`. Next step: the app calls `/v1/extract` with `text` and a **new** key (another unit, D-245).

### 7.4 `POST /v1/transcribe` — audio → text (0 units, rate-limited)
Request: `multipart/form-data` with parts `audio` (m4a/AAC, ≤ 60 s, ≤ 2 MB) and `meta`
(`{ "schemaVersion": 1, "locale": "vi-VN" }`). Audio is never stored. Over the limit → `413`.
Rate limit: `TRANSCRIBE_PER_HOUR` (default 30) per user → `429 rate_limited` + `Retry-After` (D-237).
```json
200 { "schemaVersion": 1, "requestId": "req_01JC8Z9E33", "text": "nhắn anh minh là chiều nay em đến muộn", "confidence": 0.82 }
```
`confidence` 0–1. It may be `null` if the model gives no score (D-238). The app always shows the transcript as editable
(spec §6.2 AC1) and never auto-sends it to `/v1/parse`.

## 8. Billing
### 8.1 `POST /v1/billing/verify` (D-083)
The app calls it after every successful StoreKit 2 purchase, on "Khôi phục giao dịch" (once per transaction in
`Transaction.currentEntitlements`), and on launch for `Transaction.updates`. It calls `transaction.finish()` after a `200`
or `403` (that transaction will never verify for this account). On network error, `400`, or `5xx` it leaves the
transaction unfinished, so StoreKit delivers it again on the next launch.
```json
POST /v1/billing/verify
{ "schemaVersion": 1, "signedTransaction": "eyJhbGciOiJFUzI1NiIsIng1YyI6WyJNSUlF..." }
```
Backend steps:
1. Verify the JWS chain + signature with Apple's App Store Server Library (Python) and Apple root certificates.
   Failure → `400 billing_invalid`.
2. Check `bundleId == APP_BUNDLE_ID` and `productId` ∈ `PRODUCT_IDS` (D-091). Check `environment` ∈ `ALLOWED_ENVIRONMENTS`.
   Failure → `400 billing_invalid`.
   - Production backend: `Sandbox` + `Production` (TestFlight and App Review purchase in Sandbox).
   - Thesis scope (D-284): only the dev backend exists and real purchases come from the `.storekit` file (`Xcode`).
   - Dev backend: `Sandbox` + `Xcode`. `Xcode` = Debug builds using the local `.storekit` file. Those transactions are
     signed by Xcode, not Apple: verify them with the StoreKit test certificate exported from Xcode, only when
     `ALLOW_XCODE_STOREKIT=true` (dev config only, D-240).
3. `appAccountToken` (lowercased) must equal JWT `sub`. If it differs: when the token's user **no longer exists**
   (account was deleted, same Apple ID signs up again), reassign the subscription to the current user (D-239).
   Otherwise → `403 billing_account_mismatch`.
4. Upsert `subscriptions` by `original_transaction_id`: `product_id`, `expires_at`, `environment`, `status`
   (`active` if `expiresDate > now` and no `revocationDate`; `revoked` if revoked; else `expired`).
   Re-sending the same transaction is idempotent.
5. Respond `200` with **`MeResponse`** (§6.2), so the app updates plan + quota at once.

### 8.2 `POST /v1/billing/notifications` — App Store Server Notifications V2 (D-084)
- No JWT. Body: `{ "signedPayload": "<JWS>" }`. The backend verifies the JWS like in §8.1. If invalid → `400` (logged, no DB change).
- Decode `data.signedTransactionInfo` / `signedRenewalInfo`, find the row by `originalTransactionId`. If not found and
  `appAccountToken` matches a profile → insert. If neither → log + `200` (so Apple doesn't retry forever).
- Return `200` within a few seconds for every processed or ignored notification. Any non-2xx makes Apple retry.
- Deduplicate by `notificationUUID` (keep the last 1000 in memory; reprocessing is safe anyway).
- **Out-of-order delivery:** Apple may deliver notifications late or out of order. Ignore a notification whose
  transaction `expiresDate` is older than the stored `expires_at`, except `REFUND` and `REVOKE`, which always apply.

| `notificationType` (`subtype`) | New `status` |
|---|---|
| `SUBSCRIBED`, `DID_RENEW`, `DID_CHANGE_RENEWAL_PREF` (`UPGRADE`) | `active` (+ new `expires_at`, `product_id`) |
| `DID_FAIL_TO_RENEW` (`GRACE_PERIOD`) | `inGracePeriod` |
| `DID_FAIL_TO_RENEW` (no subtype) | `billingRetry` |
| `EXPIRED`, `GRACE_PERIOD_EXPIRED` | `expired` |
| `REFUND` | `refunded` |
| `REVOKE` | `revoked` |
| `DID_CHANGE_RENEWAL_PREF` (`DOWNGRADE`), `DID_CHANGE_RENEWAL_STATUS`, `PRICE_INCREASE`, `TEST`, others | no status change (update `updated_at` only) |

The app learns about changes on its next `GET /v1/me` (launch / Settings / 402). There is no push in MVP.

## 9. Phase 2 placeholder — `/v1/gmail/*`
Do not implement routes, scopes, tables, or DTOs before Phase 2 (D-150). When Phase 2 starts, add a section here following
D-151–D-155 (backend OAuth, encrypted tokens, multi-account, no send API, cited summaries) and lock quota units
for `summarize`/`draft`, which is a new OPEN item similar to D-092.

## 10. Client behavior (`Core/Networking/APIClient`)
- Timeout **20 s** per attempt. **2 retries** with exponential backoff (1 s, 3 s + jitter) (D-127) for: network
  errors, `500`, `503 upstream_error`. **Not** for `502 llm_invalid_output` (the backend already ran a repair retry;
  show "Thử lại"), `503 spend_cap`, or any other 4xx.
- `429`: wait `Retry-After` (max 1 attempt). For transcribe, fall back to the keyboard immediately.
- All retries of one call reuse that call's `Idempotency-Key`; each endpoint call gets its own key (§4.4, D-245).
- After the final failure: the draft is already autosaved (D-104). Show "Không có mạng — bản nháp đã được lưu" (network)
  or the localized `error.<code>`, and offer "Thử lại" (new key).
- Decoding: strict on required keys, ignore unknown keys. Unknown enum raw value → map per DATA_MODEL §12, never crash.
- Every response: read `X-Quota-*` → update `CachedEntitlement`. Log `X-Request-Id` (no content).
- All calls go through one `APIClientProtocol` with a mock that returns the fixture files (§11) for previews/tests (D-206).

## 11. Contract tests & fixtures
- Fixtures live in `backend/tests/fixtures/contract/` (one JSON per example in this file, named
  `<endpoint>.<case>.request.json` / `.response.json`, e.g. `parse.ambiguousDate.response.json`). The iOS test target adds
  this folder as a folder reference, so **both sides test the same bytes**.

| Test | Side |
|---|---|
| Every `*.request.json` validates against the Pydantic model; every `*.response.json` against the response model | pytest |
| Every `*.response.json` decodes into the Swift DTO and re-encodes without losing required keys | Swift Testing |
| `ParsedDraft` fixtures validate against `task_draft.json` (D-035) | pytest |
| Error envelope fixtures for every §3.2 code decode in Swift; every code has an `error.<code>` string | both |
| Quota: reserve → refund on 502 and on unhandled 500; 402 at limit; parallel requests can't exceed limit; same `Idempotency-Key` charged once; retry at limit not blocked by its own charge; last attempt fails → 0 units; late older attempt cannot refund a newer success (D-246); key reused on another endpoint → 422 (D-245) | pytest |
| Time budget: slow mocked LLM → `503 upstream_error` before 18 s, repair skipped when < 5 s remain | pytest |
| `DELETE /v1/me` then a request with the old token → 401, no profile re-created | pytest |
| Day boundary at 00:00 `Asia/Ho_Chi_Minh`; premium limit after verify | pytest |
| `/v1/extract` UTF-16 span conversion with diacritics + emoji | pytest |
| Billing: valid / bad signature / wrong bundle / token mismatch / deleted-user transfer / replay / Xcode env only in dev; each notification type → status; out-of-order notification ignored | pytest (signed test JWS) |
| No DTO contains a 🔒 key (`contactId`, `phoneNumber` in parse request, `targetRef`, address of saved places) | Swift Testing |
| FastAPI `/openapi.json` lists exactly the routes in §5 | pytest |

## 12. API contract decisions (recorded in DECISIONS.md §12.2–12.5, status DEFAULT)
| ID | Decision | Why |
|---|---|---|
| D-230 | `Idempotency-Key` on metered POSTs; one `usage_events` row per key (24 h); charged at most once, only if the last attempt succeeded | D-127 retries must not double-charge |
| D-231 | Reserve units before the OpenAI call (advisory lock per user), refund (`units=0`) on non-2xx; `unsupported`/follow-up responses are charged | race-free D-086; fair on server errors |
| D-232 | `PREMIUM_DAILY_QUOTA = 200` fair-use limit in config | protects D-087 spend cap; part of OPEN D-090 |
| D-233 | Error envelope gets `requestId` + typed `details`; new codes `billing_account_mismatch, billing_invalid, not_found, payload_too_large, client_outdated, rate_limited, upstream_error` | every failure mode has a code the app can handle |
| D-234 | Response headers `X-Request-Id`, `X-Quota-Limit/Remaining/Resets-At` | quota display without extra `/v1/me` calls |
| D-235 | `GET /v1/health` (no auth) | Phase 0 check + uptime monitoring |
| D-236 | Profile row auto-created on the first authenticated request | no extra sign-up endpoint |
| D-237 | `/v1/transcribe` limit `TRANSCRIBE_PER_HOUR = 30` per user | makes "free but rate-limited" (D-093) concrete |
| D-238 | Request text limits 2000/10 000 chars; transcribe `confidence` may be `null` | bounded LLM cost; not every model gives a score |
| D-239 | Billing verify reassigns a subscription whose `appAccountToken` user was deleted to the current user | a paying user who deletes and re-creates the account keeps Premium |
| D-240 | Dev backend accepts `Xcode` environment transactions (local `.storekit`) when `ALLOW_XCODE_STOREKIT=true`; never in production | Debug purchases can be tested end to end |
| D-241 | Premium user over quota sees "hết lượt hôm nay" + reset time, not the paywall (refines D-088) | paywall is meaningless for a subscriber |
| D-245 | One `Idempotency-Key` per endpoint call; reuse on another endpoint → 422 | OCR + extract must be 2 units, not 1 |
| D-246 | 18 s backend budget per attempt; `usage_events.attempt`, last attempt wins | backend never outlives the app timeout; no refund/charge races |
| D-276 | `/v1/extract` returns `title` | photo → calendar flow needs no extra question for the title |
| D-277 | `ParsedDraft` = `ParsedDraftLLM` + `schemaVersion` + `requestId` | one clear schema for the LLM, one for the wire |
| D-280 | `unsupported.reason = "bulkAction"` | bulk deletes are risky for elderly users; act one item at a time |
| D-281 | app `validate()` decides follow-ups; `followUpQuestion` is wording only | one decider, testable |

## 13. Change process
- Any change to an endpoint, key, code, or unit cost = update **this file + Pydantic model + Swift DTO + fixtures** in
  **one commit** (message references the D- id). Breaking change → `/v2/` route (D-034) or `schemaVersion` bump.
- New endpoint = add to §5, give it a section with request/response examples and an error list, add fixtures, state its units.
