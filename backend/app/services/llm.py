"""`LLMClient`: the only place that talks to OpenAI (ARCHITECTURE §7.2, AI_PROMPTS §0, §6, D-054, D-246, D-262).

- Model, prompt version, temperature and prices come from config (D-038, D-278).
- Structured outputs: `response_format = json_schema`, `strict: true` (D-054).
- SDK retries off (`max_retries=0`); per-call timeout = `Deadline.llm_timeout` (≤ 12 s, inside the 18 s budget).
- Invalid output → **one** repair call, only if ≥ `REPAIR_MIN_SECONDS` remain (else 503); still invalid → 502.
- OpenAI SDK errors are mapped to `AppError` **here only** (CLAUDE.md §7).
- Logs prompt name/version, model, tokens, latency, result — never messages or output (D-059).
"""

import json
import logging
import math
import time
from collections.abc import Callable
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Protocol

import openai

from app.config import Settings
from app.errors import AppError
from app.services import prompts
from app.services.metering import CostMeter, Deadline

logger = logging.getLogger("easyphone.llm")

MAX_REPAIR_LINES = 10  # AI_PROMPTS §6

# Returns validation error lines (paths only, no user text, AI_PROMPTS §6). Empty list = valid.
Validator = Callable[[dict[str, Any]], list[str]]


class Completions(Protocol):
    """The slice of `AsyncOpenAI().chat.completions` we use (a fake in tests)."""

    async def create(self, **kwargs: Any) -> Any: ...


class Transcriptions(Protocol):
    """The slice of `AsyncOpenAI().audio.transcriptions` we use (a fake in tests)."""

    async def create(self, **kwargs: Any) -> Any: ...


@dataclass(frozen=True)
class AudioUpload:
    data: bytes
    filename: str
    content_type: str
    language: str  # ISO 639-1, e.g. "vi"


@dataclass(frozen=True)
class TranscriptResult:
    text: str
    confidence: float | None  # 0–1, or None when the model gives no score (D-238)


@dataclass(frozen=True)
class StructuredCall:
    prompt_name: str  # "parse", "extract" (for logs)
    prompt_version: int
    model: str  # from `MODEL_*` config
    messages: list[dict[str, str]]  # system / developer / user layers (AI_PROMPTS §1), built by the caller
    schema_name: str  # e.g. "ParsedDraftLLM"
    schema: dict[str, Any]


def make_openai(settings: Settings) -> openai.AsyncOpenAI:
    """One `AsyncOpenAI` per process; key from env only (D-051); SDK retries off (D-262)."""
    if settings.OPENAI_API_KEY is None:
        logger.error("llm misconfigured: OPENAI_API_KEY missing")
        raise AppError("internal", 500, True)
    return openai.AsyncOpenAI(api_key=settings.OPENAI_API_KEY.get_secret_value(), max_retries=0)


def make_completions(settings: Settings) -> Completions:
    return make_openai(settings).chat.completions


def cost_usd(settings: Settings, model: str, tokens_in: int, tokens_out: int) -> Decimal:
    price_in, price_out = settings.MODEL_PRICES_USD_PER_1M.get(model, settings.UNKNOWN_MODEL_PRICE_USD_PER_1M)
    if model not in settings.MODEL_PRICES_USD_PER_1M:
        logger.warning("llm price missing model=%s → unknown-model rate", model)
    total = Decimal(str(price_in)) * tokens_in + Decimal(str(price_out)) * tokens_out
    return (total / Decimal(1_000_000)).quantize(Decimal("0.000001"))  # numeric(10,6)


@dataclass(frozen=True)
class _Output:
    raw: str | None
    value: dict[str, Any] | None
    errors: list[str]


