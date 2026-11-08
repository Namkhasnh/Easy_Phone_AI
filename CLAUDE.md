# CLAUDE.md — EasyPhone AI

> Read by Claude Code at the start of every session. Keep it short; details live in the docs below.
> This file **never decides anything**. If it disagrees with a doc, the doc wins — fix this file.

## 1. What this project is
EasyPhone AI is an **iPhone-only** assistant for everyone, **including elderly and non-technical users**.
The user gives a task in **Vietnamese** (voice, text or one photo). The backend LLM turns it into an
**editable task draft**. The user reviews it and taps **"Xác nhận"**. The app then does what iOS allows
(EventKit, Contacts, MessageUI, MapKit) and **guides** the rest honestly.

- iOS app: Swift 6 (strict concurrency), SwiftUI, SwiftData, iOS 18.0+, SPM only.
- Backend: Python 3.12 + FastAPI (one service), Supabase (Postgres + Auth: **Google only**, D-283), OpenAI via backend only.
- Billing: StoreKit 2, verified server-side. Free = small daily quota, Premium = monthly/yearly.
- Dev setup: the owner vibe-codes with Claude Code + Xcode on a Mac (D-200).
- **Thesis scope (D-282 – D-285):** university thesis, near-zero cost. No App Store / TestFlight / paid Apple account:
  runs on Simulator + the owner's iPhone with a free Apple ID (7-day signing). Billing tested only with the local
  `.storekit` file. Spend cap 5 USD. Never ask the owner to buy an Apple Developer account.

## 2. Docs map (read only what the task needs)
All docs live in `docs/` (this file stays at the repo root). English Markdown, each under 500 lines (D-201).
UI strings stay Vietnamese.

| Doc | Read it when you… |
|---|---|
| `PROGRESS.md` | **always, first.** Current phase, next item, blockers, known issues, session log |
| `DECISIONS.md` | need to know if something is LOCKED / DEFAULT / OPEN (`D-xxx`) |
| `EasyPhone-AI-Spec.md` | need scope, user stories, acceptance criteria, phase exit criteria |
| `DATA_MODEL.md` | touch any model, enum, field id, state transition, SQL table, hash, evidence |
| `API_CONTRACT.md` | touch any endpoint, header, error code, quota/idempotency, billing, DTO |
| `AI_PROMPTS.md` | touch prompts, prompt assembly, untrusted-content wrapping, LLM fixtures |
| `ARCHITECTURE.md` | add a layer, service, executor, ViewModel, retry or error mapping |
| `UI_SCREENS.md` | build a screen, component, design token, or any visible string |

**Doc hierarchy (higher wins on conflict, D-279):**
`DECISIONS` → `Spec` → `DATA_MODEL` → `API_CONTRACT` → `AI_PROMPTS` → `ARCHITECTURE` → `UI_SCREENS` → `PROGRESS` → this file.
On a conflict: follow the higher doc, leave `// TODO(decision): <doc §> vs <doc §>` in code, and add a `DOC-x` row
to `PROGRESS.md` §5.2. Never resolve a conflict silently.

## 3. Session protocol (mandatory)
**Start**
1. Read `PROGRESS.md` (§1 Snapshot, §3 Blockers, §5 Known issues first).
2. Run the health checks (§8 below). Record failures in `PROGRESS.md` §5 before writing code.
3. Take the **first unchecked item of the current phase** unless the owner says otherwise. Mark it `[~]`.
4. Read only the docs listed in that item's `Docs:` column.

**End** (before the final reply)
1. Update `PROGRESS.md` per its §0.2 and **commit it together with the code**.
2. `[x]` only when the item's `Verify:` step passed. Compiles-but-untested = `[~]` with a "left:" note.
3. List every `TODO(spec)` / `TODO(decision)` you added in `PROGRESS.md` §5.3.
4. Write exactly **one concrete next action** in the Snapshot.

## 4. Phase gate
- Build strictly in order: **0 → 1A → 1B → 1C → 1D → 1E → 1F → 1G** (= MVP), then 2 (Gmail), 3 (ride/food). (D-140)
- Never start a phase whose previous exit criteria are not all `[x]`.
- **No Gmail code, scopes, tables, routes, DTOs or UI before Phase 2** (D-150). No ride/food code before Phase 3.
- Phase 2/3 enum cases (`emailReply`, `ride`, `food`) exist from day one for decoding only; no code path uses them.

