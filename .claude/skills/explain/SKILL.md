---
name: explain
description: Explain EasyPhone AI code in plain Vietnamese for the owner. Use when the owner asks "giải thích", "code này làm gì", "tại sao", or names a file/function/type to understand.
---

# Explain code (giải thích code)

The owner vibe-codes and may not read Swift/Python fluently. Explain so they understand **what it does and why**.

## Steps
1. Read the file(s) the owner named. If they named a concept ("state machine", "quota"), find the code with Grep first.
2. Find the doc rules behind it: search `docs/` for the `D-xxx` ids in code comments, or the matching section
   (state machine → DATA_MODEL §1.5, quota → API_CONTRACT §4, layers → ARCHITECTURE §2).
3. Answer **in Vietnamese**, in this order:
   - **Tóm tắt (1–2 câu):** what this code is for, in everyday words.
   - **Luồng chạy:** numbered steps of what happens, referencing `file:line`.
   - **Vì sao viết vậy:** the doc rule(s) it follows (`D-xxx`, doc §), in one line each.
   - **Liên quan:** which other files call it / it calls (max 5).
   - **Lưu ý:** anything that looks wrong, unfinished (`TODO(spec)`, `TODO(decision)`) or against the docs.
4. Use a tiny example with real values when it helps (e.g. "Nhắn anh Minh…" → what each step produces).

## Rules
- Do not change any code while explaining. If you spot a bug, say so and suggest using the `debug` skill.
- Keep technical terms in English (ViewModel, protocol, actor) but explain each the first time.
- Short: aim for one screen. Offer to go deeper on one part instead of explaining everything.
