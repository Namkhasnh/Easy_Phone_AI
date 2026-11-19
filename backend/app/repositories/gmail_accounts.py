"""SQL for `gmail_accounts` (migrations/0002_gmail.sql, API_GMAIL.md §7). No business rules here."""

from dataclasses import dataclass

import asyncpg


@dataclass(frozen=True)
class GmailAccountRow:
    id: str
    email: str
    status: str  # connected | needsReconnect
    refresh_token_enc: bytes


async def for_user(conn: asyncpg.Connection, user_id: str) -> list[GmailAccountRow]:
    rows = await conn.fetch(
        "select id, email, status, refresh_token_enc from gmail_accounts where user_id = $1::uuid order by created_at",
        user_id,
    )
    return [GmailAccountRow(r["id"], r["email"], r["status"], bytes(r["refresh_token_enc"])) for r in rows]


async def upsert(conn: asyncpg.Connection, user_id: str, new_id: str, email: str, token_enc: bytes,
                 scopes: list[str]) -> str:
    """Insert, or replace the token of the same (user, email) and mark it connected. Returns the account id."""
    return await conn.fetchval(
        """insert into gmail_accounts (id, user_id, email, refresh_token_enc, scopes)
           values ($1, $2::uuid, $3, $4, $5)
           on conflict (user_id, email) do update
             set refresh_token_enc = excluded.refresh_token_enc, scopes = excluded.scopes,
                 status = 'connected', updated_at = now()
           returning id""",
        new_id, user_id, email, token_enc, scopes,
    )


async def delete(conn: asyncpg.Connection, user_id: str, account_id: str) -> bytes | None:
    """Delete and return the encrypted token (to revoke it), or None if there was no such row."""
    blob = await conn.fetchval(
        "delete from gmail_accounts where user_id = $1::uuid and id = $2 returning refresh_token_enc",
        user_id, account_id,
    )
    return bytes(blob) if blob is not None else None


async def set_status(conn: asyncpg.Connection, user_id: str, account_id: str, status: str) -> None:
    await conn.execute(
        "update gmail_accounts set status = $3, updated_at = now() where user_id = $1::uuid and id = $2",
        user_id, account_id, status,
    )
