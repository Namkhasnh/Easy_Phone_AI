"""SQL for `gmail_draft_keys` (migrations/0002_gmail.sql, API_GMAIL.md §5, D-105). No business rules here."""

from dataclasses import dataclass
from datetime import datetime

import asyncpg


@dataclass(frozen=True)
class DraftKeyRow:
    account_id: str
    draft_id: str
    created_at: datetime


async def find(conn: asyncpg.Connection, user_id: str, key: str) -> DraftKeyRow | None:
    row = await conn.fetchrow(
        "select account_id, draft_id, created_at from gmail_draft_keys where user_id = $1::uuid and idempotency_key = $2",
        user_id, key,
    )
    return DraftKeyRow(row["account_id"], row["draft_id"], row["created_at"]) if row else None


async def insert(conn: asyncpg.Connection, user_id: str, key: str, account_id: str, draft_id: str) -> None:
    await conn.execute(
        """insert into gmail_draft_keys (user_id, idempotency_key, account_id, draft_id)
           values ($1::uuid, $2, $3, $4) on conflict (user_id, idempotency_key) do nothing""",
        user_id, key, account_id, draft_id,
    )
