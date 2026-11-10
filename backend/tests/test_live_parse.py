"""1B.15: golden parse fixtures against the **real** model (AI_PROMPTS §10). Costs money — `pytest -m live` only.

    LIVE_MODELS=gpt-4o-mini,gpt-6-luna uv run pytest -m live tests/test_live_parse.py -s

Default model list = `MODEL_PARSE`. Each model runs every `fixtures/prompts/parse.*.json` once, sequentially,
through the production path (`parse_service.parse`, strict schema, repair, post-processing, 18 s budget).
Writes `evals/<date>-<model>-parse.v<N>.md` (+ `.json`) and `evals/<date>-parse-summary.md` at the repo root.
"""

import asyncio
import json
import os
import time
from datetime import date
from pathlib import Path

import pytest

from app.config import Settings
from app.errors import AppError
from app.schemas.parse import ParseRequest
from app.services import parse_service
from app.services.llm import LLMClient, make_openai
from app.services.metering import CostMeter, Deadline
from tests.live_eval import CaseResult, ModelRun, group_of, report, score, summary

pytestmark = pytest.mark.live

GOLDEN = Path(__file__).parent / "fixtures" / "prompts"
EVALS = Path(__file__).parents[2] / "evals"
BASE = Settings()
MODELS = [m.strip() for m in os.environ.get("LIVE_MODELS", BASE.MODEL_PARSE).split(",") if m.strip()]


async def _run_model(model: str) -> ModelRun:
    settings = BASE.model_copy(update={"MODEL_PARSE": model})
    client = make_openai(settings)
    llm = LLMClient(settings, client.chat.completions)
    results: list[CaseResult] = []
    for path in sorted(GOLDEN.glob("parse.*.json")):
        g = json.loads(path.read_text("utf-8"))
        req = ParseRequest.model_validate(g["request"])
        meter = CostMeter()
        started = time.monotonic()
        try:
            out = await parse_service.parse(req, settings, llm, Deadline(settings.REQUEST_BUDGET_SECONDS), meter)
            fails, error = score(g["expected"], out, g.get("liveMatch")), None
        except AppError as exc:
            fails, error = [], exc.code
        results.append(CaseResult(
            case=g["case"], group=group_of(g["case"]), passed=error is None and not fails, fails=fails,
            error=error, latency_ms=int((time.monotonic() - started) * 1000),
            tokens_in=meter.tokens_in, tokens_out=meter.tokens_out, cost_usd=float(meter.cost_usd),
        ))
    await client.close()
    return ModelRun(model, settings.PROMPT_VERSION_PARSE, date.today().isoformat(), results)


@pytest.mark.parametrize("model", MODELS)
def test_live_parse(model):
    run = asyncio.run(_run_model(model))
    EVALS.mkdir(exist_ok=True)
    stem = f"{run.date}-{model}-parse.v{run.prompt_version}"
    (EVALS / f"{stem}.json").write_text(run.to_json(), "utf-8")
    (EVALS / f"{stem}.md").write_text(report(run), "utf-8")
    runs = [ModelRun.from_json(p.read_text("utf-8")) for p in sorted(EVALS.glob(f"{run.date}-*-parse.v*.json"))]
    (EVALS / f"{run.date}-parse-summary.md").write_text(summary(runs), "utf-8")
    print(f"\n{model}: {run.passed}/{len(run.results)}, p50 {run.latency(0.5)} ms, ${run.cost:.4f}")

    # The strict `task_draft.json` must be accepted by the real API: an OpenAI 400 maps to `internal`.
    assert not any(r.error == "internal" for r in run.results), "schema or request rejected by OpenAI"
    # §8.3: injected draft text never becomes an extra step.
    inj = next(r for r in run.results if r.case == "inject_current_draft")
    assert not any(f.startswith("steps:") or "kind/operation" in f for f in inj.fails)
