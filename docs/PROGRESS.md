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
- [ ] `cd backend && uv run pytest -q` — green (live tests excluded)
- [ ] `git status` clean at start (else note the uncommitted work in §1)
- CI: `.github/workflows/backend.yml` runs pytest + SQL migration check on every push touching `backend/` (iOS CI deferred: macOS minutes, Xcode version on runners)

### 0.5 `CLAUDE.md`
The repo root `CLAUDE.md` (project doc `CLAUDE.md`) holds the session protocol, doc map, rules and commands.
Copy it to the repo root in item 0.1. Keep it in sync when this file's protocol changes.

---

## 1. Snapshot (overwrite every session)

| Key | Value |
|---|---|
| Last updated | 2026-11-10 |
| Current phase | **Phase 1B — Input** (Phase 0 exit ✅ 2026-11-09, Phase 1A exit ✅ 2026-11-10) |
| Working on | — |
| Last commit | `[1A] S15 Settings shell` on branch `demo_git` (not pushed) |
| Build status | ✅ Simulator build; ✅ device build signed with the free Personal Team (`DEVELOPMENT_TEAM` in git-ignored `Secrets.xcconfig`) |
| Test status | ✅ iOS `test` green (incl. `ContractFixtureTests`, `TaskEnumsTests`, `TaskModelTests`, `FieldCatalogTests`, `TaskStateMachineTests`, `ApprovalHashTests`, `ValidatorTests`, `TaskEngineTests`, `TaskEngineConfirmTests`, `TaskDraftStatusTests`, `LiveTaskRepositoryTests`, `NameNormalizerTests`, `LiveLocalDataRepositoryTests`, `TokenContrastTests`, `ComponentStringsTests`, `FieldFormatterTests`, `ReviewViewModelTests`, `FieldEditorTests`, `HistoryTests`, `SettingsTests`); ✅ backend `uv run pytest -q` 113/113; ✅ `run_db_tests.sh` 6/6 (earlier session) |
| Next action | 1B.1: S02 Home — toolbar Lịch sử / Cài đặt (→ S14 / S15), `MascotView` slot (placeholder until 1B.16), `display` greeting "Bạn cần mình giúp gì?", `ListeningMic` 120pt + caption, multi-line text field + "Gửi" when non-empty, "Chụp ảnh giấy tờ", quick links (hidden in simple mode except Lịch hôm nay), "Việc chưa xong" (max 3 + Xem tất cả); replaces the user-id placeholder in `RootView` — UI_SCREENS S02 |
| Owner decisions needed now | none (0.6 kept by owner 2026-11-09). Thesis scope (D-282 – D-285): no paid Apple account, Google-only sign-in |

---

## 2. Documentation status

| Doc | Status | Notes |
|---|---|---|
| `DECISIONS.md` | ✅ written | D-001 – D-291; thesis scope D-282 – D-285 (§12.6); branding EasyPhoneK / Khoai D-287 – D-289 (§12.7); engine D-290 + Khoai style D-291 (§12.8) |
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
| P-41 | UI_SCREENS §12 | guide mascot "Khoai" | ✅ D-289 |
| P-42 | chat 2026-11-10 (Figma Make mock-up `pLty634pVp905UwgHxNDNx`) | "Khoai" palette from the app icon + `honey` fill token + SF Pro Rounded titles/buttons | ✅ D-291 |
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
| DOC-20 | `APIClientProtocol.blockingUpdates` (426 → `AppState.blockingScreen`) is not in ARCHITECTURE §4.1 | ARCHITECTURE §4.1 vs UI_SCREENS §4 | add `blockingUpdates` to §4.1 | open |
| DOC-21 | S19 CTA "Mở App Store" has no target: the thesis build is not on the App Store (D-282) | DECISIONS D-282 vs UI_SCREENS S19 | owner kept the button as a no-op (2026-11-09); later: new D-id to drop it or reword it (e.g. "cài lại từ Xcode") | open |
| DOC-22 | `succeeded` + `userEdited` → `awaitingApproval` is "a new `update` action", but nothing says who changes `operation` `create` → `update` or sets `targetRef` from `resultEvidence`; re-confirming a `create` step would hit the idempotency check (D-105) and skip the edit | DATA_MODEL §1.5 vs §3.5, ARCHITECTURE §5.1 step 5 | engine on that edit sets `operation = .update`, `targetRef` from evidence (`ek:event:<id>`), clears `resultEvidence` — owner to confirm | fixed (D-290) |
| DOC-23 | UI_SCREENS §2 / §9 give texts but no keys for "Bước {n}/{total}", "Trạng thái: {label}", "Bấm hai lần để sửa", ", cần kiểm tra lại" | UI_SCREENS §2, §9 vs §0 rule 1 | add keys `stepIndicator.label`, `a11y.state`, `a11y.field.hint`, `a11y.field.needsReview` to UI_SCREENS (already used in code) | fixed (owner OK 2026-11-10, UI_SCREENS §2, §9) |
| DOC-24 | Mic VoiceOver value "Đang nghe" (UI_SCREENS §9) has no key | UI_SCREENS §9 vs §0 rule 1 | add `home.mic.listening.a11y` = Đang nghe (used in code) | fixed (owner OK 2026-11-10, UI_SCREENS §9) |
| DOC-25 | Bool field values (`allDay`, `completed`) have no display text in UI_SCREENS §10 | UI_SCREENS §10.3 | add `common.yes` = Có / `common.no` = Không (used in code) | fixed (owner OK 2026-11-10, UI_SCREENS §10.3) |
| DOC-26 | `state.handedOff` = "Cần hoàn tất trong {app}" but no key names the Phone app for calls | DATA_MODEL §8 vs UI_SCREENS §10 | add `app.phone` = Điện thoại (used in code) | fixed (owner OK 2026-11-10, UI_SCREENS §10.3) |
| DOC-27 | D-289 needs a `settings.pet` toggle but DATA_MODEL §5 `AppSettings` has no field; S15 "{hour} giờ" has no key | DECISIONS D-289 vs DATA_MODEL §5; UI_SCREENS S15 | add `petEnabled: Bool = true` to DATA_MODEL §5 and key `settings.snoozeHour.value` to S15 (both used in code) | open |
| DOC-19 | Spec §3.2 layout root is `EasyPhone/`; the repo's app folder, target and scheme are `EasyPhoneAI` (CLAUDE.md §8 uses `EasyPhoneAI`) | Spec §3.2 vs repo | keep `EasyPhoneAI/` as the app root (no project rename) | fixed (D-286) |

### 5.3 Code TODOs left in source
List every `// TODO(spec):` and `// TODO(decision):` with file + line. Remove when resolved.

