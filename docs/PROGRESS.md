# EasyPhone AI — PROGRESS.md

> Audience: the AI coding agent (Claude Code) working in Xcode + the FastAPI backend, and the owner.
> Purpose: **memory between sessions.** This file is the single place that says what is done, what is in
> progress, what is broken and what to do next. It never decides anything: decisions live in `DECISIONS.md`,
> scope in `EasyPhone-AI-Spec.md`, shapes in `DATA_MODEL.md`, wire in `API_CONTRACT.md`, prompts in
> `AI_PROMPTS.md`, structure in `ARCHITECTURE.md`, screens/strings in `UI_SCREENS.md`.
> Conflict between this file and any of those → the other doc wins; fix this file.

---

## 0. Session protocol (mandatory)

### 0.1 At the START of every session
1. Read this file top to bottom (§1 Snapshot, §3 Blockers, §5 Known issues first).
2. Read only the docs the current task needs (see the `Docs` column of each checklist item).
3. Run the health checks in §0.4 and note anything red in §5 before writing code.
4. Pick the **first unchecked item of the current phase** unless the owner says otherwise. Do not start a phase
   whose previous phase has unmet exit criteria (D-140).
5. Mark the item `[~]` (in progress) and write it into §1 "Working on".

### 0.2 At the END of every session (before the final reply to the owner)
Update this file **in the same commit** as the code, then commit (D-203). Required edits:
1. Tick finished items `[x]` and add the commit short hash: `- [x] … (a1b2c3d)`.
2. Leave unfinished items as `[~]` with one line: what is left, which file, which function.
3. Add new bugs to §5 (`BUG-xxx`), close fixed ones (move to §5.4 with the fixing commit).
4. Add any `// TODO(spec):` / `// TODO(decision):` you left in code to §5.3.
5. Update §1 Snapshot (date, phase, last commit, next action — **one concrete next step**).
6. Append one entry to §8 Session log (newest on top). Max 8 lines per entry.
7. If an `OPEN` decision now blocks work, add it to §3 and **stop and ask the owner** (DECISIONS §13 rule).
8. Never delete history in §5.4 or §8. If the file nears 500 lines (D-201), compress §8 entries older than
   10 sessions into one summary line per phase.

### 0.3 Status legend
| Mark | Meaning |
|---|---|
| `[ ]` | not started |
| `[~]` | in progress (must have a "left:" note) |
| `[x]` | done **and** verified (tests pass / checked on device as the item says) |
| `[!]` | blocked — reason + blocker id (§3) on the same line |
| `[-]` | dropped / moved — reason + where it went |

"Done" means verified. Code that compiles but is untested is `[~]`, not `[x]`.

### 0.4 Health checks (run at session start, record failures in §5)
- [ ] `xcodebuild -scheme EasyPhoneAI -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build` succeeds
- [ ] `xcodebuild … test` — all `EasyPhoneTests` green
- [ ] `cd backend && pytest -q` — green (live tests excluded)
- [ ] `git status` clean at start (else note the uncommitted work in §1)

### 0.5 `CLAUDE.md`
The repo root `CLAUDE.md` (project doc `CLAUDE.md`) holds the session protocol, doc map, rules and commands.
Copy it to the repo root in item 0.1. Keep it in sync when this file's protocol changes.

---

## 1. Snapshot (overwrite every session)

| Key | Value |
|---|---|
| Last updated | 2026-11-08 |
| Current phase | **Phase 0 — Skeleton** (0.1, 0.2 done) |
| Working on | — |
| Last commit | `[0] project settings …` on branch `demo_git` (no remote yet) |
| Build status | ✅ `xcodebuild … iPhone 18 Pro build` succeeds |
| Test status | n/a — no test target yet (added in Phase 1A); `xcodebuild test` is expected to fail until then |
| Next action | Item 0.3: folder layout — first ask the owner about DOC-19 (keep `EasyPhoneAI/` folder name) |
| Owner decisions needed now | none. Thesis scope (D-282 – D-285): no paid Apple account, Google-only sign-in |

---

## 2. Documentation status

