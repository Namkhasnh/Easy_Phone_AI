---
name: build-step
description: Implement ONE small item from docs/PROGRESS.md exactly as the docs specify, verify it, and record progress. Use when the owner says "làm tiếp", "code mục tiếp theo", "làm mục 0.x / 1A.x", or asks to build a feature.
---

# Build one small step (code từng phần nhỏ, đúng docs)

Goal: one PROGRESS item per run, small diff, zero drift from `docs/`.

## 1. Pick the item
1. Read `docs/PROGRESS.md` §1 Snapshot, §3 Blockers, §5 Known issues.
2. Item = the one the owner named, else the **first `[ ]` item of the current phase**. Never start a later phase
   while the previous phase has unticked exit criteria (D-140). No Gmail before Phase 2, no ride/food before Phase 3.
3. If the item is large (more than ~3 new files or ~200 lines), split it into sub-steps, tell the owner the list,
   and do only the first sub-step.
4. Mark it `[~]` in PROGRESS and set "Working on" in §1.

## 2. Read only what is needed
- Read the docs listed in the item's `Docs:` column, plus `CLAUDE.md` §5 (product rules) and §6/§7 (conventions).
- Before writing code, tell the owner in 3–6 Vietnamese bullets: what you will create/change and which `D-xxx` /
  doc § each part follows. Then proceed.

## 3. Write code
- Use names, enums, field ids, keys and strings **verbatim** from the docs. Do not rename, add states, or invent UI.
- Something not specified → simplest option + `// TODO(spec): <what>`. Two docs disagree → follow the higher doc
  (DECISIONS → Spec → DATA_MODEL → API_CONTRACT → AI_PROMPTS → ARCHITECTURE → UI_SCREENS) + `// TODO(decision): <doc §> vs <doc §>`.
- An `OPEN` decision would make this hard to undo (DB schema, App Store product ids, hosting) → stop and ask.
- Reference decisions in comments where the rule is non-obvious: `// D-102: tel:// is never succeeded`.

## 4. Self-check before saying done
Run through this list against the diff and fix any hit:
- [ ] Views/ViewModels import no EventKit, Contacts, MessageUI, Speech, Vision, StoreKit, Supabase (D-015)
- [ ] New service = protocol + `Live…` + `Mock…`; new screen has `#Preview` with mocks (D-206)
- [ ] No string literal in `Text("…")`; keys from UI_SCREENS (D-003)
- [ ] Only `TaskEngine` writes `TaskStep.state` (D-123)
- [ ] No 🔒 field in any DTO / backend payload (D-056); no API key in the app (D-051)
- [ ] Backend: no hard-coded model / quota / price (D-038); no raw user content in logs (D-059)
- [ ] Shared sources changed together (task_draft.json ↔ Swift, field_catalog.json ↔ FieldCatalog.swift, API_CONTRACT ↔ Pydantic ↔ DTO ↔ fixtures)

## 5. Verify
- iOS: `xcodebuild -scheme EasyPhoneAI -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build` (and `test` if tests exist).
- Backend: `cd backend && pytest -q`. Never run `pytest -m live` unless the owner asks (costs money).
- Run the item's `Verify:` step. If it needs a real iPhone, give the owner a short numbered test script in Vietnamese
  and leave the item `[~]` until they confirm.

## 6. Finish
Use the `save-progress` skill (update PROGRESS.md + commit). Then reply in Vietnamese: what was done, how it was
verified, and the one next step.
