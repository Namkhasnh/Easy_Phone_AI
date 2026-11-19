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


async def owner_of(conn: asyncpg.Connection, original_transaction_id: str) -> str | None:
    value = await conn.fetchval(
        "select user_id::text from subscriptions where original_transaction_id = $1", original_transaction_id)
    return value


async def user_exists(conn: asyncpg.Connection, user_id: str) -> bool:
    """A deleted account has no profile any more (FK cascade, API_CONTRACT §6.3)."""
    return bool(await conn.fetchval("select exists (select 1 from profiles where id = $1::uuid)", user_id))


async def upsert(conn: asyncpg.Connection, user_id: str, product_id: str, original_transaction_id: str,
                 expires_at: datetime | None, status: str, environment: str) -> None:
    """By `original_transaction_id` (API_CONTRACT §8.1 step 4); sending the same transaction again is idempotent."""
    await conn.execute(
        """insert into subscriptions (user_id, product_id, original_transaction_id, expires_at, status, environment)
           values ($1::uuid, $2, $3, $4, $5, $6)
           on conflict (original_transaction_id) do update
             set user_id = excluded.user_id, product_id = excluded.product_id, expires_at = excluded.expires_at,
                 status = excluded.status, environment = excluded.environment, updated_at = now()""",
        user_id, product_id, original_transaction_id, expires_at, status, environment,
    )
