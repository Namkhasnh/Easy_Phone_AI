"""1B.7: `LLMClient` with a fake OpenAI `chat.completions` (no network, no cost). ARCHITECTURE §7.2, AI_PROMPTS §6."""

import asyncio
import json
from decimal import Decimal
from types import SimpleNamespace

import httpx2 as httpx
import openai
import pytest

from app.config import Settings
from app.errors import AppError
from app.services import prompts
from app.services.llm import LLMClient, StructuredCall, cost_usd, make_completions
from app.services.metering import CostMeter, Deadline

SECRET = "Nhắc tôi gọi bà Lan lúc 8 giờ"
SCHEMA = {"type": "object", "properties": {"ok": {"type": "boolean"}}, "required": ["ok"], "additionalProperties": False}
CALL = StructuredCall(
    "parse", 1, "gpt-4o-mini",
    [{"role": "system", "content": "sys"}, {"role": "user", "content": SECRET}],
    "Test", SCHEMA,
)


def resp(content=None, *, refusal=None, finish="stop", tokens=(1000, 100)):
    msg = SimpleNamespace(content=content, refusal=refusal)
    return SimpleNamespace(
        choices=[SimpleNamespace(message=msg, finish_reason=finish)],
        usage=SimpleNamespace(prompt_tokens=tokens[0], completion_tokens=tokens[1]),
    )


class FakeCompletions:
    def __init__(self, *outputs):
        self.outputs = list(outputs)
        self.calls: list[dict] = []

    async def create(self, **kwargs):
        self.calls.append(kwargs)
        out = self.outputs.pop(0)
        if isinstance(out, BaseException):
            raise out
        return out


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


def valid_if_ok(value):
    return [] if value.get("ok") is True else ["ok: must be true"]


def run(fake, *, settings=None, budget=None, meter=None):
    client = LLMClient(settings or Settings(), fake)
    return asyncio.run(client.structured(CALL, valid_if_ok, budget or Deadline(18), meter or CostMeter()))


def test_valid_first_answer_sends_strict_schema_and_config():
    fake = FakeCompletions(resp('{"ok": true}'))
    meter = CostMeter()
    assert run(fake, meter=meter) == {"ok": True}
    kw = fake.calls[0]
    assert kw["model"] == "gpt-4o-mini" and kw["store"] is False
    assert kw["response_format"] == {"type": "json_schema", "json_schema": {"name": "Test", "strict": True, "schema": SCHEMA}}
    assert kw["timeout"] == 12 and "temperature" not in kw
    assert (meter.tokens_in, meter.tokens_out) == (1000, 100)
    assert meter.cost_usd == Decimal("0.000210")  # 1000 × 0.15 + 100 × 0.60 per 1M


def test_temperature_sent_only_when_set():
    fake = FakeCompletions(resp('{"ok": true}'))
    run(fake, settings=Settings(LLM_TEMPERATURE=0.2))
    assert fake.calls[0]["temperature"] == 0.2


def test_timeout_is_min_of_12s_and_remaining():
    clock = Clock()
    budget = Deadline(18, clock)
    clock.t = 10
    fake = FakeCompletions(resp('{"ok": true}'))
    run(fake, budget=budget)
    assert fake.calls[0]["timeout"] == 8


def test_invalid_then_repaired_costs_both_calls_and_never_resends_user_text():
    fake = FakeCompletions(resp('{"ok": false}'), resp('{"ok": true}', tokens=(1200, 50)))
    meter = CostMeter()
    assert run(fake, meter=meter) == {"ok": True}
    repair = fake.calls[1]["messages"]
    assert repair[:2] == CALL.messages  # same layers, the user's text appears only in the original message
    assert repair[2] == {"role": "assistant", "content": '{"ok": false}'}
    assert repair[3]["role"] == "user" and "ok: must be true" in repair[3]["content"]
    assert SECRET not in repair[3]["content"]
    assert meter.tokens_in == 2200


