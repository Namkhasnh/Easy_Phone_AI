"""Shared `Depends` (ARCHITECTURE §7). `client_version` comes in its item."""

import re
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import UTC, datetime

import asyncpg
from fastapi import Depends, Header, Request

from app.auth import CurrentUser, verify_token
from app.config import Settings, get_settings
from app.errors import AppError
from app.services import accounts

__all__ = ["AuthedUser", "CurrentUser", "Settings", "authed_user", "clock", "current_user", "db", "get_settings", "idempotency_key", "request_id"]


@dataclass(frozen=True)
class AuthedUser(CurrentUser):
    locale: str  # stored `profiles.locale` (set on create only, D-236)


_LOWER_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def idempotency_key(key: str | None = Header(default=None, alias="Idempotency-Key")) -> str:
    """Metered POSTs only (API_CONTRACT §1, §4.4): lowercase UUID, else 422 `invalid_input`."""
    # TODO(spec): §4.4 gives only `details.field` here; the `reason` values "missing" / "notLowercaseUuid" are ours.
    if key is None or not key.strip():
        raise AppError("invalid_input", 422, False, details={"field": "Idempotency-Key", "reason": "missing"})
    if not _LOWER_UUID.match(key):
        raise AppError("invalid_input", 422, False, details={"field": "Idempotency-Key", "reason": "notLowercaseUuid"})
    return key


def request_id(request: Request) -> str:
    return request.state.request_id


def clock() -> datetime:
    """Current time (UTC, aware). Overridden in tests."""
    return datetime.now(UTC)


def current_user(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> CurrentUser:
    """JWT only, no DB. Used directly only by `DELETE /v1/me` (no profile upsert, API_CONTRACT §2)."""
    # Sync on purpose: FastAPI runs it in a threadpool; the JWKS fetch is blocking.
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise AppError("unauthorized", 401, False)
    return verify_token(token.strip(), settings)


async def db(request: Request, settings: Settings = Depends(get_settings)) -> AsyncIterator[asyncpg.Connection]:
    pool = await request.app.state.db.pool(settings)
    async with pool.acquire() as conn:
        yield conn


async def authed_user(
    user: CurrentUser = Depends(current_user),
    conn: asyncpg.Connection = Depends(db),
    accept_language: str | None = Header(default=None),
) -> AuthedUser:
    """Every authenticated endpoint except `DELETE /v1/me`: JWT + profile upsert (D-236)."""
    locale = await accounts.ensure_profile(conn, user.id, accept_language)
    return AuthedUser(id=user.id, locale=locale)
