# Live parse eval — summary — 2026-11-10

> Input for D-052 (model choice). Per-model details in the files next to this one.

| Model | Passed | p50 ms | p90 ms | Errors | Cost / request | Cost / 1000 requests |
|---|---|---|---|---|---|---|
| `gpt-6-luna` | 30/31 | 3165 | 5455 | 0 | $0.00044 | $0.44 |
| `gpt-4o-mini` | 9/31 | 3738 | 6870 | 0 | $0.00058 | $0.58 |
| `gpt-5-nano` | 1/31 | 12088 | 12132 | 30 | $0.00002 | $0.02 |

## Notes (written by hand after the run)

- Run: 31 golden cases × 3 models, sequential, production path (strict schema, 1 repair, 18 s budget, 12 s per call).
  Total ≈ $0.03 at list prices (timed-out `gpt-5-nano` calls report no usage, so real spend may be slightly higher).
- `gpt-6-luna`: only E7 fails (delete hint: no `startDate` for "thứ Sáu"; the device still searches by title).
- `gpt-4o-mini`: returns **2 steps** for most single-task requests (19 cases), incl. the §8.3 injection case;
  invents a time for "cuối tuần"; marks the lunar date unsupported.
- `gpt-5-nano`: 30/31 hit the 12 s per-call timeout (reasoning at default effort) → `upstream_error`.
  Not retried with a lower `reasoning_effort` (no config for it; not needed after the result above).
- Transcription: 1 real `gpt-4o-mini-transcribe` call (synthetic "Linh" voice clip) accepted `include: logprobs`,
  confidence 0.91, text matched, cost $0.00009.
- **Owner decision 2026-11-10: D-052 = `gpt-6-luna` (parse/extract/vision/summarize) + `gpt-4o-mini-transcribe`.**
