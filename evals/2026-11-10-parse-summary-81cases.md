# Live parse eval — summary — 2026-11-10

> Input for D-052 (model choice). Per-model details in the files next to this one.

| Model | Passed | p50 ms | p90 ms | Errors | Cost / request | Cost / 1000 requests |
|---|---|---|---|---|---|---|
| `gpt-6-luna` | 76/81 | 3108 | 4769 | 0 | $0.00044 | $0.44 |

## Notes (written by hand after the run)

- 81 cases = the 31 golden cases + 50 extra `x_*` cases (1B.15b, owner request). Same prompt `parse.v1`, D-052 model.
  The scorer now also checks `unsupported.reason` (all 6 + 8 out-of-scope cases passed it).
- Failures (5):
  - `E7` — delete hint: no `startDate` for "thứ Sáu" (same as the 31-case run; device still searches by title).
  - `date_numeric_past` — past numeric date got confidence > 0.6 (passed in the first run → model is not fully
    deterministic; the app still shows the date for review).
  - `x_place_google` — "Mở Google Maps …": `mapsApp` not set (Apple Maps default would open instead).
  - `x_rem_bare_hour_tomorrow` — "7 giờ" said at 18:07: no `dueDate` (asks instead of guessing tomorrow 07:00 — safe).
  - `x_rem_snooze` — "hoãn … thêm 15 phút": no `snoozeOption` `min15`.
- None of the failures acts without the user: each leaves a field empty or low-confidence for Review / a follow-up.