def test_repair_still_invalid_is_502():
    fake = FakeCompletions(resp('{"ok": false}'), resp("not json"))
    with pytest.raises(AppError) as e:
        run(fake)
    assert (e.value.code, e.value.http_status, e.value.retryable) == ("llm_invalid_output", 502, True)
    assert len(fake.calls) == 2  # exactly one repair (D-054)


def test_repair_skipped_when_less_than_5s_left():
    clock = Clock()
    budget = Deadline(18, clock)

    class SlowFirst(FakeCompletions):
        async def create(self, **kwargs):
            clock.t = 13.5  # first call took 13.5 s → 4.5 s left
            return await super().create(**kwargs)

    fake = SlowFirst(resp('{"ok": false}'))
    with pytest.raises(AppError) as e:
        run(fake, budget=budget)
    assert (e.value.code, e.value.http_status) == ("upstream_error", 503)
    assert len(fake.calls) == 1


def test_budget_exhausted_before_call_is_503_without_calling():
    clock = Clock()
    budget = Deadline(18, clock)
    clock.t = 18
    fake = FakeCompletions()
    with pytest.raises(AppError) as e:
        run(fake, budget=budget)
    assert e.value.code == "upstream_error" and fake.calls == []


@pytest.mark.parametrize("content,kw", [
    (None, {"refusal": "no"}),
    ('{"ok": tr', {"finish": "length"}),
    ("[1, 2]", {}),
])
def test_refusal_truncation_non_object_go_to_repair(content, kw):
    fake = FakeCompletions(resp(content, **kw), resp('{"ok": true}'))
    assert run(fake) == {"ok": True}
    assert len(fake.calls) == 2


REQ = httpx.Request("POST", "https://api.openai.com/v1/chat/completions")


def status_error(cls, code):
    return cls("x", response=httpx.Response(code, request=REQ), body=None)


@pytest.mark.parametrize("exc", [
    openai.APITimeoutError(request=REQ),
    openai.APIConnectionError(request=REQ),
    status_error(openai.RateLimitError, 429),
    status_error(openai.InternalServerError, 500),
])
def test_transient_sdk_errors_are_503_upstream(exc):
    with pytest.raises(AppError) as e:
        run(FakeCompletions(exc))
    assert (e.value.code, e.value.http_status, e.value.retryable) == ("upstream_error", 503, True)


def test_other_sdk_status_is_500_internal():
    with pytest.raises(AppError) as e:
        run(FakeCompletions(status_error(openai.BadRequestError, 400)))
    assert (e.value.code, e.value.http_status) == ("internal", 500)


def test_logs_never_contain_content(caplog):
    caplog.set_level("DEBUG")
    run(FakeCompletions(resp('{"ok": false}'), resp('{"ok": true}')))
    assert "prompt=parse.v1" in caplog.text
    assert SECRET not in caplog.text and '"ok"' not in caplog.text


def test_unknown_model_uses_high_rate():
    s = Settings()
    assert cost_usd(s, "gpt-4o-mini", 1_000_000, 0) == Decimal("0.150000")
    assert cost_usd(s, "some-new-model", 1_000_000, 0) == Decimal("10.000000")


def test_missing_key_is_500_and_client_has_no_retries():
    with pytest.raises(AppError) as e:
        make_completions(Settings(OPENAI_API_KEY=None))
    assert e.value.code == "internal"
    completions = make_completions(Settings(OPENAI_API_KEY="sk-test"))
    assert completions._client.max_retries == 0


def test_repair_prompt_file_loads_and_fills():
    template = prompts.load("repair", Settings().PROMPT_VERSION_REPAIR)
    assert prompts.placeholders(template) == {"errors"}
    text = prompts.render(template, errors="a: b")
    assert "a: b" in text and "{{" not in text
    with pytest.raises(KeyError):
        prompts.render(template)
