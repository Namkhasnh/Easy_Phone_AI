"""SQL for `usage_events` (DATA_MODEL §9). No business rules here."""

from datetime import datetime

import asyncpg


async def units_between(conn: asyncpg.Connection, user_id: str, start: datetime, end: datetime) -> int:
    """`sum(units)` of the user's rows with `start <= created_at < end` (API_CONTRACT §4.2)."""
    return await conn.fetchval(
        "select coalesce(sum(units), 0)::int from usage_events"
        " where user_id = $1::uuid and created_at >= $2 and created_at < $3",
        user_id,
        start,
        end,
    )
