"""1B.15: scoring + report for the live parse eval (AI_PROMPTS §10). Pure functions, unit-tested in CI.

Match rules (AI_PROMPTS §10 "field-level match: kind/op exact, dates exact, text fuzzy"):
- `unsupported` expected → no steps, `unsupported.message` starts with "Chưa hỗ trợ", same `reason`.
- steps: same count, same (kind, operation) in order.
- a field with an expected value: `dateTime` = same instant (offset may differ), text-like = fuzzy,
  anything else (bool, enum, minutes, phone…) = exact. Missing / null → fail.
- a field expected `null` (= must ask): the model must not invent a value.
- `dateCandidates`: every expected candidate value is offered.
- `liveMatch` hints from the fixture: `followUpQuestion: present`, `confidence: ≤ x` (date fields), `message: startsWith …`.

Reports hold case ids, check names and numbers only — never request text or model output (D-059).
"""

from __future__ import annotations

import difflib
import json
import re
import unicodedata
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path

CATALOG = json.loads((Path(__file__).parents[1] / "app" / "schemas" / "field_catalog.json").read_text("utf-8"))
FIELD_TYPES: dict[tuple[str, str], str] = {
    (k["kind"], f["id"]): f["type"] for k in CATALOG["kinds"] for f in k["fields"]
}
FUZZY_TYPES = {"text", "longText", "address"}
DATE_TYPES = {"dateTime"}
FUZZY_MIN_RATIO = 0.6


EXTRA_GROUPS = {  # 1B.15b extra cases `x_<topic>_…`
    "cal": "extra: calendar", "rem": "extra: reminders", "call": "extra: calls", "sms": "extra: messages",
    "place": "extra: places", "multi": "extra: several steps", "scope": "extra: out of scope",
    "follow": "extra: follow-up answers", "voice": "extra: speech style",
}


def group_of(case: str) -> str:
    if case.startswith("x_"):
        return EXTRA_GROUPS[case.split("_")[1]]
    if re.fullmatch(r"E\d+", case):
        return "examples E1–E8"
    if case.startswith("date_"):
        return "§8.1 dates"
    if case.startswith("name_"):
        return "§8.2 names"
    if case.startswith("inject"):
        return "§8.3 injection"
    return "§8.4 other"


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFC", s).casefold()
    return " ".join(re.sub(r"[^\w\s]", " ", s).split())


def fuzzy_equal(a: str, b: str) -> bool:
    a, b = _norm(a), _norm(b)
    if not a or not b:
        return a == b
    return a in b or b in a or difflib.SequenceMatcher(None, a, b).ratio() >= FUZZY_MIN_RATIO


def _same_date(a: str, b: str) -> bool:
    if a == b:
        return True
    try:
        da, db = datetime.fromisoformat(a), datetime.fromisoformat(b)
    except ValueError:
        return False
    if (da.tzinfo is None) != (db.tzinfo is None):
        return False
    return da == db


def value_matches(kind: str, field_id: str, expected: str, actual: str) -> bool:
    t = FIELD_TYPES.get((kind, field_id), "text")
    if t in DATE_TYPES:
        return _same_date(expected, actual)
    if t in FUZZY_TYPES:
        return fuzzy_equal(expected, actual)
    return _norm(expected) == _norm(actual)


def score(expected: dict, actual: dict, live_match: dict | None = None) -> list[str]:
    """Names of the failed checks ([] = case passed). Names never contain values."""
    fails: list[str] = []
    hints = live_match or {}
    if expected["unsupported"] is not None:
        u = actual.get("unsupported")
        if actual.get("steps"):
            fails.append("unsupported: steps returned")
        if not u or not str(u.get("message") or "").startswith("Chưa hỗ trợ"):
            fails.append("unsupported: missing or message")
        elif u.get("reason") != expected["unsupported"]["reason"]:
            fails.append("unsupported: reason")
        return fails
    if actual.get("unsupported") is not None:
        return ["unexpected unsupported"]
    e_steps, a_steps = expected["steps"], actual.get("steps") or []
    if len(e_steps) != len(a_steps):
        return [f"steps: count {len(a_steps)} ≠ {len(e_steps)}"]
    for i, (es, as_) in enumerate(zip(e_steps, a_steps)):
        if (es["kind"], es["operation"]) != (as_["kind"], as_["operation"]):
            fails.append(f"step{i}: kind/operation")
            continue
        got = {f["id"]: f for f in as_["fields"]}
        for ef in es["fields"]:
            af = got.get(ef["id"])
            av = af["value"] if af else None
            name = f"step{i}.{ef['id']}"
            if ef["value"] is None:
                if av is not None:
                    fails.append(f"{name}: invented value")
            elif av is None:
                fails.append(f"{name}: missing")
            elif not value_matches(es["kind"], ef["id"], ef["value"], av):
                fails.append(f"{name}: mismatch")
            if "confidence" in hints and av is not None and af.get("confidence") is not None:
                limit = float(str(hints["confidence"]).lstrip("≤ "))
                # the hint is about the doubtful date (AI_PROMPTS §8.1 rows 7–8), not the title
                is_date = FIELD_TYPES.get((es["kind"], ef["id"])) in DATE_TYPES
                if is_date and ef["value"] is not None and af["confidence"] > limit:
                    fails.append(f"{name}: confidence > {limit}")
        want = {c["value"] for c in es.get("dateCandidates", [])}
        have = {c["value"] for c in as_.get("dateCandidates", [])}
        missing = [w for w in want if not any(_same_date(w, h) for h in have)]
        if missing:
            fails.append(f"step{i}: {len(missing)} date candidate(s) missing")
    if hints.get("followUpQuestion") == "present" and not actual.get("followUpQuestion"):
        fails.append("followUpQuestion: missing")
    return fails