| Doc | Status | Notes |
|---|---|---|
| `DECISIONS.md` | ✅ written | D-001 – D-285; thesis scope D-282 – D-285 (§12.6); no open DOC-x items |
| `EasyPhone-AI-Spec.md` | ✅ updated | phases, user stories, DoD; layout (D-258), hierarchy (D-279), transitions (D-243) |
| `DATA_MODEL.md` | ✅ updated | enums, transition table (+D-243), field catalog + §4.1 per-operation required, SQL (+`attempt`) |
| `API_CONTRACT.md` | ✅ updated | endpoints, errors, quota, idempotency per endpoint call (D-245), time budget (D-246) |
| `AI_PROMPTS.md` | ✅ updated | parse/extract/repair prompts, fixtures, `title` (D-276), `bulkAction` (D-280); summarize = Phase 2 draft |
| `ARCHITECTURE.md` | ✅ updated | layers, services, engine (permission step 0), metering pipeline, retry, testing |
| `UI_SCREENS.md` | ✅ updated | S01–S20, tokens, all `vi` strings; result card buttons (D-250) |
| `CLAUDE.md` | ✅ written | agent entry point; copy to repo root in 0.1 |
| `PROGRESS.md` | ✅ this file | |
| `SupportedServices.json` | ⬜ to create in 1C | DATA_MODEL §10, all `verified: false`; `sms` not listed (built in) |
| Privacy policy / Terms pages | ⬜ in-app text only, 1G | D-188 relaxed by D-284 (no public URLs) |

---

## 3. Blockers & open decisions (from `DECISIONS.md` §13)

| ID | Question | Needed by | Default in use | Blocks? |
|---|---|---|---|---|
| D-036 | Backend hosting provider | — | local + tunnel or free tier (D-037, D-284) | no |
| D-052 | Exact OpenAI models | Phase 1B | config placeholders (D-053) | **yes, before** shipping 1B: run live evals (AI_PROMPTS §10) |
| D-060 | Vision OCR good enough for Vietnamese? | Phase 1D | both paths (D-061) | no |
| D-090 | Free quota, prices, trial | — | Free 10/day, Premium 200/day, no trial | no — `.storekit` only (D-284) |
| D-092 | Which endpoints cost quota | Phase 1F | D-093 | no |
| D-161 | Verified service list (Zalo) | 1C / 3 | all `verified: false` (D-162) | no |
| D-156 | Google OAuth verification plan | Phase 2 | Testing mode | not in MVP |

Rule: hard-to-undo work built on a default (App Store product ids, DB schema, hosting) → ask the owner first.

---

## 4. Proposals waiting for owner approval

Code may follow a proposal only after it is recorded in `DECISIONS.md` §12 / §14. Until then use the simplest
option and mark the code `// TODO(decision): P-xx`. Update the Status column when the owner answers.

| IDs | Source doc | Topic | Status |
|---|---|---|---|
| P-17 – P-22 | AI_PROMPTS §11 | multi-recipient SMS, phone number as recipient, calendar table, quote→span, hour rules, prompt files | ✅ D-252 – D-257 |
| P-23 – P-30 | ARCHITECTURE §14 | folder layout, OCR fallback threshold, LLM call outside lock, asyncpg, `max_retries=0` + 12 s timeout, `@MainActor` engine, `needsUI`, `UserMessage` | ✅ D-258 – D-265 (D-258 supersedes D-019) |
| P-31 – P-40 | UI_SCREENS §12 | `Route.calendarToday`/`.reminders`, color tokens, type floor, "mình/bạn", alert choices, no onboarding, "Sửa" target, key scheme, delete style, simple mode | ✅ D-266 – D-275 |

---

## 5. Known issues

### 5.1 Open bugs (code)
Format: `BUG-xxx | phase | severity (P1 crash/data loss, P2 wrong behavior, P3 cosmetic) | symptom | where | status`

| ID | Phase | Sev | Symptom | Where | Status |
|---|---|---|---|---|---|
| — | | | none yet | | |

