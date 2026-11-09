"""Accounts (ARCHITECTURE §7): profile auto-create (D-236). Admin API delete comes with `DELETE /v1/me` (1G)."""

import logging

import asyncpg

from app.errors import AppError
from app.repositories import profiles

logger = logging.getLogger("easyphone.accounts")


def locale_from(accept_language: str | None) -> str:
    """`en` if the first language is English, else `vi` (same rule as error messages, API_CONTRACT §1)."""
    first = (accept_language or "").split(",")[0].split(";")[0].strip().lower()
    return "en" if first.startswith("en") else "vi"


async def ensure_profile(conn: asyncpg.Connection, user_id: str, accept_language: str | None) -> str:
    """Upsert `profiles(id=sub)`; locale is set only on create. Returns the stored locale.

    Auth user gone (deleted account, token not yet expired) → 401 (API_CONTRACT §2).
    """
    try:
        return await profiles.upsert(conn, user_id, locale_from(accept_language))
    except asyncpg.ForeignKeyViolationError:
        logger.info("profile upsert: auth user missing")
        raise AppError("unauthorized", 401, False) from None