| File:line | Tag | Note |
|---|---|---|
| `EasyPhoneAI/App/EasyPhoneApp.swift:14` | TODO(spec) | SwiftData store open failure → `fatalError`; no recovery screen specified (D-104) |
| `EasyPhoneAI/Features/SignIn/SignInViewModel.swift:26` | TODO(decision) | `auth.signInFailed` has no `error.auth.signInFailed` key; S01 uses `signIn.failed` (UI_SCREENS S01) |
| `EasyPhoneAI/Features/SignIn/SignInView.swift:67` | TODO(spec) | Google "G" mark missing (no licensed asset) |
| `EasyPhoneAI/Features/SignIn/SignInView.swift:79` | TODO(spec) | legal links no-op until in-app Terms/Privacy (1G.6, D-284) |
| `backend/app/errors.py:118` | TODO(spec) | framework HTTP errors other than 404/405 have no §3.2 code → rendered as `500 internal` |
| `EasyPhoneAI/Core/Networking/APIClientProtocol.swift:11` | TODO(spec) | `blockingUpdates` not in ARCHITECTURE §4.1 (DOC-20) |
| `EasyPhoneAI/Core/Networking/RetryPolicy.swift:19` | TODO(spec) | jitter size unspecified; 0–0.5 s |
| `EasyPhoneAI/Core/Networking/RetryPolicy.swift:23` | TODO(spec) | no `Retry-After` upper bound; clamped to 30 s |
| `EasyPhoneAI/Core/Networking/APIClient.swift:105` | TODO(spec) | 426 without `details.minVersion` → empty version on S19 |
| `EasyPhoneAI/Core/Models/CachedEntitlement.swift:15` | TODO(spec) | unknown `plan` → `free` (display only) |
| `EasyPhoneAI/Features/UpdateRequired/UpdateRequiredViewModel.swift:20` | TODO(decision) | S19 "Mở App Store" is a no-op: no App Store listing in thesis scope (D-282 vs UI_SCREENS S19, DOC-21) |
| `EasyPhoneAI/Features/UpdateRequired/UpdateRequiredView.swift:14` | TODO(spec) | S19 icon unspecified; SF Symbol `arrow.down.app` |
| `EasyPhoneAI/Core/Models/FieldSource.swift:67` | TODO(spec) | `NormalizedRect` undefined in DATA_MODEL §1.7; fields `x, y, width, height` (0–1, origin bottom-left) |
| `EasyPhoneAI/Core/Models/Field.swift:40` | TODO(spec) | DATA_MODEL §2 `labelKey` has no args but `Field` has no kind → `labelKey(kind:)` |
| `EasyPhoneAI/Core/Models/FieldCatalog.swift:6` | TODO(spec) | DATA_MODEL §4 gives no JSON layout for `field_catalog.json`; the Swift `Codable` shape is used |
| `EasyPhoneAI/Core/Models/FieldCatalog.swift:140` | TODO(spec) | `channel` options list only `sms`; SupportedServices ids (DATA_MODEL §10) come with 1C.12 |
| `EasyPhoneAI/Core/Engine/ApprovalHash.swift:10` | TODO(spec) | §3.4 canonical form does not escape `\n` / `=` inside values; implemented verbatim |
| `EasyPhoneAI/Core/Engine/Validator.swift:87` | TODO(spec) | §7.1 checks encoding of required fields only; optional values (e.g. a malformed `endDate`) are not flagged |
| `EasyPhoneAI/Core/Engine/Validator.swift:191` | TODO(spec) | D-253 phone check is a minimal §7.3 matcher; replace with the 1C.8 normalizer |
| `EasyPhoneAI/Core/Engine/TaskEngine.swift:157` | TODO(spec) | no `userEdited` row for processing/prepared/handedOff/failed/unknown/closed → edits refused there |
| `EasyPhoneAI/Core/Engine/TaskEngine.swift:44` | TODO(spec) | no executor for a kind → `failed("unsupported")`; no code specified |
| `EasyPhoneAI/Core/Engine/TaskEngine.swift:76` | TODO(spec) | MessageUI `.failed` → `messages.sendFailed` (not in ARCHITECTURE §9) |
| `EasyPhoneAI/Core/Engine/TaskEngine.swift:93` | TODO(spec) | empty evidence → `failed("evidence.missing")`; no code specified |
| `EasyPhoneAI/Core/Models/HistoryGroup.swift:35` | TODO(spec) | draft with no steps: not closed, group `needsYou` |
| `EasyPhoneAI/Core/Services/Live/LiveTaskRepository.swift:60` | TODO(spec) | failed SwiftData save has no UI; logged, retried on next save (D-104) |
| `EasyPhoneAI/Core/Services/LocalDataRepository.swift:4` | TODO(spec) | ARCHITECTURE §4.4 lists no methods for `LocalDataRepository`; simplest CRUD set used |
| `EasyPhoneAI/Core/UI/Components/Banner.swift:14` | TODO(spec) | Banner icon not named; `xmark.octagon` / `exclamationmark.triangle` |
| `EasyPhoneAI/Features/Review/ReviewViewModel.swift:51` | TODO(spec) | human rows for 🔒 `contactId` (name + photo + masked number) and `calendarId` (calendar |
| `EasyPhoneAI/Features/Review/ReviewViewModel.swift:138` | TODO(spec) | "Mở trong Lịch" / "Mở trong Lời nhắc" (secondary) need the calendar / reminders services (1C). |
| `EasyPhoneAI/Features/Review/ReviewViewModel.swift:151` | TODO(spec) | `permission.<c>.denied` → Primary `perm.<c>.fallback` + "Tôi đã làm xong" comes with S18 (1C.1). |
| `EasyPhoneAI/Features/Review/ReviewViewModel.swift:181` | TODO(spec) | the snoozed-to time comes from the executor (1C.5); the step's `dueDate` is shown until then. |
| `EasyPhoneAI/Features/Review/ReviewViewModel.swift:190` | TODO(spec) | no result text for reminder update / delete; the state label "Đã xong" is shown. |
| `EasyPhoneAI/Features/Review/ReviewViewModel.swift:202` | TODO(spec) | no result text for other hand-offs (copy path, D-162); the executor's `handoffNote` or |
| `EasyPhoneAI/Features/Review/ReviewViewModel.swift:227` | TODO(spec) | `coordinate` / `placeRef` rows open S13 (1C.13), contact rows open S06 (1C.9). |
| `EasyPhoneAI/Features/Review/ReviewViewModel.swift:253` | TODO(spec) | `.needsUI` (SMS composer, ARCHITECTURE §5.3) is presented from 1C.11. |
| `EasyPhoneAI/Features/Review/ReviewView.swift:56` | TODO(spec) | calendar conflict card (`review.conflict.*`) needs CalendarService (1C.2). |
| `EasyPhoneAI/Features/Review/ReviewView.swift:63` | TODO(spec) | "Xem ảnh gốc" (S10, 1D.8) and "Chọn" (S06 picker, 1C.9) open their screens later. |
| `EasyPhoneAI/Features/FieldEditor/FieldEditorViewModel.swift:85` | TODO(spec) | no editor message for other invalid encodings (pickers cannot produce them). |
| `EasyPhoneAI/Features/FieldEditor/FieldEditorViewModel.swift:115` | TODO(spec) | the snooze hour comes from `AppSettings.snoozeMorningHour` (S15, 1C.17); default 8 until then. |
| `EasyPhoneAI/Features/FieldEditor/FieldEditorViewModel.swift:141` | TODO(spec) | the default time of an empty date-time editor is not specified. |
| `EasyPhoneAI/Features/FieldEditor/FieldEditorView.swift:52` | TODO(spec) | `address` → "Tìm trên bản đồ" opens the S13 picker (1C.13). |
| `EasyPhoneAI/Features/FieldEditor/FieldEditorView.swift:67` | TODO(spec) | "Đọc to" needs TTSService (1B.3). |
| `EasyPhoneAI/Features/History/HistoryViewModel.swift:72` | TODO(spec) | UI_SCREENS S14 names no kind icons; SF Symbols chosen here. |
| `EasyPhoneAI/Features/History/HistoryViewModel.swift:87` | TODO(spec) | `{mainValue}` of `history.summary` is only shown by example ("anh Minh"); per-kind field chosen here. |
| `EasyPhoneAI/Features/History/HistoryViewModel.swift:98` | TODO(spec) | S14 gives no format for dates older than yesterday; `common.dateTimeFormat` used. |
| `EasyPhoneAI/Features/Settings/SettingsView.swift:29` | TODO(spec) | range of the rate slider is not specified; 0.3–0.6 around the 0.45 default (DATA_MODEL §5). |
| `EasyPhoneAI/Features/Settings/SettingsView.swift:30` | TODO(spec) | "Nghe thử" needs TTSService (1B.3). |
| `EasyPhoneAI/Features/Settings/SettingsView.swift:39` | TODO(spec) | the "live preview" content of the text-size row is not specified. |
| `EasyPhoneAI/Features/Settings/SettingsView.swift:54` | TODO(spec) | "mẹ → Nguyễn Thị Lan" needs the contact name from ContactsService (1C.7). |
| `EasyPhoneAI/Features/Settings/SettingsView.swift:61` | TODO(spec) | "Địa điểm đã lưu" opens S13 (1C.13). |
| `EasyPhoneAI/Features/Settings/SettingsView.swift:80` | TODO(spec) | "Quyền truy cập" rows need PermissionManager (1C.1). |
| `EasyPhoneAI/Features/Settings/SettingsView.swift:100` | TODO(spec) | "Chính sách quyền riêng tư" / "Điều khoản sử dụng" open in-app text (1G.6, D-284). |
| `EasyPhoneAI/Features/Settings/SettingsView.swift:110` | TODO(spec) | "Xóa tài khoản" needs `DELETE /v1/me` + local wipe (1G.1–1G.2). |
| `EasyPhoneAI/Features/Settings/SettingsView.swift:134` | TODO(spec) | quota row + reset time + "Nâng cấp Premium" / "Quản lý gói" come with 1F.6–1F.8. |
| `EasyPhoneAI/App/RootView.swift:64` | TODO(spec) | S02 Home replaces this in 1B.1; until then show the signed-in user id (EXIT 0 check). |
| `EasyPhoneAI/App/RootView.swift:85` | TODO(spec) | the other routes get their screens in their own items (1B–1F). |
| `EasyPhoneAI/Core/Models/LocalModels.swift:54` | TODO(decision) | DATA_MODEL §5 vs D-289 (`settings.pet` toggle, on by default) — field added here (DOC-27). |
| `Config/Release.xcconfig:2` | TODO(decision) | D-036: no production backend in thesis scope (D-284); Release uses the Debug backend URL |

### 5.4 Closed (append-only)
| ID | Closed on | Commit | Note |
|---|---|---|---|
| DOC-8 – DOC-16 | 2026-11-08 | docs only | resolved by D-243 – D-251 |
| DOC-3, DOC-4, DOC-17, DOC-18 | 2026-11-08 | docs only | resolved by D-266, D-253, D-276, D-252 – D-275 |
| DOC-1, DOC-2, DOC-5, DOC-6, DOC-7 | 2026-11-08 | docs only | resolved by D-277 – D-281 |
| DOC-22 | 2026-11-10 | D-290 commit | owner OK'd the proposed fix; `TaskEngine.turnIntoUpdate` |
| DOC-19 | 2026-11-09 | 0.3 commit | resolved by D-286 (keep `EasyPhoneAI/`) |
| TODO `SignInView.swift:15` | 2026-11-09 | 6bb0f44 | S01 uses the owner's icon art (`appLogo`) |

---

## 6. Phase checklists

Each item: `- [ ] <id> <task> — Docs: … — Verify: …`. Exit criteria come from spec §4 and must all be `[x]`
before the next phase starts. Architecture order per ARCHITECTURE §13.1.

### Phase 0 — Skeleton
Exit: **sign in with Google (Simulator + owner's iPhone, free Apple ID), backend returns the user id** (`GET /v1/me`, D-283).
- [x] 0.1 git repo, `.gitignore` (`.env`, `*.p8`, `Secrets.xcconfig`, D-207), `CLAUDE.md` at root — Verify: `git check-ignore .env` (716adcd)
- [x] 0.2 Xcode project: iOS 18.0, iPhone only, Swift 6 strict concurrency, SPM — Docs: D-010–D-018 (9022272) — bundle id `vn.namkhanh.easyphone`, display name "EasyPhone", development language `vi`, default MainActor isolation removed (ARCHITECTURE §8), App Groups off (D-284)
- [x] 0.3 Folder layout `App/ Core/{Models,Engine,Services,Networking,Persistence,Permissions,UI} Features/ Intents/ Widgets/ Resources/` — Docs: ARCHITECTURE §2, D-258 (4653af9) — D-286: empty app folders are on disk only (no `.gitkeep` inside the synchronized folder); `Widgets/` at repo root
- [x] 0.4 `Localizable.xcstrings` (vi source) + `InfoPlist.xcstrings` created — Docs: UI_SCREENS §0, §6 S18 (b19e21f) — seeded `common.*` (§5) + 8 usage descriptions (S18), `extractionState: manual`; `vi` is the development language (Xcode drops it from `supported`; `vi.lproj` still built); Info.plist keys themselves come in 1G.5
- [x] 0.5 `AppEnvironment.live()` / `.mock()`, `AppState`, `Router` (empty routes) — Docs: ARCHITECTURE §2.2, §3 (b74d9de) — no service properties yet (each added by its item); `\.appEnv` defaults to mock; `ContentView` → `RootView` (`NavigationStack`, `ProgressView` placeholder); `Plan` + `CachedEntitlement` in `Core/Models/`
- [x] 0.6 SwiftData `ModelContainer` with `VersionedSchema` v1 (empty models ok) — Docs: DATA_MODEL §12 (9d9da26) — `SchemaV1` (1.0.0, no models yet) + `EasyPhoneMigrationPlan`, `ModelContainerFactory.make(inMemory:)`; verified: app launches on simulator, `default.store` created
- [x] 0.7 `Config.xcconfig` (Debug/Release `API_BASE_URL`, Supabase URL + anon key only) — Docs: D-207, D-208 (1af55a3 + project wiring commit after it) — `Config/{Base,Debug,Release,Secrets.example}.xcconfig` + partial `Config/Info.plist` at repo root (non-target folder ref in project), `Core/Networking/AppConfig.swift`, `AppEnvironment.config`; target base configs = `specialized-configurations` in `project.xcproj` (new Xcode format, hand-editable), `INFOPLIST_FILE = Config/Info.plist`. Verified: Debug + Release build, built Info.plist `APIBaseURL = http://127.0.0.1:8000`, Supabase keys empty until 0.8, app launches on simulator
- [x] 0.8 Supabase project (free tier) + Google OAuth client (Google Cloud, free): Google provider enabled, redirect URL for the app — Docs: D-283 — Verify: test sign-in in dashboard (commit after a556285) — project `ssbppiwuzuxptyzqxlcq` (Singapore, Free); Google Cloud project `EasyPhone`, consent External + Testing (owner's Gmail = test user), OAuth client type Web, redirect `https://<ref>.supabase.co/auth/v1/callback`; Supabase: Google on, Email off, signups allowed, redirect URL `vn.namkhanh.easyphone://login-callback`; app uses the **publishable** key (`sb_publishable_…`, replaces legacy anon, D-207) in git-ignored `Config/Secrets.xcconfig`. Verified: `/auth/v1/settings` google=true email=false; browser sign-in via `/auth/v1/authorize?provider=google` → owner's user in Auth › Users; built Info.plist has Supabase URL + key
- [x] 0.9 `AuthService` live (Supabase Swift SDK, Google only) + mock — Docs: ARCHITECTURE §4.1, D-283 (07da01e) — SPM `supabase-swift` 2.55.6, product `Auth` only (owner added in Xcode; new format keys `packages` + `package-product-members`); `Core/Services/{AuthService,ServiceError}.swift`, `Live/LiveAuthService.swift` (PKCE, Keychain, `signOut` falls back to `.local`), `Mock/MockAuthService.swift` (`Mutex`); `AppEnvironment.auth`; RootView streams `sessionUpdates` → `AppState.session`; `CFBundleURLTypes` scheme `vn.namkhanh.easyphone`. Verified: build, 19 tests, app launches on simulator. Real Google sign-in exercised in 0.10 (needs the S01 button)
- [x] 0.10 S01 Sign-in screen (Google button, legal text) + `#Preview` — Docs: UI_SCREENS S01 (4e224e6 + 4704594) — Built: `Features/SignIn/{SignInView,SignInViewModel}.swift`, `UserMessage` (D-265), RootView switches on `session` (signed in → user id placeholder until S02), 7 `signIn.*` keys, slice of 1A.10 (6 color assets, `Core/UI/Tokens.swift`, `PrimaryButton`, `DemoDataBadge`; `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = NO` in Base.xcconfig because asset `primary` collides with `Color.primary`). Verified: build, 23 tests, S01 renders on Simulator; owner signed in with real Google account on Simulator (Google asked for a passkey → "Try another way") → user id shown; app relaunch keeps the session (Keychain). Cancel path covered by unit test only
- [x] 0.11 Backend skeleton: FastAPI, `config.py` (pydantic-settings), `deps.py`, request-id middleware, error envelope handler — Docs: ARCHITECTURE §7, §9.3; API_CONTRACT §3 (4a37612) — `uv` project (`pyproject.toml`, Python 3.12 pinned, `httpx2` for TestClient); `app/{main,config,deps,errors,request_id}.py` + empty `routers/ schemas/ services/ repositories/ prompts/`; `AppError` + handlers (AppError, validation → 422 `invalid_input` first field no values, 404/405 → `not_found`, unhandled → 500 `internal`), vi/en fallback messages = UI_SCREENS §8 texts; `X-Request-Id` `req_<ulid>` on every response (also 500); `.env.example` (`!.env.example` in `.gitignore`). Verified: `uv run pytest -q` 11/11, uvicorn + curl → 404 envelope + header, `Accept-Language: en` works
- [x] 0.12 `GET /v1/health` (no auth) — Verify: pytest + curl (d65ff06) — `routers/health.py` + `schemas/health.py` (`HealthResponse`), version/schemaVersion from `Settings`; no client-version check (uptime monitor). Verified: pytest 14/14, curl → 200 `{"status":"ok","version":"0.1.0","schemaVersion":1}` + `X-Request-Id`
- [x] 0.13 JWT verification (`sub`, `exp`, `aud`) — Verify: pytest 401 cases (eb03096) — `app/auth.py` (`verify_token`, `CurrentUser`), `deps.current_user`; ES256/RS256 via project JWKS (project uses ES256), HS256 fallback with `SUPABASE_JWT_SECRET`; `JWT_AUDIENCE` in config; JWKS unreachable → 500 `internal`; `pyjwt[crypto]` added. Verified: pytest 35/35 (fake JWKS), real project JWKS loads. **Profile upsert (D-236) moved to 0.15** (needs the 0.14 table + DB connection; owner OK'd plan)
- [x] 0.14 SQL migration: `profiles`, `subscriptions`, `usage_events` (incl. `attempt`, D-246) + RLS (no `gmail_accounts`) — Docs: DATA_MODEL §9 — `backend/migrations/0001_init.sql` (tables verbatim §9, select-own policies `to authenticated`, `revoke` client writes; folder choice not in docs), `checks/{supabase_stub,0001_check}.sql` + `run_local.sh` (Docker Postgres 16): all checks pass, negative test (no RLS) fails as expected. (de97acf + fdc4e31) — owner ran the SQL in Supabase SQL Editor; REST anon → `200 []` for the 3 tables, `gmail_accounts` → `PGRST205`, anon insert → `42501`
- [x] 0.15 `GET /v1/me` returning `MeResponse` + `X-Quota-*` headers + profile upsert (D-236, deleted auth user → 401, from 0.13) — Docs: API_CONTRACT §2, §6.2 — Built: `asyncpg` lazy pool (`app/db.py`, `statement_cache_size=0` for the Supabase pooler; `/v1/health` never opens it), `deps.{db,clock,authed_user}` (`AuthedUser` = JWT + upsert; `current_user` alone stays for `DELETE /v1/me`), `repositories/{profiles,subscriptions,usage}.py`, `services/accounts.py` (locale from `Accept-Language`, **set on create only** — owner 2026-11-09; FK violation → 401), `services/quota.py` (premium iff any row qualifies, local-day window `[midnight, next midnight)`), `schemas/me.py`, `routers/me.py`. Tests: `test_quota.py`, `test_me.py` (fakes), `test_db.py` (marker `db`, real Postgres via `migrations/checks/run_db_tests.sh`, also in CI). (ea9f3cc + 207b14a) — Verified on Supabase: owner's `backend/.env` (session pooler), real Google access token → `200` with own `userId`, `plan: free`, `X-Quota-*` 10/10, one `profiles` row created (`vi`); a 2nd call with `Accept-Language: en` → still `vi`, still one row; bad token → `401`. Swift `MeResponse` DTO comes with 0.16, contract fixture with 0.18
- [x] 0.16 `APIClient` actor: headers, 20 s timeout, `RetryPolicy`, 401 refresh-once, 426 → S19 — Docs: API_CONTRACT §10, ARCHITECTURE §10 (459aa23) — Built: `Core/Networking/{APIClientProtocol,APIClient,RetryPolicy,HTTPTransport,IdempotencyKey,ClientInfo,Broadcast}.swift`, DTOs `Core/Networking/DTO/{HealthResponse,MeResponse,APIErrorEnvelope}.swift` (unknown enum → `.unknown`, unknown `plan` → `.free`), `Core/Models/AppError.swift` (ARCHITECTURE §9.1 + `code`), `MockAPIClient` (hard-coded until 0.18 fixtures), `AppEnvironment.api`, `AppState.apply(me:)/apply(quota:)` (memory only until 1A.9), RootView calls `/v1/me` on sign-in/launch and listens to `quotaUpdates` / `blockingUpdates`. Retry: timeout/other network, `500`, `503 upstream_error` → 1 s / 3 s + 0–0.5 s jitter; offline + TLS fail fast (ARCHITECTURE §11); `429` once (≤ 30 s); parallel 401s share one refresh; 2nd 401 or failed refresh → `auth.signOut()`. Tests: `RetryPolicyTests`, `APIClientTests` (stub transport), `DTODecodingTests`, `AppStateTests`. Verified: build + all tests green; Simulator (restored session) + local uvicorn → app log `GET /v1/me 200 attempt=1 req_…`, uvicorn `GET /v1/me 200` (no ATS change needed for `http://127.0.0.1`). 401/426/retry paths unit-tested only
- [x] 0.17 S19 Update required screen — Docs: UI_SCREENS S19 (a4d63b2) — `Features/UpdateRequired/{UpdateRequiredView,UpdateRequiredViewModel}.swift` (3 previews incl. AX5/dark), `update.title/body/cta` keys (`{minVersion}` → `%@`), RootView `.fullScreenCover` bound to `AppState.blockingScreen` (no close, `interactiveDismissDisabled`); CTA no-op per owner (DOC-21). Verified: build + 74 tests green (`UpdateRequiredViewModelTests`); Simulator with a scratch 426 stub on :8000 → restored session calls `/v1/me` → S19 shows "tối thiểu 1.2.0"; AX5 readable, body scrolls, button pinned
- [x] 0.18 Contract fixtures folder `backend/tests/fixtures/contract/` shared with iOS tests — Docs: API_CONTRACT §11 (ccff97e) — 16 files named per §11 (`health.ok`, `me.free`, `me.premium`, `error.<code>` × 13 §3.2 codes, `.response.json`); backend `schemas/error.py` (`ErrorEnvelope`, `extra=forbid`) + `tests/test_contract_fixtures.py` (validate + byte round-trip, every code has a fixture = `errors.MESSAGES`, vi fallback text, no 🔒 keys, rendered errors match the model); folder added to `EasyPhoneTests` as a synchronized folder in `project.xcproj` (test bundle only, not in the app) + `EasyPhoneTests/ContractFixtureTests.swift` (decode → re-encode keeps keys, `details`, `apiError` code). Owner chose option A: `MeResponse.mock` / `HealthResponse.mock` stay in code, test asserts equal to fixtures (`MockAuthService.userId` = contract UUID). Verified: both suites green; changing `"plan"` in `me.free` made pytest **and** Swift fail, restored. Request fixtures + parse/extract/billing fixtures come with 1B/1D/1F; `error.<code>` string keys still missing → 1G.9
- [x] 0.19 Backend reachable from iPhone (tunnel, D-037) (eda3fdb) — Cloudflare quick tunnel (`cloudflared`, no account, HTTPS → no ATS change); command in CLAUDE.md §8, `Secrets.example.xcconfig` explains `API_BASE_URL`; owner's git-ignored `Secrets.xcconfig` points at the tunnel. Verified on Mac: tunnel `/v1/health` 200 + `X-Request-Id`, `/v1/me` no token 401; Simulator app built with the tunnel URL → uvicorn `GET /v1/me 200`, `userId` shown. Owner: iPhone Safari → `/v1/health` → `{"status":"ok"…}` (2026-11-09). Quick tunnel URL changes every run (stable URL → 1G.7)
- [x] **EXIT 0** Simulator **and** owner's iPhone (installed from Xcode, free Apple ID): sign in with Google → app shows `userId` from `/v1/me` (hash in §8 / git log) — 2026-11-09: owner's iPhone 16 Pro Max, Personal Team `DEVELOPMENT_TEAM` in git-ignored `Secrets.xcconfig` (not in `project.xcproj`), built with `xcodebuild -allowProvisioningUpdates` + `devicectl device install app`, Developer Mode on, developer profile trusted; owner signed in with Google → `userId` shown, uvicorn `GET /v1/me 200` via tunnel. Free signing expires after 7 days (reinstall, 1G.11). Owner: kill + relaunch on iPhone keeps the session (Keychain)

### Phase 1A — Core engine
Exit: **unit tests pass for all state transitions.**
- [x] 1A.1 Enums `TaskKind`, `TaskOperation`, `TaskState`, `TaskEvent`, `FieldType`, `FieldSource` (+ JSON `type` discriminator) — Docs: DATA_MODEL §1 — `Core/Models/{TaskEnums,FieldSource}.swift`: raw values verbatim, unknown raw value → decoding error (owner OK 2026-11-09), `TaskState.isFinal` (D-122) / `isClosed` (D-244), `TaskKind.allowedOperations` (§1.2 valid pairs, for 1A.7), `FieldSource` hand-written `Codable` with `type` key (+ `isOCR`), `SourceSpan`, `NormalizedRect`. Verified: `EasyPhoneTests/TaskEnumsTests.swift` (7 tests: raw lists, final/closed, every kind×operation pair, every `FieldSource` case exact JSON + round-trip, bad JSON throws) + full suite green (e7bc07c)
- [x] 1A.2 `Field`, `Ambiguity`, `Candidate`, `TaskStep`, `StateChange`, `TaskDraft @Model`, `InputMode` — Docs: DATA_MODEL §2–3 (56ab866) — `Core/Models/{Field,TaskStep,TaskDraft}.swift`, `TaskDraft` added to `SchemaV1` (still 1.0.0, nothing shipped); `AmbiguityKind` enum; `labelKey(kind:)` takes the step kind (TODO(spec)); `TaskStep.field(_:)` helper; `currentStep`/`isClosed`/`overallStatus` left for 1A.9. Verified: `EasyPhoneTests/TaskModelTests.swift` (6 tests: JSON keys, step round-trip, `needsReview` D-126, label key, raw values, SwiftData insert → fetch in a fresh context keeps `steps` equal) + full suite green
- [x] 1A.3 `FieldCatalog.swift` (incl. §4.1 per-operation required) + `backend/app/schemas/field_catalog.json`, equality test — Docs: DATA_MODEL §4, §4.1 (4e6948d) — `FieldSpec` (`deviceOnly`, `appBuilt`, `options`, `operations` = "op=…"), `RequiredRule` (`requiresTargetRef`, `conditional` with `equals` / `notPhoneNumber` conditions for D-247, D-253, `customLabel`), `FieldCatalog.mvp` (6 MVP kinds; Phase 2/3 not listed, D-150); JSON = `Codable` form of `.mvp` (written by a one-off script, all non-optional keys explicit). Verified: `EasyPhoneTests/FieldCatalogTests.swift` (7 tests; reads the backend file via `#filePath`, works on Simulator only) + `backend/tests/test_field_catalog.py` (4 tests); editing one option in the JSON made the Swift equality test fail, restored. Rule evaluation (incl. phone check) is 1A.7
- [x] 1A.4 `transition(state, event, context)` pure function — Docs: DATA_MODEL §1.5 (d14492e) — `Core/Engine/TaskStateMachine.swift`: `TaskStateMachine.transition(_:_:context:)` (one `switch`, one case per table row), `TransitionContext.composerDismissed` (D-222; ignored outside `processing`, where `userCancelled` follows "any non-final"); illegal → `nil` + `Logger.warning` (category `stateMachine`). Verified: `TaskStateMachineTests` (4 smoke tests) + full suite green; exhaustive pairs = 1A.5
- [x] 1A.5 Tests: every table row passes; every other pair → `nil` (incl. D-222, D-242, D-243 rows) — Docs: DATA_MODEL §13 (83d905a) — `TaskStateMachineTests`: independent `expectedTable` copied from §1.5 (29 pairs × `composerDismissed` false/true = 58 entries), loop over all 11 states × 13 events × 2 contexts = 286 cases, closed states never leave except `succeeded + userEdited`. Verified: suite green twice in a row
- [x] 1A.6 Approval hash (CryptoKit SHA256, canonical form) + tests (order-stable, changes on edit) — Docs: DATA_MODEL §3.4 (a56a2a3) — `Core/Engine/ApprovalHash.swift`: `canonical(_:)` verbatim §3.4 (ids sorted by UTF-8 bytes, all fields incl. 🔒), `hash(_:)` lowercase hex, `matches(_:)` (no stored hash → false, for the executor check). Storing/clearing the hash on `userConfirmed`/`awaitingApproval` = `TaskEngine` (1A.8). Verified: `EasyPhoneTests/ApprovalHashTests.swift` (9 tests incl. a `shasum -a 256` vector, field order, every field edit, 🔒 field, `targetRef`, ignores state/source/confidence) + full suite green
- [x] 1A.7 `Validator.validate(step)` per §4.1 incl. cross-field rules, `channel` rule (D-247) + tests — Docs: DATA_MODEL §7.1 (733fbc5) — `Core/Engine/Validator.swift`: `validate(_:now:serviceIds:catalog:)` → `[ValidationIssue]` (`fieldId?` + `Reason`: `missingTargetRef`, `missing`, `invalidEncoding`, `ambiguous`, `endBeforeStart`, `inPast`, `unknownOption`, `unsupportedOperation`), order = `targetRef` then catalog order (follow-up = first issue); `requiredFieldIds` / `applyRequired` (conditional rules: `channel = sms` D-247, `notPhoneNumber` D-253, `label = custom`); encodings per §1.6 (dateTime needs seconds + offset); past check (5 min) and end > start only on required fields of the op (delete hints skipped); `serviceIds` injected until `SupportedServices.json` (1C.12); `now` passed in (no Clock yet). D-281 follow-up wording = 1B.14. Verified: `EasyPhoneTests/ValidatorTests.swift` (17 tests, 13 §4.1 rows × complete/empty + coverage of every catalog pair, sms vs zalo, phone recipient, customLabel, ambiguity, encodings, 5-min boundary) + full suite green
- [x] 1A.8 `TaskEngine` (@MainActor, only writer, history cap 50, autosave) — Docs: ARCHITECTURE §5 — split into 8a / 8b: **8a done** (08890ed): `Core/Engine/TaskEngine.swift` (`apply`, `revalidate`, `edit`, `cancel`/`retry`/`markDone`; one private writer `applyInPlace`: hash stored on `userConfirmed`, cleared on entering `awaitingApproval`, `attempt += 1` on entering `processing`, history cap 50, `updatedAt` + `repository.save` after every mutation; edits refused outside `draft`/`needsInfo`/`awaitingApproval`/`succeeded`), `Core/Services/TaskRepository.swift` (`draft`/`save` only) + `Mock/MockTaskRepository.swift`; `now` injected. Verified: `EasyPhoneTests/TaskEngineTests.swift` (14 tests) + full suite green. **8b done** (f9b675f): `Core/Engine/StepExecutor.swift` (`UIEffect.composer`, `ExecutionOutcome`, `@MainActor StepExecutor`, `ComposerResult`, `ConfirmResult`), `Mock/MockStepExecutor.swift`; `TaskEngine(executors:)`, `confirm()` (§5.1 steps 1–3: awaitingApproval + `validate()` empty → `userConfirmed` saved before executing → hash recheck → executor; steps 4–6 belong to executors), `finish` maps outcome → event (`verified` needs non-empty evidence D-124, `handedOff` sets note + `handoffPromptShown = false` D-242, `failed` stores `errorCode`, `needsUI` stays `processing`), `composerFinished` (`.sent` → `msg:sent:<ISO in draft tz>`, `.failed`, `.cancelled` + `composerDismissed` D-222); error fields cleared on each `processing` entry. Verified: `EasyPhoneTests/TaskEngineConfirmTests.swift` (11 tests) + full suite green. Linked-step rule = 1C.14
- [x] 1A.9 `TaskRepository` + `LocalDataRepository` (SwiftData), `currentStep`/closed rules (D-244) — Docs: ARCHITECTURE §4.4, DATA_MODEL §3.2 — split into 9a / 9b: **9a done** (45744b8): `Core/Models/HistoryGroup.swift` (`HistoryGroup` raw = `history.group.<raw>`, `TaskState.historyGroup` per §8, `TaskDraft.currentStep` / `isClosed` / `overallStatus` / `isUnfinished` / `closedStepCount`, D-244), full `TaskRepository` protocol (§4.4), `Live/LiveTaskRepository.swift` (main context, insert on first save, in-memory state filters after one fetch, errors logged by type only), mock completed (`nonisolated init` for `AppEnvironment.mock()`), `AppEnvironment.drafts` + `@MainActor live(container:)` (built in `EasyPhoneApp.init`). Verified: `EasyPhoneTests/TaskRepositoryTests.swift` (4 status + 7 SwiftData in-memory tests, incl. engine edit → fresh context sees it) + full suite green; app launches on Simulator. **9b done** (275334c): `Core/Models/LocalModels.swift` (`SavedPlace`, `Nickname` with unique `normalized`, `AppSettings` defaults verbatim §5) added to `SchemaV1` (still 1.0.0, nothing shipped); `Core/Models/NameNormalizer.swift` (§7.2 `normalize` only; kinship strip + matching = 1C.7); `LocalDataRepository` protocol (method set not in docs, TODO) + `Live/LiveLocalDataRepository.swift` (nickname upsert by key, exact → normalized lookup, one settings row created on demand, `wipeMemory` = "Xóa dữ liệu ghi nhớ", `wipeAll`) + `Mock/MockLocalDataRepository.swift`; `AppEnvironment.localData`. Verified: `EasyPhoneTests/LocalDataRepositoryTests.swift` (8 normalizer cases incl. "Mính", "đức", full width; 5 SwiftData + 1 mock test) + full suite green; Simulator with the old v1 store (only `ZTASKDRAFT`) → app launches, store gains `ZNICKNAME`, `ZSAVEDPLACE`, `ZAPPSETTINGS`
- [x] 1A.10 Design tokens + shared components (`PrimaryButton`, `FieldRow`, `StateBadge`, `Banner`, `Toast`, `ConfirmSheet`…) + contrast test — Docs: UI_SCREENS §1–2, §11 — split into 10a / 10b: **10a done** (ff174f2): 15 color assets = D-291 "Khoai" palette (new `secondaryFill`, `honey`, `onHoney`, `success`, `warning`, `warningBg`, `danger`, `border`; `AccentColor` = `primary`), `Tokens.swift` complete (rounded `display`/`title`/`button`, `fieldValue`, sizes), `PrimaryButton` (+ `role: .destructive`, `disabledReasonKey`), new `SecondaryButton` (Increase Contrast → surface + 2pt border), `TextLinkButton`; keys `confirm.delete`, `review.disabled.missing`, `home.camera`; UI_SCREENS §1.1 notes `onHoney` asset. Verified: `EasyPhoneTests/TokenContrastTests.swift` reads the asset catalog in light + dark: 21 pairs × 2 ≥ 4.5 (42 cases) + D-291 spot values + honey-as-text fails; full suite green; S01 screenshots light/dark on Simulator. **10b done** (2fe4fbd): `StateBadge` (§8 icon + `state.<raw>`, args, success/danger/textSecondary, one VoiceOver element), `FieldRow` (label/value/chevron, "Chưa có", needsReview warningBg + "Kiểm tra lại" + warning chevron, OCR "Xem ảnh gốc", ambiguity question + 56pt `SecondaryButton` "Chọn", HStack → VStack at AX sizes, 2pt border on Increase Contrast, VoiceOver per §9), `StepIndicator`, `EmptyState` (pawprint on 88pt honey circle); `TaskState.labelKey` / `symbolName` (`Core/Models/TaskStateDisplay.swift`), `UserMessage.text` (fills `%@`); keys: 11 `state.*`, 34 `field.*` (§10.2), `history.empty`, plus `stepIndicator.label`, `a11y.state`, `a11y.field.needsReview`, `a11y.field.hint` (names not in docs, DOC-23). Verified: `EasyPhoneTests/ComponentStringsTests.swift` (3 tests: §8 table, format args, every catalog field has a label) + full suite green; components rendered with `ImageRenderer` light/dark and checked by eye (throwaway test, not committed). **10c done** (2c623fb): `Banner` (UserMessage, danger/warning bar + icon, optional 56pt `SecondaryButton`), `Toast` + `.toast($model)` (4 s / 8 s with VoiceOver, `AccessibilityNotification.Announcement`, optional "Hoàn tác", Reduce Motion → fade), `ConfirmSheet` (medium/large, title/body/note, destructive primary + secondary pinned), `ListeningMic` (120 → 140, `stop.fill`, pulsing honey ring + light 2pt `primary` outline, Reduce Motion → static, `home.mic.a11y` + value, `.startsMediaSession`); keys `error.network.offline`, `error.approval.mismatch`, `confirm.clearHistory.*`, `home.mic.a11y`, `home.mic.listening.a11y` (DOC-24). Verified: `ComponentStringsTests` + 1 test (keys), full suite green; light/dark render checked by eye (ImageRenderer does not draw `ScrollView` content, so ConfirmSheet text is checked in previews only). DOC-23 keys recorded in UI_SCREENS (4a3b2d5). String-literal scan test stays with 1G.9
- [x] 1A.11 S04 Review (fields, buttons, disabled reasons, result card per D-250) with mock draft — Docs: UI_SCREENS S04, spec §5.3 — split into 11a / 11b: **11a done** (20e8cff): `Core/UI/FieldFormatter.swift` (dateTime → `common.dateTimeFormat` in the draft time zone with vi weekday, options `option.<field>.<value>` incl. alert P-35 + snooze hour, bool → `common.yes/no` (DOC-25), 🔒 refs never shown), `TaskEngine.confirmBlocker` (ambiguity → missing → previous linked step not final/handedOff/prepared → not awaitingApproval; `confirm()` uses it, so the DATA_MODEL §3.3 confirm rule is now enforced — the 1C.14 `.linked` value updates are still open), `Features/Review/{ReviewViewModel,ReviewView}.swift` (title `step.<kind>.<op>`, StepIndicator, StateBadge, banner `approval.mismatch` / `review.editedAfterApproval`, FieldRows in catalog order hiding conditional-only rows, original input, bottom bar Xác nhận (destructive "Xác nhận xóa" + hint for delete) / Sửa (P-37 field choice) / Hủy (cancel + pop), disabled reason text, 3 previews with "Dữ liệu mẫu"); 45 keys (`step.*`, `option.*`, `review.*`). Verified: `EasyPhoneTests/ReviewTests.swift` (3 formatter + 9 Review tests) + full suite green; S04 rendered in a hosted window (light reminder, dark ambiguous SMS) and checked by eye → added a divider above the pinned bar. **11b done** (f326ae7): result card replaces the bar (D-250): processing (spinner, no buttons), succeeded (`result.<kind>.<op>` or "Xong rồi!" on the last step; Primary "Tiếp tục: {step}" / "Xong" → Home), handedOff/prepared (markDone + Để sau), unknown (markDone + Thử lại for calendar/reminder, else Để sau), failed (`result.failed` + `error.<code>` → `error.generic` fallback; Thử lại + Hủy), userMarkedDone/cancelled; haptics success/warning, VoiceOver focus back to the title; `TaskEngine` in `AppEnvironment` (nonisolated init, `StepExecutor: Sendable`), `RootView` routes `.review(id)`; 21 keys (`result.*`, `error.generic`, `error.eventkit.saveFailed`). Verified: 6 more `ReviewViewModelTests` (result card per state, next step, markDone, retry, done) + full suite green. Open: "Mở trong Lịch/Lời nhắc" + permission fallback buttons (1C)
- [x] 1A.12 S05 Field editor per `FieldType` — Docs: UI_SCREENS S05 (ce0c5dc) — `Features/FieldEditor/{FieldEditorViewModel,FieldEditorView}.swift`: title = field label; text/address (multi-line field + "Xóa nội dung"), phone (phone pad, saved as E.164 via new `Validator.normalizePhone` §7.3), longText (TextEditor ≥ 160pt), dateTime (chips Hôm nay / Ngày mai keep the time + graphical date + wheel time, encoded ISO with the draft's offset; empty → next full hour, TODO), date (graphical, `YYYY-MM-DD`), alert choices P-35 (keeps a non-listed AI value), bool toggle 56pt, enumChoice radio rows 64pt + checkmark; inline `editor.invalid.*` in `danger` + icon via new `Validator.check(fieldId:value:in:now:)` (encoding of any non-empty value + endBeforeStart / past); "Lưu" disabled while invalid, "Hủy". S04: row tap / "Sửa" open the sheet (picker types `contactRef`/`placeRef`/`coordinate` excluded until 1C), "Lưu" → `TaskEngine.edit`. 6 `editor.*` keys. Verified: `EasyPhoneTests/FieldEditorTests.swift` (10 tests incl. S04 → S05 → engine → `awaitingApproval`) + full suite green; date-time (light) and alert list (dark) rendered and checked by eye. Not done here: "Đọc to" (TTS 1B.3), "Tìm trên bản đồ" (S13 1C.13); snooze hour from settings (1C.17)
- [x] 1A.13 S14 History (4 groups, reopen at `currentStep`, hide) — Docs: UI_SCREENS S14, DATA_MODEL §8 (f5575b2) — `Features/History/{HistoryViewModel,HistoryView}.swift`: sections in fixed order (empty ones hidden), rows ≥ 72pt newest first: kind icon (SF Symbols, TODO) + `history.summary` "{stepTitle}: {mainValue}" of `currentStep` (mainValue field per kind, TODO) + "Hôm nay / Hôm qua {HH:mm}" else `common.dateTimeFormat` (TODO) + `StateBadge` of the group step + "{done}/{total} bước"; tap → `router.push(.review(id))` (Review opens at `currentStep`, AC2); swipe / VoiceOver action "Ẩn" → `isArchived`; empty → `EmptyState` "Chưa có việc nào."; route `.history` in `RootView` (entry point = Home toolbar, 1B.1). Fix found by screenshot: `state.handedOff` showed "%@" → `StateBadge(step:)` / `labelArgs` fill `{app}` (call → `app.phone` "Điện thoại", DOC-26; directions → `mapsApp` label; SMS copy → `channel` label), used on S04 and S14. 10 keys. Verified: `EasyPhoneTests/HistoryTests.swift` (5 tests) + full suite green; S14 rendered and checked by eye
- [x] 1A.14 S15 Settings shell (sections, no live data yet) — Docs: UI_SCREENS S15 (this commit) — `Features/Settings/{SettingsViewModel,SettingsView}.swift`: insetGrouped list on `surface` rows, sections in S15 order; Tài khoản (plan from `AppState.entitlement`), Giọng nói (toggle + rate slider Chậm/Nhanh), Hiển thị (text-size note, simple mode, "Hiện bạn Khoai"), Ghi nhớ (nicknames + swipe Xóa / empty text), ★ Nâng cao (snooze hour 5–11, maps app; hidden in simple mode, P-40), Kết nối (Gmail — sắp có, disabled), Dữ liệu (Xóa lịch sử → closed drafts only D-244, Xóa dữ liệu ghi nhớ) and Đăng xuất (drafts kept) via `ConfirmSheet` (S20), Thông tin (AI disclosure D-187, legal links no-op, version); settings autosave; route `.settings`. `AppSettings.petEnabled = true` added (D-289 vs DATA_MODEL §5, DOC-27); 40 keys. Verified: `EasyPhoneTests/SettingsTests.swift` (6 tests) + full suite green; S15 rendered light/dark (fixed: rows were system white → `surface`); Simulator with the old store launches and gains `ZPETENABLED`. Left for later items: quota/upgrade (1F), voice test (1B.3), permissions (1C.1), saved places (1C.13), nickname contact names (1C.7), delete account + legal text (1G)
- [x] **EXIT 1A** `EasyPhoneTests` green for state machine, hash, validator — 2026-11-10: `TaskStateMachineTests`, `ApprovalHashTests`, `ValidatorTests` green (and the full suite); backend 113/113

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
- [ ] 1B.16 `MascotView` (Khoai) + placement on S02 / S03 + `settings.pet` toggle; needs the owner's art (else SF Symbol placeholder) — Docs: UI_SCREENS §2, §12 P-41, D-289
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
- [ ] 1E.2 App Shortcuts phrases vi (18.4+) + en fallback (`#available`); "Ê Khoai" / "Khoai" via `INAlternativeAppNames` (D-288), test on the owner's iPhone — Docs: D-012, D-288, UI_SCREENS §7
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
- [ ] 1G.8 Accessibility pass (incl. mascot, P-41): AX5, VoiceOver, Increase Contrast, Reduce Motion, Dark on S02/S03/S04/S06/S08/S16 — Docs: UI_SCREENS §9
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

### 2026-11-10 — Phase 1A — 1A.14 S15 Settings + EXIT 1A
- Done: DOC-26 recorded (ad3f244); 1A.14 (Settings shell, S20 confirms for history/memory/sign-out, 6 tests); **EXIT 1A ✅** — Phase 1B starts
- Fixed by screenshot: Settings rows used system white instead of `surface`
- DOC-27 opened (`petEnabled`, `settings.snoozeHour.value`)
- Next: 1B.1 S02 Home

### 2026-11-10 — Phase 1A — 1A.13 S14 History
- Done: 1A.13 (History screen + route, `StateBadge(step:)` args fix, 5 tests); suite green; S14 checked by screenshot
- Bug found by screenshot: handedOff badge showed literal "%@" (S04 + S14) → fixed; DOC-26 opened (`app.phone`)
- Note: one `test` run reported "no member 'badgeArgs'" right after the edit — stale test build again; `build` then `test` passed
- Next: 1A.14 S15 Settings shell

### 2026-11-10 — Phase 1A — 1A.12 S05 editor
- Done: 1A.12 (S05 editor, `normalizePhone`, `Validator.check`, 10 tests); suite green; no new crash reports
- Owner asked why the app still shows only the user id: S02 Home is 1B.1; owner chose to keep the phase order (no debug menu). Screens are visible in Xcode Previews meanwhile
- Found: the Simulator had been left in Dark appearance by the S01 screenshot step → reset to light (`xcrun simctl ui booted appearance light`). iOS 27 graphical DatePicker draws the selected day monochrome (ignores `tint`)
- Owner decision open (no DOC row): time wheel sits below the calendar (needs a scroll) — order follows UI_SCREENS S05
- Next: 1A.13 S14 History

### 2026-11-10 — Phase 1A — 1A.11b result card
- Done: DOC-25 recorded (52a03d9); 1A.11 complete (result card, routing, next step, 6 tests); suite green
- Bug in a test (not app code): `[kind: exec, .reminder: exec]` with `kind == .reminder` = duplicate keys in a dictionary literal → runtime trap; the test host crashed 12× over two runs (owner saw repeated "EasyPhoneAI quit unexpectedly" dialogs). Fixed in the test; crash reports in `~/Library/Logs/DiagnosticReports/EasyPhoneAI-*.ips` pointed at `Dictionary.init(dictionaryLiteral:)`
- Next: 1A.12 S05 editor

### 2026-11-10 — Phase 1A — 1A.11a Review layout
- Done: DOC-24 recorded (d13380f); 1A.11a (`FieldFormatter`, `confirmBlocker` with linked-step rule, `ReviewViewModel`/`ReviewView`, 45 keys, 12 tests); suite green
- How to screenshot a SwiftUI screen with `ScrollView`/`NavigationStack` from a test: `UIWindow(windowScene:)` of the host app + `drawHierarchy` (ImageRenderer draws nothing inside ScrollView; a window without a scene renders blank)
- TODOs added: see §5.3 (FieldFormatter bool, Review 🔒 rows / S05 / S06 / S10 / conflict card / composer); DOC-25 opened
- Next: 1A.11b

### 2026-11-10 — Phase 1A — 1A.10c notice components
- Done: 1A.10 complete (10c: `Banner`, `Toast`, `ConfirmSheet`, `ListeningMic`, 6 keys, 1 test); DOC-23 keys recorded in UI_SCREENS (owner OK)
- TODOs added: `Banner.swift:14`, `ListeningMic.swift:43`; DOC-24 opened
- Next: 1A.11 S04 Review

### 2026-11-10 — Phase 1A — 1A.10b display components
- Done: 1A.10b (`StateBadge`, `FieldRow`, `StepIndicator`, `EmptyState`, 49 keys, 3 tests); suite green; light/dark render checked
- Fix found by render: chevron on `warningBg` used `textSecondary` (forbidden) → `warning`
- TODOs added: `StateBadge.swift:29`, `FieldRow.swift:27`, `StepIndicator.swift:11`; DOC-23 opened
- Next: 1A.10c

### 2026-11-10 — Phase 1A — 1A.10a tokens + buttons
- Done: 1A.10a (D-291 assets, `Tokens`, Primary/Secondary/TextLink buttons, `TokenContrastTests` 42 pairs); suite green; S01 light/dark look right
- In progress: 1A.10 — left: 10b components
- Note: `colorSchemeContrast` is read-only → Increase Contrast previews via the canvas variants only
- Next: 1A.10b

### 2026-11-10 — Off-checklist — D-291 Khoai visual style
- Owner reviewed a Figma Make mock-up (prompt from Claude) → approved P-42: Khoai palette, `honey` token, SF Pro Rounded (D-291)
- Docs: DECISIONS §12.8 + §14, UI_SCREENS §1.1 table (measured contrast), §1.2, §2 `ListeningMic` / `EmptyState`
- Review notes for 1A.10: DemoDataBadge must be ≥ `label` (not 13 pt); buttons in Banner/FieldRow stay 56 pt; review rows keep the chevron; mic label changes while listening; light mic ring gets a `primary` outline
- Next: 1A.10

### 2026-11-10 — Phase 1A — 1A.9b local data
- Done: 1A.9 complete (9b: `SavedPlace`/`Nickname`/`AppSettings`, `NameNormalizer`, `LocalDataRepository` Live + Mock, 14 tests); suite green; old store migrates on Simulator
- TODOs added: `LocalDataRepository.swift:4` TODO(spec)
- Next: 1A.10 tokens + components

### 2026-11-10 — Phase 1A — 1A.9a task repository
- Done: 1A.9a (draft status D-244, `LiveTaskRepository`, `AppEnvironment.drafts`, 11 tests); iOS suite green; app launches
- In progress: 1A.9 — left: 9b `LocalDataRepository` + `SavedPlace`/`Nickname`/`AppSettings`
- TODOs added: `HistoryGroup.swift:35`, `LiveTaskRepository.swift:60`; removed `TaskRepository.swift` TODO
- Next: 1A.9b

### 2026-11-10 — Phase 1A — 1A.8b confirm + executors
- Done: 1A.8 complete (8b: `StepExecutor`, `confirm`, `composerFinished`, 11 tests); iOS suite green
- TODOs added: `TaskEngine.swift:33`, `:48`, `:65`, `:82` TODO(spec)
- Next: 1A.9 repositories

### 2026-11-10 — Phase 1A — D-290 edit after success
- Decisions answered: DOC-22 → D-290 (owner "ok"); DATA_MODEL §1.5 row note, DECISIONS §12.8 + §14
- Done: `TaskEngine.turnIntoUpdate` + 2 tests (replaces the TaskEngine TODO); iOS suite green
- Next: 1A.8b

### 2026-11-10 — Phase 1A — 1A.8a TaskEngine core
- Done: 1A.8a (engine core, `TaskRepository` protocol + mock, 14 tests); iOS suite green
- In progress: 1A.8 — left: 8b `confirm()` + executors, `TaskEngine.swift`
- TODOs added: `TaskRepository.swift:5`, `TaskEngine.swift:59`, `TaskEngine.swift:77` TODO(spec); DOC-22 opened
- Next: 1A.8b

### 2026-11-10 — Phase 1A — 1A.7 validator
- Done: 1A.7 `Validator` + 17 tests; iOS suite green
- TODOs added: `Validator.swift:87`, `Validator.swift:191` TODO(spec)
- Next: 1A.8 `TaskEngine`

### 2026-11-10 — Phase 1A — 1A.6 approval hash
- Done: 1A.6 `ApprovalHash` + 9 tests; iOS suite green
- Note: first `test` run after adding the file failed with "cannot find 'ApprovalHash'" (stale test-module build again); rerun green
- TODOs added: `ApprovalHash.swift:10` TODO(spec) (no escaping in canonical form)
- Next: 1A.7 validator

### 2026-11-09 — Phase 1A — 1A.5 transition tests
- Done: 1A.5 exhaustive table test (286 cases) + closed-state test; iOS suite green (2 consecutive runs)
- Note: one earlier run reported `TEST FAILED` with no failing test listed — most likely the known stale test-module compile issue (filter hid `error:`); `build` then `test` is reliable
- TODOs added: none
- Next: 1A.6 approval hash

### 2026-11-09 — Off-checklist — App icon (owner art)
- Done: owner's Figma icon (`Khoai — Light` / `Khoai — Dark`, file `WervKLr0NeNuDOvCYkrRqt`) → `AppIcon.appiconset` (1024 single size, light + dark, tinted empty → iOS generates, owner's choice), alpha removed; `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in `Base.xcconfig`
- S01: `appLogo` image set (288 px, light + dark) replaces the SF Symbol placeholder (owner OK); TODO `SignInView.swift:15` closed
- Verify: build, `CFBundleIcons` in built Info.plist, `Assets.car` has AppIcon any + dark; S01 screenshots light/dark on Simulator; full iOS test green. Home-screen icon on the owner's iPhone after next reinstall
- Note: icon art is not usable as mascot art (1B.16 needs 6 transparent poses)
- Next: 1A.5 exhaustive transition tests

### 2026-11-09 — Phase 1A — 1A.4 state machine
- Done: 1A.4 `TaskStateMachine.transition` + 4 smoke tests; iOS suite green
- TODOs added: none
- Next: 1A.5 exhaustive transition tests

### 2026-11-09 — Phase 1A — 1A.3 field catalog
- Done: 1A.3 `FieldCatalog.swift` + `field_catalog.json` + 7 Swift / 4 pytest tests; iOS green, backend 113/113; negative check done
- TODOs added: `FieldCatalog.swift:6` JSON layout, `:140` channel options
- Note: Swift reads the backend JSON by `#filePath` (no project-file change); test only runs on Simulator
- Next: 1A.4 `transition` pure function

### 2026-11-09 — Phase 1A — 1A.2 task models
- Done: 1A.2 `Field`/`Ambiguity`/`Candidate`/`TaskStep`/`StateChange`/`TaskDraft`/`InputMode` + 6 tests; iOS suite green, backend 109/109
- TODOs added: `Field.swift:40` TODO(spec) `labelKey(kind:)`
- Note: again "cannot find type" in the test target after adding app files; a plain `build` then `test` fixed it (stale module)
- Next: 1A.3 field catalog (Swift + JSON + equality test)

### 2026-11-09 — Phase 1A — 1A.1 task enums
- Done: 1A.1 `TaskEnums.swift` + `FieldSource.swift` + 7 tests, full iOS suite green; backend 109/109 (health check)
- Decisions (owner OK'd plan): unknown raw values fail decoding; `TaskKind.allowedOperations` added now (used by 1A.7)
- TODOs added: `FieldSource.swift:67` TODO(spec) `NormalizedRect` fields
- Note: first `xcodebuild test` after adding files reported "cannot find type" in the test target; plain rerun passed (stale incremental build)
- Next: 1A.2 models per DATA_MODEL §2–3

### 2026-11-09 — Branding: EasyPhoneK + mascot Khoai
- Process: owner asked for a Codex-like guide pet and a rename; "làm tiếp /plan" → plan (Vietnamese), approved ("Khoai" alone also a call phrase)
- Done: display name + visible strings → EasyPhoneK, Siri "Ê Khoai" / "Khoai" spec (D-287, D-288, eed43a4); P-41 mascot spec → D-289, new item 1B.16
- Verify: iOS `test` green; built Info.plist `CFBundleDisplayName = EasyPhoneK`. Owner's iPhone keeps the old name until reinstalled
- Bugs: none. TODOs: none. Waiting on: mascot art from the owner (needed by 1B.16)
- Next: 1A.1 enums

### 2026-11-09 — Phase 0 — EXIT 0 on the owner's iPhone
- Process: "làm tiếp /plan" → plan (Vietnamese), approved; owner added Apple ID in Xcode, paired iPhone, Developer Mode
- Done: EXIT 0 — device build + install from CLI, Google sign-in on iPhone → `userId`, backend `/v1/me 200` → Phase 0 complete
- Code: `Secrets.example.xcconfig` documents `DEVELOPMENT_TEAM`; CLAUDE.md §8 device build/install commands
- Note: a leftover uvicorn from the previous session held :8000 → stopped and restarted; tunnel URL changed again
- Bugs: none. TODOs: none
- Next: 1A.1 enums

### 2026-11-09 — Phase 0 — Tunnel (0.19)
- Process: "làm tiếp /plan" → plan (Vietnamese), owner "duyệt" (Cloudflare quick tunnel)
- Done: 0.19 (eda3fdb) — Mac + Simulator through the tunnel; owner confirmed iPhone Safari `/v1/health` → `[x]`
- Note: background uvicorn/tunnel were stopped at the 30 min limit and restarted (new URL) → restart = new URL
- Bugs: none. TODOs: none. Note: quick tunnel URL changes per run → edit `Secrets.xcconfig` + rebuild
- Next: EXIT 0 on the owner's iPhone

### 2026-11-09 — Phase 0 — Contract fixtures (0.18)
- Process: "làm tiếp /plan" → plan (Vietnamese), owner "duyệt và chọn A" (mocks in code + equality test)
- Done: 0.18 fixtures + `schemas/error.py` + pytest/Swift fixture tests; folder ref in `project.xcproj` (ccff97e)
- Verify: pytest 109/109, iOS test green; one-byte break fails both sides → `[x]`
- Bugs: none. TODOs: removed MockAPIClient.swift:4; added none. Note: no `error.<code>` keys in Localizable yet (1G.9)
- Next: 0.19 tunnel

### 2026-11-09 — Phase 0 — S19 Update required (0.17)
- Process: "làm tiếp /plan" → plan (Vietnamese), owner "ok" = keep CTA as no-op
- Done: 0.17 S19 view + ViewModel + strings + RootView full-screen cover (a4d63b2); hashes for 0.9 – 0.16 filled in
- Verify: build + 74 tests green; Simulator via scratch 426 stub (backend has no version check yet) → S19, AX5 OK → `[x]`
- Bugs: none. Opened DOC-21 (App Store CTA). TODOs added: 2 (see §5.3)
- Next: 0.18 contract fixtures

### 2026-11-09 — Phase 0 — `APIClient` (0.16)
- Process: "làm tiếp /plan" → plan mode (Vietnamese), approved, then built
- Done: 0.16 `APIClient` actor + `RetryPolicy` + DTOs + `AppError` + `MockAPIClient`; RootView loads `/v1/me` (459aa23)
- Verify: iOS build (no warnings) + tests green; Simulator → local backend `GET /v1/me 200` → `[x]`
- Bugs: none. Opened DOC-20 (`blockingUpdates`). TODOs added: 6 (see §5.3)
- Next: 0.17 S19 Update required

### 2026-11-09 — Phase 0 — `GET /v1/me` + profile upsert (0.15)
- Done: code + tests for 0.15 (ea9f3cc); asyncpg added; `db` test suite on Docker Postgres, wired into CI
- Verified on real Supabase with the owner's token: 200 + profile row created once → 0.15 `[x]`
- Bugs: none. TODOs added: none
- Decisions answered: owner — `locale` set only when the profile is created (D-236)
- Next: 0.16 `APIClient` actor

### 2026-11-09 — Infra — Backend CI
- Done: pushed `demo_git`; `.github/workflows/backend.yml` (ubuntu, uv, `pytest -q`, `migrations/checks/run_local.sh`), owner OK'd
- iOS CI deferred (macOS runners: 10× minutes, Xcode/simulator version mismatch, no `Secrets.xcconfig`); revisit at 1C XCUITest
- Next: 0.15 `/v1/me` + profile upsert (owner creates `backend/.env` first)

### 2026-11-09 — Phase 0 — SQL migration
- Process: "làm tiếp /plan" → plan mode with full SQL for owner review, approved
- Done: 0.14 — `backend/migrations/0001_init.sql` + Docker check (`sh backend/migrations/checks/run_local.sh`); owner applied it in Supabase
- Verify: local checks pass (RLS own-rows, anon 0 rows, client writes refused, service role writes, unique key, checks, cascade); pytest 35/35
- Supabase before run: REST → `PGRST205` (tables absent). Bugs: none. TODOs: none
- Later: owner ran SQL → REST anon `200 []` ×3, `gmail_accounts` absent, anon insert `42501` → 0.14 `[x]`
- Next: 0.15 `/v1/me` + profile upsert (needs `backend/.env`)

### 2026-11-09 — Phase 0 — JWT verification
- Process: "làm tiếp /plan" → plan mode, approved (incl. moving profile upsert to 0.15)
- Done: 0.13 `app/auth.py` + `deps.current_user`: JWKS (ES256/RS256) primary, HS256 fallback; `require exp/sub/aud`, `sub` UUID lowercased
- Verify: `uv run pytest -q` 35/35 (21 new auth tests, fake JWKS); real project JWKS loads (ES256). Bugs: none. TODOs: none
- Next: 0.14 SQL migration (show SQL to owner first)

### 2026-11-09 — Phase 0 — Health endpoint
- Process: "làm tiếp /plan" → plan mode (Vietnamese plan), approved, then built
- Done: 0.12 `GET /v1/health` (`routers/health.py`, `schemas/health.py`, `ROUTERS` in `main.py`, `tests/test_health.py`)
- Verify: `uv run pytest -q` 14/14; uvicorn + curl → 200 body per API_CONTRACT §6.1. Bugs: none. TODOs added: none
- Next: 0.13 JWT verification + profile upsert

### 2026-11-09 — Phase 0 — Backend skeleton
- Process: "làm tiếp /plan" → plan mode, plan approved; owner asked plans in Vietnamese from now on
- Done: 0.11 FastAPI skeleton (config, request id, `AppError` + envelope handlers) with `uv` + Python 3.12
- Verify: `uv run pytest -q` 11/11; uvicorn + curl unknown route → 404 envelope + `X-Request-Id`. Bugs: none
- Also: CLAUDE.md §8 / PROGRESS §0.4 backend commands now `uv run …`; `.gitignore` keeps `.env.example`
- TODOs added: backend/app/errors.py:118 TODO(spec)
- Next: 0.12 `GET /v1/health`

### 2026-11-09 — Phase 0 — S01 Sign-in
- Process: "làm tiếp /plan" → EnterPlanMode, plan approved, then built
- In progress: 0.10 — built S01 + `SignInViewModel` + `UserMessage`; RootView switches on session; left: real Google sign-in by owner
- Also: slice of 1A.10 pulled forward (6 color tokens, `Tokens.swift`, `PrimaryButton`, `DemoDataBadge`); 1A.10 still `[ ]`
- Verify: build ok, 23/23 tests, S01 screenshot on iPhone 18 Pro Simulator. Bugs: none
- TODOs added: RootView.swift:33, SignInViewModel.swift:26, SignInView.swift:15/67/79
- Note: first `test` run after adding files can fail (tests target lacks explicit app dependency); re-run passes
- Later: owner signed in for real on Simulator → user id shown, relaunch stays signed in → 0.10 `[x]`
- Next: 0.11 backend skeleton

### 2026-11-09 — Phase 0 — AuthService
- Process: "làm tiếp /plan" → EnterPlanMode, plan approved by owner, then built
- Done: 0.9 AuthService protocol + Live (Supabase `Auth` 2.55.6) + Mock, wired into `AppEnvironment` / RootView
- Owner step: added the SPM package in Xcode (agent could not hand-edit package keys safely)
- Verify: build ok, 19/19 tests, app launches on simulator. Bugs: none. TODOs added: none
- Next: 0.10 S01 sign-in screen, then real Google sign-in on Simulator
- Later: Xcode re-formatted `InfoPlist.xcstrings` + auto-extracted `CFBundleDisplayName`/`CFBundleName` (8 S18 keys intact) → committed; `demo_git` pushed to GitHub. ⌘R still shows only a `ProgressView` until 0.10

### 2026-11-09 — Phase 0 — 0.7 config files
- Done: owner kept 0.6 (`9d9da26`); `/plan` slash command unavailable in the mobile app — put "/plan" at the end of a message instead
- Done: 0.7 verified (Debug/Release build, Info.plist values, simulator launch). Xcode "Add Files" copied `Config/` into the synchronized folder → removed; agent added the folder ref + `INFOPLIST_FILE` in `project.xcproj`, owner picked the xcconfigs (`specialized-configurations` key)
- TODOs added: `Config/Release.xcconfig:2` TODO(decision) D-036
- Decisions: Release = Debug URL for now; anon key in git-ignored `Secrets.xcconfig` (owner OK'd plan)
- Next: `EasyPhoneTests` target, then 0.8
- Later same day: agent added `EasyPhoneTests` target (`bundle.unit-test`, `test-host-target`) in `project.xcproj` + shared scheme `xcshareddata/xcschemes/EasyPhoneAI.xcscheme` (autogenerated scheme had no test action); 12 tests green. `/plan` = real plan mode via EnterPlanMode tool
- 0.8 done with owner on dashboards (Supabase Singapore, Google OAuth Web client, Testing mode); publishable key instead of legacy anon. Next: 0.9 AuthService

### Summary of older sessions (compressed, §0.2 rule 8)
- 2026-11-09 Phase 0: 0.3 folder layout (4653af9, D-286 `.gitkeep` breaks synchronized folder), 0.4 string catalogs (b19e21f), 0.5 app state + router (b74d9de), 0.6 SwiftData `SchemaV1` (9d9da26, built before owner approval → rule: "/plan" anywhere = plan mode and stop)
- 2026-11-08 Phase 0: 0.1 repo (716adcd) + 0.2 project settings (9022272); opened/closed DOC-19
- 2026-11-08 Docs: 7 planning docs + this file; CLAUDE.md; DOC-1 – DOC-18 fixed via D-243 – D-281; P-17 – P-40 → D-252 – D-275; thesis scope D-282 – D-285