### 5.2 Spec gaps & doc conflicts (fix in docs, not by guessing in code)
| ID | Issue | Docs | Suggested fix | Status |
|---|---|---|---|---|
| DOC-1 | `ParsedDraft` is called "exactly the LLM schema" but `schemaVersion` + `requestId` are added by the backend | DATA_MODEL §6.2 vs AI_PROMPTS §3 | define `ParsedDraftLLM` in DATA_MODEL §6.3 | fixed (D-277) |
| DOC-2 | Config model names differ: D-053 lists `MODEL_VISION`, `MODEL_TRANSCRIBE`; AI_PROMPTS uses `MODEL_SUMMARIZE` | DECISIONS D-053, AI_PROMPTS §0 | one list in `config.py`: PARSE, EXTRACT, VISION (OCR), TRANSCRIBE, SUMMARIZE (Phase 2) | fixed (D-278 supersedes D-053) |
| DOC-3 | `Route` enum lacks `calendarToday`, `reminders` (S11, S12) | ARCHITECTURE §2.2 vs UI_SCREENS §3 | approve P-31 | fixed (D-266) |
| DOC-4 | Call/SMS to a raw phone number: catalog requires `contactId` | DATA_MODEL §4.1 vs AI_PROMPTS P-18 | approve P-18 → `contactId` required only when no number given | fixed (D-253, DATA_MODEL §4.1) |
| DOC-5 | Doc hierarchy lists differ (ARCHITECTURE omits UI_SCREENS; DECISIONS says `PROMPTS.md`) | DECISIONS D-202, ARCHITECTURE header | add AI_PROMPTS, ARCHITECTURE, UI_SCREENS to D-202 (CLAUDE.md already uses the full list) | fixed (D-279 supersedes D-202) |
| DOC-6 | Bulk delete ("Xóa hết lịch tuần này") behavior unspecified | AI_PROMPTS §8.4 `TODO(spec)` | device asks one by one; confirm with owner | fixed (D-280: `bulkAction` unsupported, open S11/S12) |
| DOC-7 | `followUpQuestion` vs app `validate()` disagreement rule only in API_CONTRACT §7.1 | API_CONTRACT, ARCHITECTURE §6.2 | keep app as the decider; add a test | fixed (D-281 + DATA_MODEL §13 test) |
| DOC-8 | `failed` step could not be cancelled or marked done (UI offered "Hủy"); "Xóa lịch sử" deleted `failed` drafts shown as unfinished | DATA_MODEL §1.5, §5, §8; UI S04, S20 | D-243 transitions + D-244 closed states | fixed |
| DOC-9 | `unknown` step with no evidence after launch verification was stuck (no retry) | DATA_MODEL §1.5, ARCHITECTURE §5.4 | D-243 `unknown + retry` | fixed |
| DOC-10 | Shared `Idempotency-Key` for `/v1/ocr` + `/v1/extract` would charge 1 unit instead of 2 | API_CONTRACT §4.4, ARCHITECTURE §6.4, §10.1 | D-245 one key per endpoint call + mismatch 422 | fixed |
| DOC-11 | LLM 15 s + repair could exceed the app's 20 s timeout; overlapping attempts with one key could refund/charge wrongly | API_CONTRACT §4.3–4.4, ARCHITECTURE §7 | D-246 18 s budget, 12 s LLM timeout, `usage_events.attempt`, last attempt wins | fixed |
| DOC-12 | Validator rejected `channel = sms` (not in `SupportedServices.json`); Zalo copy path required contact permission | DATA_MODEL §4, §7.1 | D-247 | fixed |
| DOC-13 | Required fields not defined per operation (reminder complete/snooze/delete, place open had no destination, undo had no field) | DATA_MODEL §4 | D-248 + DATA_MODEL §4.1, `completed` field | fixed |
| DOC-14 | Error codes `eventkit.denied` vs `<kind>.denied` | DATA_MODEL §3.1, ARCHITECTURE §5.1/§9, UI §8 | D-249 `permission.<capability>.denied` | fixed |
| DOC-15 | S04 hand-off card showed "Đã xong" next to "Xong" (confusing); `metered()` did not refund on 500; `notDetermined` permission flow and OCR "Tiếp tục" meaning unspecified; chip answers might cost a unit | UI S04/S09, ARCHITECTURE §5.1/§7.1 | D-250, D-251 + doc clarifications | fixed |
| DOC-16 | "Việc chưa xong" and `currentStep` (when no step qualifies) undefined | UI S02/S08/§7, DATA_MODEL §3.2 | D-244 | fixed |
| DOC-17 | `/v1/extract` has no `title`, so OCR → calendarEvent always needs a follow-up for `title` | API_CONTRACT §7.2, AI_PROMPTS §4, DATA_MODEL §4 | owner: add `title` to extract (e.g. clinic/appointment name) or keep editor-only; until then the user types it in S05 (no AI call) | fixed (D-276) |
| DOC-18 | Phase 0/1A items depend on pending proposals (P-23 layout vs LOCKED D-019, P-30, P-32, P-33, P-38) | PROGRESS §4, §6 | owner approves P-17 – P-40 as a batch (P-23 as a superseding D-id) before 0.3 | fixed (D-252 – D-275) |
| DOC-19 | Spec §3.2 layout root is `EasyPhone/`; the repo's app folder, target and scheme are `EasyPhoneAI` (CLAUDE.md §8 uses `EasyPhoneAI`) | Spec §3.2 vs repo | keep `EasyPhoneAI/` as the app root (no project rename); confirm with owner in 0.3 | open |

### 5.3 Code TODOs left in source
List every `// TODO(spec):` and `// TODO(decision):` with file + line. Remove when resolved.

| File:line | Tag | Note |
|---|---|---|
| `EasyPhoneAI/ContentView.swift:3` | TODO(spec) | placeholder view with a literal string; replaced in 0.3/0.5 |

### 5.4 Closed (append-only)
| ID | Closed on | Commit | Note |
|---|---|---|---|
| DOC-8 – DOC-16 | 2026-11-08 | docs only | resolved by D-243 – D-251 |
| DOC-3, DOC-4, DOC-17, DOC-18 | 2026-11-08 | docs only | resolved by D-266, D-253, D-276, D-252 – D-275 |
| DOC-1, DOC-2, DOC-5, DOC-6, DOC-7 | 2026-11-08 | docs only | resolved by D-277 – D-281 |