class LLMClient:
    def __init__(self, settings: Settings, completions: Completions, transcriptions: Transcriptions | None = None) -> None:
        self._settings = settings
        self._completions = completions
        self._transcriptions = transcriptions

    async def transcribe(self, audio: AudioUpload, budget: Deadline, meter: CostMeter) -> TranscriptResult:
        """`/v1/transcribe` (API_CONTRACT §7.4). Audio is passed through, never stored or logged (D-059)."""
        if self._transcriptions is None:
            raise AppError("internal", 500, True)
        model = self._settings.MODEL_TRANSCRIBE
        timeout = budget.llm_timeout(self._settings)
        if timeout <= 0:
            raise AppError("upstream_error", 503, True)
        started = time.monotonic()
        kwargs: dict[str, Any] = {
            "model": model,
            "file": (audio.filename, audio.data, audio.content_type),
            "language": audio.language,
            "response_format": "json",
            "include": ["logprobs"],  # → confidence; models without logprobs just omit them
            "timeout": timeout,
        }
        try:
            resp = await self._transcriptions.create(**kwargs)
        except openai.APIError as exc:
            self._raise_mapped(exc, "transcribe", model, started)
        tokens_in, tokens_out, cost = self._transcribe_cost(resp, model)
        meter.add(tokens_in, tokens_out, cost)
        logger.info(
            "llm prompt=transcribe model=%s result=ok tokens_in=%s tokens_out=%s latency_ms=%s",
            model, tokens_in, tokens_out, int((time.monotonic() - started) * 1000),
        )
        return TranscriptResult((getattr(resp, "text", None) or "").strip(), _confidence(resp))

    def _transcribe_cost(self, resp: Any, model: str) -> tuple[int, int, Decimal]:
        usage = getattr(resp, "usage", None)
        if usage is not None and getattr(usage, "type", None) == "tokens":
            t_in, t_out = int(usage.input_tokens or 0), int(usage.output_tokens or 0)
            return t_in, t_out, cost_usd(self._settings, model, t_in, t_out)
        seconds = getattr(usage, "seconds", None) if usage is not None else None
        if seconds is None:
            seconds = self._settings.TRANSCRIBE_MAX_SECONDS  # no usage: assume the longest allowed clip (spend cap)
        per_minute = Decimal(str(self._settings.TRANSCRIBE_USD_PER_MINUTE))
        return 0, 0, (per_minute * Decimal(str(seconds)) / 60).quantize(Decimal("0.000001"))

    def _raise_mapped(self, exc: Exception, phase: str, model: str, started: float) -> None:
        """OpenAI SDK error → `AppError` (ARCHITECTURE §7.2): timeout / connection / 429 / 5xx → 503, else 500."""
        name = type(exc).__name__
        logger.info("llm prompt=%s model=%s result=%s latency_ms=%s",
                    phase, model, name, int((time.monotonic() - started) * 1000))
        if isinstance(exc, (openai.APITimeoutError, openai.APIConnectionError, openai.RateLimitError,
                            openai.InternalServerError)):
            raise AppError("upstream_error", 503, True) from None
        raise AppError("internal", 500, True) from None

    async def structured(
        self, call: StructuredCall, validate: Validator, budget: Deadline, meter: CostMeter
    ) -> dict[str, Any]:
        """Valid JSON object for `call.schema`, or `AppError` (502 / 503 / 500). Tokens/cost go into `meter`."""
        first = await self._complete(call, call.messages, validate, budget, meter, "first")
        if not first.errors:
            return first.value  # type: ignore[return-value]
        if not budget.can_repair(self._settings):
            self._log(call, "repair_skipped")
            raise AppError("upstream_error", 503, True)  # D-246: not enough budget for a repair
        repair = await self._complete(call, self._repair_messages(call, first), validate, budget, meter, "repair")
        if repair.errors:
            raise AppError("llm_invalid_output", 502, True)
        return repair.value  # type: ignore[return-value]

    def _repair_messages(self, call: StructuredCall, bad: _Output) -> list[dict[str, str]]:
        """AI_PROMPTS §6: previous output + error paths; never the user's text again."""
        lines = [line.replace("\n", " ")[:200] for line in bad.errors[:MAX_REPAIR_LINES]]
        text = prompts.render(
            prompts.load("repair", self._settings.PROMPT_VERSION_REPAIR), errors="\n".join(lines)
        )
        return [*call.messages, {"role": "assistant", "content": bad.raw or ""}, {"role": "user", "content": text}]

    async def _complete(
        self,
        call: StructuredCall,
        messages: list[dict[str, str]],
        validate: Validator,
        budget: Deadline,
        meter: CostMeter,
        phase: str,
    ) -> _Output:
        timeout = budget.llm_timeout(self._settings)
        if timeout <= 0:
            self._log(call, f"{phase}:budget_exhausted")
            raise AppError("upstream_error", 503, True)
        kwargs: dict[str, Any] = {
            "model": call.model,
            "messages": messages,
            "response_format": {
                "type": "json_schema",
                "json_schema": {"name": call.schema_name, "strict": True, "schema": call.schema},
            },
            "timeout": timeout,
            "store": False,  # D-059: no copy of user content kept on the OpenAI side
        }
        if self._settings.LLM_TEMPERATURE is not None:
            kwargs["temperature"] = self._settings.LLM_TEMPERATURE
        started = time.monotonic()
        try:
            resp = await self._completions.create(**kwargs)
        except (openai.APITimeoutError, openai.APIConnectionError, openai.RateLimitError, openai.InternalServerError) as exc:
            self._log(call, f"{phase}:{type(exc).__name__}", started=started)
            raise AppError("upstream_error", 503, True) from None
        except openai.APIStatusError as exc:
            # 400/401/403/404/422 from OpenAI = our config or schema bug, not the user's.
            # TODO(spec): ARCHITECTURE §7.2 maps only timeout / 5xx / 429; other statuses → 500 internal.
            self._log(call, f"{phase}:status_{exc.status_code}", started=started)
            raise AppError("internal", 500, True) from None

        tokens_in, tokens_out = _usage(resp)
        meter.add(tokens_in, tokens_out, cost_usd(self._settings, call.model, tokens_in, tokens_out))
        out = _read(resp)
        if not out.errors:
            out = _Output(out.raw, out.value, validate(out.value))  # type: ignore[arg-type]
        self._log(
            call, f"{phase}:{'ok' if not out.errors else 'invalid'}", started=started,
            tokens=(tokens_in, tokens_out), n_errors=len(out.errors),
        )
        return out

    def _log(self, call: StructuredCall, result: str, *, started: float | None = None,
             tokens: tuple[int, int] = (0, 0), n_errors: int = 0) -> None:
        latency_ms = int((time.monotonic() - started) * 1000) if started is not None else 0
        logger.info(
            "llm prompt=%s.v%s model=%s result=%s errors=%s tokens_in=%s tokens_out=%s latency_ms=%s",
            call.prompt_name, call.prompt_version, call.model, result, n_errors, tokens[0], tokens[1], latency_ms,
        )