## 5. Non-negotiable product rules (apply to every line of code)
1. **Never act without confirmation.** Create / edit / delete / send / hand-off only after "Xác nhận" on Review (D-100).
2. **Edit after approval resets approval** → `awaitingApproval`, hash cleared (D-101).
3. **Never claim success you cannot verify.** `succeeded` needs `resultEvidence` (D-124). `tel://`, Maps, Zalo copy,
   ride/food = `handedOff` / `prepared`, never `succeeded` (D-102). SMS is sent only on `MessageComposeResult.sent`.
4. **Untrusted content** (OCR, email, web) is data only; it reaches the LLM only via `wrap_untrusted()` (D-057).
5. **No automatic sending** of SMS, email or calls (D-103). Delete always needs a **tap**, never voice "có" (D-108).
6. **Drafts survive everything**: autosave on every field change; kill / offline / app switch / 401 never lose data (D-104).
7. **Idempotent retries**: look up evidence / `easyphone:<stepId>` before re-creating anything (D-105, D-225).
8. **Never auto-pick** among several contacts, numbers, dates, places or events — show a picker (D-106).
9. **Minimal data to backend**: names and labels only. 🔒 fields (`contactId`, contact phone numbers, `calendarId`,
   `targetRef`, `resultEvidence`, saved-place addresses, image paths) never leave the device (D-056).
10. **No OpenAI key in the app**, ever. Only the Supabase URL + anon key may ship (D-051, D-207).
11. **Accessibility first**: every flow works by text + buttons only, Dynamic Type to AX5, VoiceOver labels,
    contrast ≥ 4.5:1, state = icon + text, primary buttons ≥ 56pt, max 2 primary buttons per screen (D-180 – D-183).
12. Out-of-scope request → show **"Chưa hỗ trợ"**; never partially implement it (DECISIONS §9.4).

## 6. iOS conventions
**Layers (dependencies point down only):** View → ViewModel → `TaskEngine` / use case → Service protocol → framework.
- Views and ViewModels **never import** EventKit, Contacts, MessageUI, Speech, Vision, StoreKit or Supabase.
  They see only protocols from `Core/Services/` (D-015).
- Every service = `protocol` + `Live…` + `Mock…`. Previews and tests use mocks via `AppEnvironment.mock(...)` (D-206).
- ViewModels: `@Observable @MainActor final class …ViewModel`; no business rules, they forward intents to the engine.
- **Only `TaskEngine` writes `TaskStep.state`**, always through the pure `transition(state, event, context)`.
  Illegal transition → `nil`, state unchanged, `Logger.warning` (D-123). Implement the table in `DATA_MODEL.md` §1.5 exactly.
- Value models are `struct …: Codable, Sendable, Hashable`. No `@unchecked Sendable` without a comment.
- System UI (SMS composer) is returned as `ExecutionOutcome.needsUI` and presented by the ViewModel.

**Strings & UI**
- Every visible string is a key in `Localizable.xcstrings` (`vi` source). No literals in `Text("…")` (D-003).
- Use the key names from `UI_SCREENS.md` verbatim. Errors render as `UserMessage { key, args }` → `error.<code>`.
- Never show `error.localizedDescription`, stack traces or the backend `message` when a key exists.
- Field labels = `field.<kind>.<id>`; state labels = `state.<raw>`. The LLM never writes UI text (D-220).
- Use design tokens from `Core/UI/Tokens.swift` and shared components (`PrimaryButton`, `FieldRow`, `StateBadge`…).
  No fixed font sizes; no `minimumScaleFactor` < 1; no color-only state.
- A screen, element or string not in `UI_SCREENS.md` → simplest option + `// TODO(spec):`. Do not invent UI.

**Permissions:** request only on first use, after the S18 explainer; denied → explain + "Mở Cài đặt" + fallback (D-185).

## 7. Backend conventions
- Layout: `backend/app/{main.py, config.py, deps.py, routers/, schemas/, services/, repositories/, prompts/}`, `backend/tests/`.
- Routers are thin; business rules in `services/`; SQL only in `repositories/`.
- **All config in env / `config.py`** (pydantic-settings): `MODEL_PARSE/EXTRACT/VISION/TRANSCRIBE/SUMMARIZE` (D-278),
  quotas, units, spend cap, timeouts, `ENABLED_KINDS`. Never hard-code a model string, quota or price (D-038).
- Requests: Pydantic with `extra="forbid"`. Responses: every JSON root has `schemaVersion`; AI responses have `requestId`.
- Errors: raise `AppError(code, http_status, retryable, message_key, details)`; one global handler renders the envelope
  from `API_CONTRACT.md` §3. OpenAI SDK errors are mapped only in `services/llm.py`.