@dataclass
class CaseResult:
    case: str
    group: str
    passed: bool
    fails: list[str] = field(default_factory=list)
    error: str | None = None  # AppError code when the call failed
    latency_ms: int = 0
    tokens_in: int = 0
    tokens_out: int = 0
    cost_usd: float = 0.0


@dataclass
class ModelRun:
    model: str
    prompt_version: int
    date: str
    results: list[CaseResult]

    @property
    def passed(self) -> int:
        return sum(r.passed for r in self.results)

    @property
    def cost(self) -> float:
        return sum(r.cost_usd for r in self.results)

    def latency(self, q: float) -> int:
        xs = sorted(r.latency_ms for r in self.results)
        return xs[min(len(xs) - 1, int(q * len(xs)))] if xs else 0

    def to_json(self) -> str:
        return json.dumps({"model": self.model, "promptVersion": self.prompt_version, "date": self.date,
                           "results": [asdict(r) for r in self.results]}, ensure_ascii=False, indent=1)

    @classmethod
    def from_json(cls, text: str) -> ModelRun:
        d = json.loads(text)
        return cls(d["model"], d["promptVersion"], d["date"], [CaseResult(**r) for r in d["results"]])


def report(run: ModelRun) -> str:
    n = len(run.results)
    lines = [
        f"# Live parse eval — {run.model} — parse.v{run.prompt_version} — {run.date}",
        "",
        "> Generated by `uv run pytest -m live tests/test_live_parse.py` (1B.15, AI_PROMPTS §10).",
        "> Case ids and check names only, no user content (D-059). Cost = config prices (`MODEL_PRICES_USD_PER_1M`).",
        "",
        f"- Passed: **{run.passed}/{n}** ({run.passed / n:.0%})" if n else "- Passed: 0/0",
        f"- Latency: p50 {run.latency(0.5)} ms, p90 {run.latency(0.9)} ms, max {run.latency(1.0)} ms",
        f"- Tokens: in {sum(r.tokens_in for r in run.results)}, out {sum(r.tokens_out for r in run.results)}",
        f"- Cost: ${run.cost:.4f} total, ${run.cost / n if n else 0:.5f} per request",
        f"- Errors: {sum(r.error is not None for r in run.results)}",
        "",
        "## By group",
        "",
        "| Group | Passed |",
        "|---|---|",
    ]
    groups: dict[str, list[CaseResult]] = {}
    for r in run.results:
        groups.setdefault(r.group, []).append(r)
    for g, rs in groups.items():
        lines.append(f"| {g} | {sum(r.passed for r in rs)}/{len(rs)} |")
    lines += ["", "## Cases", "", "| Case | Result | Latency ms | Failed checks |", "|---|---|---|---|"]
    for r in run.results:
        why = f"error `{r.error}`" if r.error else "; ".join(r.fails)
        lines.append(f"| {r.case} | {'✅' if r.passed else '❌'} | {r.latency_ms} | {why} |")
    return "\n".join(lines) + "\n"


def summary(runs: list[ModelRun]) -> str:
    lines = [
        f"# Live parse eval — summary — {runs[0].date if runs else ''}",
        "",
        "> Input for D-052 (model choice). Per-model details in the files next to this one.",
        "",
        "| Model | Passed | p50 ms | p90 ms | Errors | Cost / request | Cost / 1000 requests |",
        "|---|---|---|---|---|---|---|",
    ]
    for r in sorted(runs, key=lambda r: (-r.passed, r.cost)):
        n = len(r.results) or 1
        lines.append(
            f"| `{r.model}` | {r.passed}/{len(r.results)} | {r.latency(0.5)} | {r.latency(0.9)} | "
            f"{sum(x.error is not None for x in r.results)} | ${r.cost / n:.5f} | ${r.cost / n * 1000:.2f} |"
        )
    return "\n".join(lines) + "\n"
