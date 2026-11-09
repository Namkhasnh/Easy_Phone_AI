"""SQL for `subscriptions` (DATA_MODEL §9). No business rules here."""

from dataclasses import dataclass
from datetime import datetime

import asyncpg


@dataclass(frozen=True)
class SubscriptionRow:
    product_id: str
    status: str
    expires_at: datetime | None
    environment: str


async def for_user(conn: asyncpg.Connection, user_id: str) -> list[SubscriptionRow]:
    """All rows of the user, latest `expires_at` first (null last)."""
    rows = await conn.fetch(
        "select product_id, status, expires_at, environment from subscriptions"
        " where user_id = $1::uuid order by expires_at desc nulls last, updated_at desc",
        user_id,
    )
    return [SubscriptionRow(**dict(r)) for r in rows]
