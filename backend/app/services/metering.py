"""The shared `metered()` pipeline (ARCHITECTURE §7.1, API_CONTRACT §4.3–§4.4, D-086, D-230, D-231, D-245, D-246).

Steps 4–6 (idempotency + attempt, spend cap, quota reserve) run in one transaction under a per-user advisory lock.
The OpenAI call(s) run **outside** that transaction (P-25 / D-260), so a slow model never holds the lock.
Never logs request text or model output (D-059): only ids, endpoint, status, attempt.
"""

import asyncio
import logging
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Generic, TypeVar

import asyncpg

from app.config import Settings
from app.errors import AppError
from app.repositories import usage
from app.services import quota
from app.services.quota import QuotaInfo

logger = logging.getLogger("easyphone.metering")

T = TypeVar("T")


class Deadline:
    """Time budget of one backend attempt (`REQUEST_BUDGET_SECONDS` = 18 s, D-246)."""

    def __init__(self, seconds: float, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._end = clock() + seconds

    def remaining(self) -> float:
        return max(0.0, self._end - self._clock())

    def llm_timeout(self, settings: Settings) -> float:
        """Per-call timeout = `min(LLM_TIMEOUT_SECONDS, remaining)` (ARCHITECTURE §7.2)."""
        return min(settings.LLM_TIMEOUT_SECONDS, self.remaining())

    def can_repair(self, settings: Settings) -> bool:
        """The repair call runs only if ≥ `REPAIR_MIN_SECONDS` remain; else the caller raises `upstream_error`."""
        return self.remaining() >= settings.REPAIR_MIN_SECONDS


class CostMeter:
    """Tokens + cost spent by one attempt. `run` adds to it after every OpenAI call, so a call that fails
    after spending still reaches the spend cap (API_CONTRACT §4.4: "added on every attempt").

    ARCHITECTURE §7.1 has `run` return `(result, cost)`; a returned cost is lost when `run` raises, so `run`
    records into this meter instead.
    """

    def __init__(self) -> None:
        self.tokens_in = 0
        self.tokens_out = 0
        self.cost_usd = Decimal(0)

    def add(self, tokens_in: int, tokens_out: int, cost_usd: Decimal) -> None:
        self.tokens_in += tokens_in
        self.tokens_out += tokens_out
        self.cost_usd += cost_usd


@dataclass(frozen=True)
class Metered(Generic[T]):
    result: T
    quota: QuotaInfo  # after this request → `X-Quota-*` headers (API_CONTRACT §1)


Run = Callable[[Deadline, CostMeter], Awaitable[T]]


def _invalid_key(reason: str) -> AppError:
    return AppError("invalid_input", 422, False, details={"field": "Idempotency-Key", "reason": reason})


async def _claim(
    conn: asyncpg.Connection, user_id: str, key: str, endpoint: str, settings: Settings, now: datetime
) -> usage.UsageRow:
    """Step 4: reuse the row of this key (24 h, same endpoint) or create it (D-245)."""
    row = await usage.find_by_key(conn, user_id, key)
    if row is None:
        return await usage.insert_keyed(conn, user_id, endpoint, key, now)
    if row.endpoint != endpoint:
        raise _invalid_key("idempotencyKeyEndpointMismatch")
    if now - row.created_at >= timedelta(hours=settings.IDEMPOTENCY_WINDOW_HOURS):
        raise _invalid_key("idempotencyKeyExpired")
    return row


async def metered(
    conn: asyncpg.Connection,
    settings: Settings,
    *,
    endpoint: str,
    units: int,
    user_id: str,
    key: str,
    now: datetime,
    run: Run[T],
    deadline: Deadline | None = None,
) -> Metered[T]:
    """Steps 4–9 of API_CONTRACT §4.3. Auth, client version and body validation (1–3) happen before, in `Depends`.

    Charged at most once per key, only if the **last** attempt returned 2xx. Any exception from `run` (AppError,
    budget timeout, unexpected) refunds — `units = 0` — but only if no newer attempt started meanwhile.
    """
    budget = deadline or Deadline(settings.REQUEST_BUDGET_SECONDS)
    async with conn.transaction():
        await conn.execute("select pg_advisory_xact_lock(hashtext($1))", user_id)
        row = await _claim(conn, user_id, key, endpoint, settings, now)
        my_attempt = await usage.next_attempt(conn, row.id)
        await quota.check_spend_cap(conn, settings, now)  # 503 spend_cap, before any OpenAI call (D-086)
        quota_after = await quota.reserve(conn, user_id, row, units, settings, now)  # 402 quota_exceeded
    # An error above rolls the transaction back: a first attempt leaves no row, a retry keeps its old attempt.

    meter = CostMeter()
    try:
        try:
            async with asyncio.timeout(budget.remaining()):
                result = await run(budget, meter)
        except TimeoutError:
            raise AppError("upstream_error", 503, True) from None  # budget exhausted (D-246)
    except BaseException as exc:
        await _settle(conn, row.id, meter)
        refunded = await usage.refund_if_latest(conn, row.id, my_attempt)
        logger.info(
            "metered fail endpoint=%s row=%s attempt=%s error=%s refunded=%s",
            endpoint, row.id, my_attempt, getattr(exc, "code", type(exc).__name__), refunded,
        )
        raise
    await _settle(conn, row.id, meter)
    logger.info("metered ok endpoint=%s row=%s attempt=%s units=%s", endpoint, row.id, my_attempt, units)
    return Metered(result, quota_after)


async def _settle(conn: asyncpg.Connection, row_id: int, meter: CostMeter) -> None:
    if meter.tokens_in or meter.tokens_out or meter.cost_usd:
        await usage.add_cost(conn, row_id, meter.tokens_in, meter.tokens_out, meter.cost_usd)