---

## 6. Phase checklists

Each item: `- [ ] <id> <task> — Docs: … — Verify: …`. Exit criteria come from spec §4 and must all be `[x]`
before the next phase starts. Architecture order per ARCHITECTURE §13.1.

### Phase 0 — Skeleton
Exit: **sign in with Google (Simulator + owner's iPhone, free Apple ID), backend returns the user id** (`GET /v1/me`, D-283).
- [x] 0.1 git repo, `.gitignore` (`.env`, `*.p8`, `Secrets.xcconfig`, D-207), `CLAUDE.md` at root — Verify: `git check-ignore .env` (716adcd)
- [x] 0.2 Xcode project: iOS 18.0, iPhone only, Swift 6 strict concurrency, SPM — Docs: D-010–D-018 (this commit) — bundle id `vn.namkhanh.easyphone`, display name "EasyPhone", development language `vi`, default MainActor isolation removed (ARCHITECTURE §8), App Groups off (D-284)
- [ ] 0.3 Folder layout `App/ Core/{Models,Engine,Services,Networking,Persistence,Permissions,UI} Features/ Intents/ Widgets/ Resources/` — Docs: ARCHITECTURE §2, D-258
- [ ] 0.4 `Localizable.xcstrings` (vi source) + `InfoPlist.xcstrings` created — Docs: UI_SCREENS §0, §6 S18
- [ ] 0.5 `AppEnvironment.live()` / `.mock()`, `AppState`, `Router` (empty routes) — Docs: ARCHITECTURE §2.2, §3
- [ ] 0.6 SwiftData `ModelContainer` with `VersionedSchema` v1 (empty models ok) — Docs: DATA_MODEL §12
- [ ] 0.7 `Config.xcconfig` (Debug/Release `API_BASE_URL`, Supabase URL + anon key only) — Docs: D-207, D-208
- [ ] 0.8 Supabase project (free tier) + Google OAuth client (Google Cloud, free): Google provider enabled, redirect URL for the app — Docs: D-283 — Verify: test sign-in in dashboard
- [ ] 0.9 `AuthService` live (Supabase Swift SDK, Google only) + mock — Docs: ARCHITECTURE §4.1, D-283
- [ ] 0.10 S01 Sign-in screen (Google button, legal text) + `#Preview` — Docs: UI_SCREENS S01
- [ ] 0.11 Backend skeleton: FastAPI, `config.py` (pydantic-settings), `deps.py`, request-id middleware, error envelope handler — Docs: ARCHITECTURE §7, §9.3; API_CONTRACT §3
- [ ] 0.12 `GET /v1/health` (no auth) — Verify: pytest + curl
- [ ] 0.13 JWT verification (`sub`, `exp`, `aud`) + profile upsert (D-236) — Verify: pytest 401 cases
- [ ] 0.14 SQL migration: `profiles`, `subscriptions`, `usage_events` (incl. `attempt`, D-246) + RLS (no `gmail_accounts`) — Docs: DATA_MODEL §9
- [ ] 0.15 `GET /v1/me` returning `MeResponse` + `X-Quota-*` headers — Docs: API_CONTRACT §6.2
- [ ] 0.16 `APIClient` actor: headers, 20 s timeout, `RetryPolicy`, 401 refresh-once, 426 → S19 — Docs: API_CONTRACT §10, ARCHITECTURE §10
- [ ] 0.17 S19 Update required screen — Docs: UI_SCREENS S19
- [ ] 0.18 Contract fixtures folder `backend/tests/fixtures/contract/` shared with iOS tests — Docs: API_CONTRACT §11
- [ ] 0.19 Backend reachable from iPhone (tunnel, D-037)
- [ ] **EXIT 0** Simulator **and** owner's iPhone (installed from Xcode, free Apple ID): sign in with Google → app shows `userId` from `/v1/me`

### Phase 1A — Core engine
Exit: **unit tests pass for all state transitions.**
- [ ] 1A.1 Enums `TaskKind`, `TaskOperation`, `TaskState`, `TaskEvent`, `FieldType`, `FieldSource` (+ JSON `type` discriminator) — Docs: DATA_MODEL §1
- [ ] 1A.2 `Field`, `Ambiguity`, `Candidate`, `TaskStep`, `StateChange`, `TaskDraft @Model`, `InputMode` — Docs: DATA_MODEL §2–3
- [ ] 1A.3 `FieldCatalog.swift` (incl. §4.1 per-operation required) + `backend/app/schemas/field_catalog.json`, equality test — Docs: DATA_MODEL §4, §4.1
- [ ] 1A.4 `transition(state, event, context)` pure function — Docs: DATA_MODEL §1.5
- [ ] 1A.5 Tests: every table row passes; every other pair → `nil` (incl. D-222, D-242, D-243 rows) — Docs: DATA_MODEL §13
- [ ] 1A.6 Approval hash (CryptoKit SHA256, canonical form) + tests (order-stable, changes on edit) — Docs: DATA_MODEL §3.4
- [ ] 1A.7 `Validator.validate(step)` per §4.1 incl. cross-field rules, `channel` rule (D-247) + tests — Docs: DATA_MODEL §7.1
- [ ] 1A.8 `TaskEngine` (@MainActor, only writer, history cap 50, autosave) — Docs: ARCHITECTURE §5
- [ ] 1A.9 `TaskRepository` + `LocalDataRepository` (SwiftData), `currentStep`/closed rules (D-244) — Docs: ARCHITECTURE §4.4, DATA_MODEL §3.2
- [ ] 1A.10 Design tokens + shared components (`PrimaryButton`, `FieldRow`, `StateBadge`, `Banner`, `Toast`, `ConfirmSheet`…) + contrast test — Docs: UI_SCREENS §1–2, §11
- [ ] 1A.11 S04 Review (fields, buttons, disabled reasons, result card per D-250) with mock draft — Docs: UI_SCREENS S04, spec §5.3
- [ ] 1A.12 S05 Field editor per `FieldType` — Docs: UI_SCREENS S05
- [ ] 1A.13 S14 History (4 groups, reopen at `currentStep`, hide) — Docs: UI_SCREENS S14, DATA_MODEL §8
- [ ] 1A.14 S15 Settings shell (sections, no live data yet) — Docs: UI_SCREENS S15
- [ ] **EXIT 1A** `EasyPhoneTests` green for state machine, hash, validator

### Phase 1B — Input
Exit: **a Vietnamese sentence becomes an editable draft.**
- [ ] 1B.1 S02 Home (mic 120pt, text field, camera button, quick links, unfinished list) — Docs: UI_SCREENS S02
- [ ] 1B.2 `SpeechService` (vi-VN on device, partial transcripts, stop) + mock — Docs: ARCHITECTURE §4.3
- [ ] 1B.3 `TTSService` (stoppable, rate from settings) — Docs: spec §6.2 AC5
- [ ] 1B.4 S03 Conversation: 5 modes (listen, transcript, working, follow-up with local chips, unsupported) — Docs: UI_SCREENS S03
- [ ] 1B.5 Backend `services/metering.py`: idempotency per endpoint, attempt numbers, 18 s budget, advisory lock, spend cap, reserve/refund — Docs: API_CONTRACT §4, ARCHITECTURE §7.1
- [ ] 1B.6 pytest quota suite (402 at limit, parallel, same key once, refund on 502/500, late attempt, key mismatch, budget, day boundary) — Docs: API_CONTRACT §11
- [ ] 1B.7 `LLMClient` (model from config, structured output, 12 s timeout within budget, `max_retries=0`, repair once) — Docs: ARCHITECTURE §7.2, AI_PROMPTS §6
- [ ] 1B.8 `prompt_context.py` (14-day calendar table) + `untrusted.py` (`neutralize`, `wrap_untrusted`) + tests — Docs: AI_PROMPTS §1–2
- [ ] 1B.9 `prompts/parse.v1.md`, `task_draft.json` generated from catalog + `ENABLED_KINDS` — Docs: AI_PROMPTS §3, DATA_MODEL §6.3
- [ ] 1B.10 `POST /v1/parse` + post-processing checks — Docs: API_CONTRACT §7.1, AI_PROMPTS §9
- [ ] 1B.11 Golden fixtures E1–E8 + §8 hard cases (mocked LLM in CI) — Docs: AI_PROMPTS §7–8, §10
- [ ] 1B.12 `POST /v1/transcribe` (0 units, 30/h) + app fallback — Docs: API_CONTRACT §7.4
- [ ] 1B.13 `DraftBuilder` (`ParsedDraft` → `TaskDraft`, merge keeps `.user` fields) + tests — Docs: ARCHITECTURE §5
- [ ] 1B.14 Follow-up loop: one question at a time, `dateCandidates` chips resolved on device (D-251), D-281 rule + test — Docs: spec §6.2 AC3, AC6
- [ ] 1B.15 Live eval run (`pytest -m live`) → report in `evals/`; owner locks D-052
- [ ] **EXIT 1B** On device: type and speak "Nhắc tôi 8 giờ sáng mai uống thuốc" → Review shows editable draft

### Phase 1C — Device actions
Exit: **linked flows 1 & 2 (spec §7) work on device** (flow 1 without photo until 1D).
- [ ] 1C.1 `PermissionManager` + S18 explainer/denied (all capabilities, fallbacks, step 0 before confirm) — Docs: UI_SCREENS S18, ARCHITECTURE §5.1, D-185
- [ ] 1C.2 `CalendarService` live (full / write-only access, conflicts, `easyphone:<stepId>` url) — Docs: ARCHITECTURE §4.2, D-225
- [ ] 1C.3 `CalendarExecutor` create/update/delete + re-read verification + idempotency — Docs: ARCHITECTURE §5.1
- [ ] 1C.4 S11 Calendar today (+ detail sheet, update/delete → Review) — Docs: UI_SCREENS S11
- [ ] 1C.5 `RemindersService` + executor (create/update/delete/complete with `completed`/snooze) — Docs: spec §6.5, D-248
- [ ] 1C.6 S12 Reminders (one-tap complete + undo toast, snooze sheet) — Docs: UI_SCREENS S12, D-107
- [ ] 1C.7 `ContactsService.match` (normalization, kinship strip, nicknames, limited access) + tests — Docs: DATA_MODEL §7.2
- [ ] 1C.8 Phone normalization + masking + tests — Docs: DATA_MODEL §7.3
- [ ] 1C.9 `DeviceResolver` + S06 Picker (contact/phone/date/place/event, save nickname) — Docs: UI_SCREENS S06
- [ ] 1C.10 `CallExecutor` (`tel://` → `handedOff`, never `succeeded`) — Docs: D-102
- [ ] 1C.11 `SMSExecutor` + `MessageComposerView` bridge (`.sent`/`.cancelled`/`.failed`) — Docs: ARCHITECTURE §5.3
- [ ] 1C.12 `SupportedServices.json` (Zalo `verified:false`) + S07 Copy guide (no contacts needed, D-247) — Docs: DATA_MODEL §10, UI_SCREENS S07
- [ ] 1C.13 `PlacesService` + S13 Places (search, map preview, save Home/Work/custom, directions as `place.open`) — Docs: UI_SCREENS S13
- [ ] 1C.14 Linked steps rule (step N+1 confirm enabled only when N final/handedOff/prepared; `.linked` updates) — Docs: DATA_MODEL §3.3
- [ ] 1C.15 `HandoffPromptCoordinator` + S08 return prompt (once per hand-off) — Docs: D-242
- [ ] 1C.16 `LaunchVerifier` (`processing` → `unknown` → verify; `unknown` retry) + test — Docs: ARCHITECTURE §5.4, D-243
- [ ] 1C.17 Settings: nicknames, saved places, permissions status, maps app, snooze hour — Docs: UI_SCREENS S15
- [ ] 1C.18 XCUITest flow 2 (find contact → SMS / call) with `-uiTestScenario` — Docs: ARCHITECTURE §13
- [ ] **EXIT 1C** Real iPhone, real data: flow 2 (3 contacts named Minh → picker → SMS sent) and calendar+reminder part of flow 1

### Phase 1D — OCR
Exit: **linked flow 1 starts from a photo.**
- [ ] 1D.1 S09 capture (camera + `PhotosPicker`, 1 image, tips) — Docs: UI_SCREENS S09
- [ ] 1D.2 Save JPEG to `Application Support/ocr/<draftId>.jpg` 🔒 — Docs: ARCHITECTURE §6.4
- [ ] 1D.3 `RoutingOCRService` (Vision `vi` check → `/v1/ocr` fallback, P-24 threshold) — Docs: ARCHITECTURE §4.3
- [ ] 1D.4 `POST /v1/ocr` (multipart, ≤ 4 MB, ≤ 2048 px, not stored) — Docs: API_CONTRACT §7.3
- [ ] 1D.5 `prompts/extract.v1.md` + `POST /v1/extract` (own key, quote → UTF-16 span) + emoji/diacritics test — Docs: AI_PROMPTS §4, API_CONTRACT §7.2
- [ ] 1D.6 Injection fixtures (§8.3) pass with mocked LLM — Docs: AI_PROMPTS §8.3
- [ ] 1D.7 `ocr` step in Review: fields with spans, `nextAction`, "Tiếp tục" = confirm + append linked step, copy contact info (D-226) — Docs: DATA_MODEL §4
- [ ] 1D.8 S10 Source image (bounding box highlight) — Docs: UI_SCREENS S10
- [ ] 1D.9 No-text / blurry path (no `/v1/extract` call) — Docs: spec §6.3 AC5
- [ ] 1D.10 Test 10 real Vietnamese appointment slips → owner locks D-060
- [ ] 1D.11 XCUITest flow 1 (photo → event + reminder) with mock OCR
- [ ] **EXIT 1D** Real iPhone: photo of an appointment slip → edited fields → event + reminder created and verified

### Phase 1E — Entry points
Exit: **app opens in listening mode from each entry.**
- [ ] 1E.1 `StartListeningIntent` (`openAppWhenRun`) sets `startListeningRequested` — Docs: ARCHITECTURE §2.2
- [ ] 1E.2 App Shortcuts phrases vi (18.4+) + en fallback (`#available`) — Docs: D-012, UI_SCREENS §7
- [ ] 1E.3 Deep link `easyphone://listen` (`onOpenURL`)
- [ ] 1E.4 Control Center control (iOS 18 `ControlWidget`)
- [ ] 1E.5 Home widgets small/medium (+ unfinished count, D-244) + Lock Screen circular — Docs: UI_SCREENS §7
- [ ] **EXIT 1E** Device test: Siri phrase, Action Button, Control Center, Home widget, Lock widget, icon → all open S03 listening

### Phase 1F — Billing
Exit: **Free user blocked at quota, subscriber not.** Thesis: `.storekit` file only, no App Store Connect (D-284).
- [ ] 1F.1 `.storekit` config file with D-091 product ids (Debug) — Docs: D-091, D-208
- [ ] 1F.2 `PurchaseService` (products, purchase with `appAccountToken`, `Transaction.updates` from launch, finish rules) — Docs: ARCHITECTURE §4.1, §6.5
- [ ] 1F.3 `POST /v1/billing/verify` (JWS chain, bundle, product, env, token, D-239 transfer, D-240 Xcode env — the thesis backend runs with `ALLOW_XCODE_STOREKIT=true`) — Docs: API_CONTRACT §8.1, D-284
- [ ] 1F.4 (optional, D-284) `POST /v1/billing/notifications` (dedupe, out-of-order, status mapping) — Docs: API_CONTRACT §8.2
- [ ] 1F.5 pytest billing suite with signed test JWS — Docs: API_CONTRACT §11
- [ ] 1F.6 S16 Paywall (StoreKit prices only, restore, terms/privacy links) — Docs: UI_SCREENS S16, D-089
- [ ] 1F.7 S17 Premium quota reached + 402 routing by plan — Docs: D-241
- [ ] 1F.8 Quota in Settings + `home.quota.low` banner from `X-Quota-*` — Docs: spec §6.11 AC7
- [-] 1F.9 App Store Connect products + Sandbox tester — dropped: thesis scope, no paid account (D-284)
- [ ] **EXIT 1F** Xcode `.storekit`: purchase, renewal, expiry, restore, refund tested (Transaction Manager); Free blocked at 10, Premium not

### Phase 1G — Demo prep (thesis, D-282, D-284)
Exit: **linked flows 1 & 2 demoed end to end on the owner's iPhone.**
- [ ] 1G.1 `DELETE /v1/me` (Admin API, cascade, idempotent) + old-token test — Docs: API_CONTRACT §6.3
- [ ] 1G.2 S20 confirms + local wipe (SwiftData + `ocr/`) + sign out — Docs: ARCHITECTURE §6.6
- [ ] 1G.3 "Xóa lịch sử" (closed drafts only, D-244) / "Xóa dữ liệu ghi nhớ" — Docs: DATA_MODEL §5
- [ ] 1G.4 `PrivacyInfo.xcprivacy` + App Privacy labels + AI provider disclosure — Docs: D-187
- [ ] 1G.5 Info.plist usage descriptions (vi) complete — Docs: UI_SCREENS S18
- [ ] 1G.6 Privacy + Terms as in-app text (no public URLs, D-284) — Docs: D-188
- [ ] 1G.7 Demo backend: local + tunnel or free tier, env secrets set, `MONTHLY_SPEND_CAP_USD=5` (D-285)
- [ ] 1G.8 Accessibility pass: AX5, VoiceOver, Increase Contrast, Reduce Motion, Dark on S02/S03/S04/S06/S08/S16 — Docs: UI_SCREENS §9
- [ ] 1G.9 String scan test (no literals in `Text("…")`), every `error.<code>` has a key — Docs: UI_SCREENS §11
- [ ] 1G.10 Resilience manual test: offline, denied permission, app kill mid-action, return from other app
- [ ] 1G.11 Demo script (Vietnamese, step by step) + reinstall on the owner's iPhone 1–2 days before the defense (7-day signing, D-282)
- [ ] **EXIT 1G** Demo script run end to end on the owner's iPhone; MVP DoD (§7) all ticked

### Phase 2 — Gmail (do not start before MVP done, D-141, D-150)
- [ ] 2.0 Owner locks D-156 + quota units for summarize/draft; API_CONTRACT §9 written
- [ ] 2.1 Backend OAuth + encrypted refresh tokens + `gmail_accounts` table
- [ ] 2.2 Search / thread / summarize (cited points) / draft reply (no send)
- [ ] 2.3 "Tạo lịch từ email" → Review → calendar
- [ ] **EXIT 2** Linked flows 3 & 4

### Phase 3 — Ride & food handoff (D-142, D-160)
- [ ] 3.0 Owner locks D-161 (verified schemes); `ride`/`food` fields defined in DATA_MODEL §4
- [ ] 3.1 `HandoffExecutor` (`prepared` → open service / copy guide → `handedOff`)
- [ ] **EXIT 3** Linked flow 5

---

## 7. MVP Definition of Done (spec §12 — tick only with evidence)

- [ ] All Phase 1 linked flows run on a real iPhone with real data
- [ ] Calendar/reminder create/edit/delete verified by re-reading EventKit
- [ ] Duplicate names, ambiguous dates, OCR errors resolved before any action
- [ ] Network loss, denied permission, app kill, return-from-other-app never lose progress
- [ ] No screen claims success for a handed-off action
- [ ] Free quota enforced server-side; purchase, renewal, expiry, restore tested with the local `.storekit` file (D-284)
- [ ] Core flows pass VoiceOver and AX5 manual tests
- [ ] Unit tests: state machine, date resolution, contact matching, quota logic. UI tests: flows 1 & 2
- [ ] Demo build on the owner's iPhone, demo script run end to end (D-282)

---

## 8. Session log (newest on top, append-only, max 8 lines each)

Template:
```text
### YYYY-MM-DD — Phase X — <short title>
- Done: <item ids> (<commits>)
- In progress: <item id> — left: <what, file, function>
- Bugs: opened BUG-xxx / closed BUG-yyy
- TODOs added: <file:line tag>
- Decisions asked / answered: <D-xxx / P-xx>
- Next: <one concrete next step>
```

### 2026-11-08 — Phase 0 — Repo + project settings
- Done: 0.1 (716adcd) `.gitignore`, docs/CLAUDE.md/skills committed, xcuserdata untracked; 0.2 (this commit)
  SDKROOT iphoneos, iPhone only, iOS 18.0, Swift 6, bundle `vn.namkhanh.easyphone`, `vi` dev language, Playgrounds removed
- Verify: `git check-ignore .env` ok; build succeeded on iPhone 18 Pro simulator
- Bugs: none. Opened DOC-19 (folder name). TODOs added: ContentView.swift:3
- Next: 0.3 folder layout (ask DOC-19 first)

### 2026-11-08 — Docs — Thesis scope
- Done: D-282 – D-285 (thesis, free Apple ID, Google-only sign-in, `.storekit` billing, 5 USD cap); Spec, PROGRESS,
  CLAUDE.md, UI_SCREENS S01, ARCHITECTURE, API_CONTRACT updated. Simulator in commands → iPhone 18 Pro
- Found: Xcode build fails ("Supported platforms … is empty"); target settings differ from D-010 – D-013 → item 0.2
- Next: Phase 0 item 0.1

### 2026-11-08 — Docs — Doc set complete
- Done: DOC-1, 2, 5, 6, 7 fixed (D-277 – D-281); Spec synced (layout, hierarchy, transitions, extract `title`)
- Bugs: none. Open DOC-x items: none
- Next: Phase 0 item 0.1

### 2026-11-08 — Docs — Proposals approved
- Done: P-17 – P-40 → D-252 – D-275 (D-258 supersedes D-019); `title` in `/v1/extract` (D-276); docs updated
- Bugs: none. Closed DOC-3, DOC-4, DOC-17, DOC-18. Still open: DOC-1, DOC-2, DOC-5, DOC-6, DOC-7
- Next: Phase 0 item 0.1

### 2026-11-08 — Docs — CLAUDE.md + cross-doc review round 2
- Done: `CLAUDE.md` written; DOC-8 – DOC-16 fixed in DECISIONS, DATA_MODEL, API_CONTRACT, ARCHITECTURE, UI_SCREENS
- In progress: —
- Bugs: none. New open: DOC-17 (extract `title`), DOC-18 (pending proposals block Phase 0/1A)
- Decisions asked / answered: D-243 – D-251 added (owner asked to fix); P-17 – P-40 still pending
- Next: owner approves P-17 – P-40, then Phase 0 item 0.1

### 2026-11-08 — Docs — Planning complete
- Done: all 7 planning docs written (DECISIONS, Spec, DATA_MODEL, API_CONTRACT, AI_PROMPTS, ARCHITECTURE, UI_SCREENS) + this file
- In progress: —
- Bugs: none. Doc conflicts recorded as DOC-1 – DOC-7 (§5.2)
- Decisions asked / answered: D-242 answered (option A); P-17 – P-40 pending (§4)
- Next: Phase 0 item 0.1 (git repo + Xcode project)