- Metered endpoints (`/v1/parse`, `/v1/extract`, `/v1/ocr`) go through the shared `metered()` pipeline:
  auth → version → validation → idempotency → spend cap → reserve → LLM → validate (+1 repair) → commit / refund.
  Quota is checked **before** any OpenAI call (D-086).
- LLM: structured outputs, `strict: true`, schema generated from `field_catalog.json` + `ENABLED_KINDS` (D-054).
  Prompts are versioned files `prompts/<name>.v<N>.md`; never inline prompt text in Python.
- **Never log raw user content** (request text, OCR text, LLM output). Log ids, endpoint, status, units, tokens,
  cost, latency, `promptVersion` only (D-059).
- RLS on every table; clients get read-only own-row policies; the backend writes with the service role (D-033).

**Single sources of truth (change together, in one commit):**
- `backend/app/schemas/task_draft.json` (= `ParsedDraftLLM`, D-277) ↔ Swift `ParsedDraft` / `TaskDraft` types (D-035).
- `backend/app/schemas/field_catalog.json` ↔ `Core/Models/FieldCatalog.swift` (equality test).
- API change = `API_CONTRACT.md` + Pydantic model + Swift DTO + fixtures in `backend/tests/fixtures/contract/`.
- New `TaskKind` = DATA_MODEL §1.1, §4, §8 + both JSON files + `Localizable.xcstrings`.

## 8. Commands
```bash
# iOS build + unit tests (Simulator)
xcodebuild -scheme EasyPhoneAI -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
xcodebuild -scheme EasyPhoneAI -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test

# Backend
cd backend && pytest -q            # CI suite, mocked LLM
cd backend && pytest -m live       # real model evals — costs money, run only when asked
cd backend && uvicorn app.main:app --reload   # local server (expose via tunnel for device tests, D-037)

git status                          # must be clean at session start, else note it in PROGRESS §1
```
If a command here is wrong for the actual project, fix this section in the same commit.

## 9. Testing rules
- Swift Testing (`@Test`) for unit tests, XCUITest for linked flows 1 & 2, pytest for backend (D-204, D-039).
- Required before MVP: state machine (every row + every illegal pair), approval hash, validator, relative dates,
  Vietnamese contact matching, phone normalization, quota + idempotency, billing verification (D-205).
- Contract fixtures are shared bytes: the iOS test target references `backend/tests/fixtures/contract/`.
- A test asserts no DTO contains a 🔒 key. A test fails on string literals inside `Text("…")`.
- Device-dependent items (EventKit, Contacts, Siri, StoreKit Sandbox) are verified on a **real iPhone** before `[x]`.

## 10. Git
- Small commits, one feature/fix each. Message: `[<phase>] <what> (D-xxx, P-xx)`, e.g. `[1A] transition table + tests (D-123)`.
- Never commit secrets: `.env`, `*.p8`, `Secrets.xcconfig` are in `.gitignore` (D-207).
- `PROGRESS.md` is updated in the same commit as the code it describes.

## 11. Decisions, proposals, open questions
- `LOCKED` = do not change; propose a superseding ID to the owner instead. `DEFAULT` = use it now.
- `OPEN` (D-036 hosting, D-052 models, D-060 OCR, D-090 prices/quota, D-092 metered endpoints, D-161 services,
  D-156 Gmail OAuth): use the listed default, but **stop and ask the owner** before hard-to-undo work built on it
  (App Store product ids, DB schema, production hosting).
- `P-xx` proposals (AI_PROMPTS §11, ARCHITECTURE §14, UI_SCREENS §12) are **not decisions** until recorded in
  `DECISIONS.md` §12/§14. Until then: simplest option + `// TODO(decision): P-xx`. Status is tracked in `PROGRESS.md` §4.
- A choice not covered anywhere: simplest option, `// TODO(spec):`, and a note in `PROGRESS.md` §5.2.

## 12. Do not
- Do not add third-party iOS packages except the Supabase Swift SDK without a `DEFAULT` entry (D-017).
- Do not use UIKit except through `UIViewControllerRepresentable` where required (D-014).
- Do not send the contact list, calendar contents or saved-place addresses to the backend.
- Do not let the LLM output ids, states, labels, `contactId`, contact phone numbers, evidence or hashes.
- Do not mark a hand-off as done automatically; ask once on return (D-242).
- Do not decide entitlement on device; the cached quota is display-only (D-085).
- Do not retry automatically: send/call/delete actions, `402`, `403`, `413`, `422`, `426`, `502`, `503 spend_cap`.
- Do not show a price StoreKit did not return. Do not promise features in the paywall that MVP lacks.
- Do not label simulated data as real; previews and demo data show "Dữ liệu mẫu" (D-189).
