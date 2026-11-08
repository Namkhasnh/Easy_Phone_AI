---
name: debug
description: Find the root cause of a bug, build error or failing test in EasyPhone AI and fix it minimally without breaking doc rules. Use when the owner says "lỗi", "fix", "debug", "không chạy", "build fail", "test fail", or pastes an error.
---

# Debug and fix (sửa lỗi)

## 1. Reproduce
- Get the exact error: run the failing command yourself (`xcodebuild … build/test`, `pytest -q path::test`), or use the
  log/screenshot the owner gave. If it only happens on a real iPhone, ask for the exact steps and the Xcode console output.
- Check `docs/PROGRESS.md` §5.1 — the bug may already be known (`BUG-xxx`).

## 2. Find the root cause
- Read the error from the **first** real error line (Swift builds cascade). Open that `file:line`.
- Form 1–3 hypotheses, check each by reading code or adding a quick check. Do not guess-and-patch.
- Ask: is the code wrong, or is the code right and the docs say something else? Compare with the doc section that
  owns it (state transitions → DATA_MODEL §1.5, errors → API_CONTRACT §3 / ARCHITECTURE §9, UI → UI_SCREENS).
- Common causes here: Swift 6 concurrency (`Sendable`, `@MainActor` isolation), SwiftData model changes without a
  schema version, Xcode project/target membership, missing `Localizable.xcstrings` keys, Pydantic `extra="forbid"`.

## 3. Fix minimally
- Change only what the root cause needs. No refactors, renames or "while I'm here" edits.
- The fix must still obey `CLAUDE.md` §5 rules. Never "fix" by weakening a rule (e.g. `@unchecked Sendable` without a
  comment, auto-picking a contact, marking a hand-off `succeeded`, skipping a test).
- If the docs themselves are wrong or contradict each other: do not change behavior silently — add a `DOC-x` row in
  PROGRESS §5.2 and ask the owner.

## 4. Prove it
- Re-run the failing command → green. Add a regression test when the bug is in logic (engine, validator, quota, parsing).
- Run the wider suite once to make sure nothing else broke.

## 5. Record
Use `save-progress`: add/close the `BUG-xxx` row in PROGRESS §5.1 / §5.4 with the fixing commit.
Reply in Vietnamese: **Nguyên nhân** (1–2 câu), **Đã sửa** (files), **Kiểm tra** (command + result).
