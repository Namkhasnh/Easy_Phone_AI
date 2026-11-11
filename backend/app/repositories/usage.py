"""SQL for `usage_events` (DATA_MODEL §9). No business rules here."""

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

import asyncpg


@dataclass(frozen=True)
class UsageRow:
    id: int
    endpoint: str
    units: int
    attempt: int
    created_at: datetime


def _row(rec: asyncpg.Record) -> UsageRow:
    return UsageRow(rec["id"], rec["endpoint"], rec["units"], rec["attempt"], rec["created_at"])


async def units_between(conn: asyncpg.Connection, user_id: str, start: datetime, end: datetime) -> int:
    """`sum(units)` of the user's rows with `start <= created_at < end` (API_CONTRACT §4.2)."""
    return await conn.fetchval(
        "select coalesce(sum(units), 0)::int from usage_events"
        " where user_id = $1::uuid and created_at >= $2 and created_at < $3",
        user_id,
        start,
        end,
    )


async def units_between_excluding(
    conn: asyncpg.Connection, user_id: str, start: datetime, end: datetime, row_id: int
) -> int:
    """Same as `units_between`, without row `row_id` (a retry is never blocked by its own charge, §4.4)."""
    return await conn.fetchval(
        "select coalesce(sum(units), 0)::int from usage_events"
        " where user_id = $1::uuid and created_at >= $2 and created_at < $3 and id <> $4",
        user_id,
        start,
        end,
        row_id,
    )


async def find_by_key(conn: asyncpg.Connection, user_id: str, key: str) -> UsageRow | None:
    rec = await conn.fetchrow(
        "select id, endpoint, units, attempt, created_at from usage_events"
        " where user_id = $1::uuid and idempotency_key = $2",
        user_id,
        key,
    )
    return _row(rec) if rec else None


async def insert_keyed(conn: asyncpg.Connection, user_id: str, endpoint: str, key: str, now: datetime) -> UsageRow:
    """New row with `units = 0`, `attempt = 0`; the caller reserves units after the quota check."""
    rec = await conn.fetchrow(
        "insert into usage_events (user_id, endpoint, units, idempotency_key, attempt, created_at)"
        " values ($1::uuid, $2, 0, $3, 0, $4) returning id, endpoint, units, attempt, created_at",
        user_id,
        endpoint,
        key,
        now,
    )
    return _row(rec)


async def next_attempt(conn: asyncpg.Connection, row_id: int) -> int:
    """`attempt += 1`, returns the new number (D-246)."""
    return await conn.fetchval("update usage_events set attempt = attempt + 1 where id = $1 returning attempt", row_id)


async def set_units(conn: asyncpg.Connection, row_id: int, units: int) -> None:
    await conn.execute("update usage_events set units = $2 where id = $1", row_id, units)


async def add_cost(conn: asyncpg.Connection, row_id: int, tokens_in: int, tokens_out: int, cost_usd: Decimal) -> None:
    """Tokens and cost are **added** on every attempt (API_CONTRACT §4.4)."""
    await conn.execute(
        "update usage_events set tokens_in = tokens_in + $2, tokens_out = tokens_out + $3,"
        " cost_usd = cost_usd + $4 where id = $1",
        row_id,
        tokens_in,
        tokens_out,
        cost_usd,
    )


async def refund_if_latest(conn: asyncpg.Connection, row_id: int, attempt: int) -> bool:
    """`units = 0` only if `attempt` is still the row's latest attempt ("last attempt wins", D-246)."""
    status = await conn.execute(
        "update usage_events set units = 0 where id = $1 and attempt = $2", row_id, attempt
    )
    return status.endswith(" 1")


async def cost_between(conn: asyncpg.Connection, start: datetime, end: datetime) -> Decimal:
    """`sum(cost_usd)` of **all** users' rows in `[start, end)` (spend cap, D-087)."""
    return await conn.fetchval(
        "select coalesce(sum(cost_usd), 0) from usage_events where created_at >= $1 and created_at < $2",
        start,
        end,
    )


async def window_count(
    conn: asyncpg.Connection, user_id: str, endpoint: str, since: datetime
) -> tuple[int, datetime | None]:
    """Rows of `endpoint` for the user with `created_at > since`, and the oldest one's time (rate limit, D-237)."""
    rec = await conn.fetchrow(
        "select count(*)::int as n, min(created_at) as oldest from usage_events"
        " where user_id = $1::uuid and endpoint = $2 and created_at > $3",
        user_id,
        endpoint,
        since,
    )
    return rec["n"], rec["oldest"]


async def insert_unkeyed(conn: asyncpg.Connection, user_id: str, endpoint: str, now: datetime) -> int:
    """A `units = 0` row without an idempotency key (`/v1/transcribe`: cost still counts for the spend cap)."""
    return await conn.fetchval(
        "insert into usage_events (user_id, endpoint, units, created_at) values ($1::uuid, $2, 0, $3) returning id",
        user_id,
        endpoint,
        now,
    )