def _confidence(resp: Any) -> float | None:
    """Mean token probability = exp(mean logprob), in 0–1; None without logprobs (D-238)."""
    logprobs = getattr(resp, "logprobs", None) or []
    values = [lp.logprob for lp in logprobs if getattr(lp, "logprob", None) is not None]
    if not values:
        return None
    return round(min(1.0, max(0.0, math.exp(sum(values) / len(values)))), 2)


def _usage(resp: Any) -> tuple[int, int]:
    usage = getattr(resp, "usage", None)
    if usage is None:
        return 0, 0
    return int(getattr(usage, "prompt_tokens", 0) or 0), int(getattr(usage, "completion_tokens", 0) or 0)


def _read(resp: Any) -> _Output:
    """First choice → JSON object. Refusal, truncation, non-JSON, non-object → one error line each."""
    choices = getattr(resp, "choices", None) or []
    if not choices:
        return _Output(None, None, ["$: no choices"])
    choice = choices[0]
    msg = choice.message
    if getattr(msg, "refusal", None):
        return _Output(None, None, ["$: refusal"])  # TODO(spec): refusal handling not in the docs; treated as invalid
    if getattr(choice, "finish_reason", None) == "length":
        return _Output(msg.content, None, ["$: output truncated"])
    raw = msg.content
    try:
        value = json.loads(raw or "")
    except json.JSONDecodeError:
        return _Output(raw, None, ["$: not valid JSON"])
    if not isinstance(value, dict):
        return _Output(raw, None, ["$: root is not an object"])
    return _Output(raw, value, [])
