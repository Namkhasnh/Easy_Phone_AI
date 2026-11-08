---
name: save-progress
description: Save what was done this session into docs/PROGRESS.md and commit, so the next AI session remembers. Use at the end of build-step / debug, or when the owner says "lưu tiến độ", "ghi lại", "kết thúc phiên", "nhớ những gì đã làm".
---

# Save progress (ghi nhớ cho phiên sau)

`docs/PROGRESS.md` is the project's memory. A new session knows only what is written there and in git.

## Steps (PROGRESS §0.2)
1. `git status` + `git diff --stat` to see what actually changed this session.
2. Update `docs/PROGRESS.md`:
   - §6 items: `[x]` **only** if its `Verify:` passed (add commit short hash after committing); else `[~]` with
     `left: <what>, <file>, <function>`. Blocked → `[!]` + blocker id.
   - §5.1 bugs: add new `BUG-xxx`; move fixed ones to §5.4 with the commit.
   - §5.2: any doc gap/conflict found → `DOC-x` row. §5.3: every `TODO(spec)` / `TODO(decision)` added (`file:line`).
   - §1 Snapshot: date, phase, working on, last commit, build/test status, **exactly one concrete next action**.
   - §8 Session log: new entry on top using the template, max 8 lines.
3. If the session touched `CLAUDE.md` §8 commands or found they are wrong, fix them in the same commit.
4. Commit code + PROGRESS together. Message: `[<phase>] <what> (D-xxx, P-xx)`. Never commit `.env`, `*.p8`,
   `Secrets.xcconfig`. Do not push unless the owner asks.
5. Commit hashes: a commit cannot contain its own hash. Tick the item as `[x] … (this commit)` and replace it with
   the real short hash at the start of the next `save-progress` run.

## Reply to the owner (Vietnamese, short)
- Đã xong / Đang dở (left: …) / Lỗi mới
- Bước tiếp theo: <one action>
- Gợi ý: phiên sau chỉ cần nói "làm tiếp" — `build-step` sẽ đọc PROGRESS.md để tiếp tục.
