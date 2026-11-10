"""Shared `Depends` (ARCHITECTURE §7)."""

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
from app.services.llm import LLMClient, make_completions

__all__ = ["AuthedUser", "CurrentUser", "Settings", "authed_user", "client_version", "clock", "current_user", "db", "get_settings", "idempotency_key", "llm", "request_id"]


@dataclass(frozen=True)
class AuthedUser(CurrentUser):
    locale: str  # stored `profiles.locale` (set on create only, D-236)


# `CFBundleShortVersionString(CFBundleVersion)`, e.g. `1.0.0(12)` or `1.0(1)` (API_CONTRACT §1).
_CLIENT_VERSION = re.compile(r"^(\d{1,4}(?:\.\d{1,4}){0,2})(?:\(\d{1,9}\))?$")


def version_tuple(version: str) -> tuple[int, int, int]:
    """`1.0` → (1, 0, 0). Missing parts are 0 so `1.0` == `1.0.0`."""
    parts = [int(p) for p in version.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))  # type: ignore[return-value]


def client_version(
    x_client_version: str | None = Header(default=None, alias="X-Client-Version"),
    settings: Settings = Depends(get_settings),
) -> str:
    """API_CONTRACT §4.3 step 2 (after auth, before body validation): older than `MIN_CLIENT_VERSION` → 426."""
    # TODO(spec): §1 says the header is required on all app calls but no code is given for missing / malformed;
    # 422 `invalid_input` (field `X-Client-Version`), like a missing `Idempotency-Key`.
    raw = (x_client_version or "").strip()
    if not raw:
        raise AppError("invalid_input", 422, False, details={"field": "X-Client-Version", "reason": "missing"})
    match = _CLIENT_VERSION.match(raw)
    if not match:
        raise AppError("invalid_input", 422, False, details={"field": "X-Client-Version", "reason": "malformed"})
    if version_tuple(match.group(1)) < version_tuple(settings.MIN_CLIENT_VERSION):
        raise AppError("client_outdated", 426, False, details={"minVersion": settings.MIN_CLIENT_VERSION})
    return raw


_LOWER_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def idempotency_key(key: str | None = Header(default=None, alias="Idempotency-Key")) -> str:
    """Metered POSTs only (API_CONTRACT §1, §4.4): lowercase UUID, else 422 `invalid_input`."""
    # TODO(spec): §4.4 gives only `details.field` here; the `reason` values "missing" / "notLowercaseUuid" are ours.
    if key is None or not key.strip():
        raise AppError("invalid_input", 422, False, details={"field": "Idempotency-Key", "reason": "missing"})
    if not _LOWER_UUID.match(key):
        raise AppError("invalid_input", 422, False, details={"field": "Idempotency-Key", "reason": "notLowercaseUuid"})
    return key


def llm(request: Request, settings: Settings = Depends(get_settings)) -> LLMClient:
    """One OpenAI client per app, created on first use (health / me never need the key)."""
    client = getattr(request.app.state, "llm", None)
    if client is None:
        client = LLMClient(settings, make_completions(settings))
        request.app.state.llm = client
    return client


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
    _version: str = Depends(client_version),  # declared after `current_user`: 401 is checked before 426
    conn: asyncpg.Connection = Depends(db),
    accept_language: str | None = Header(default=None),
) -> AuthedUser:
    """Every authenticated endpoint except `DELETE /v1/me`: JWT → client version → profile upsert (D-236)."""
    locale = await accounts.ensure_profile(conn, user.id, accept_language)
    return AuthedUser(id=user.id, locale=locale)
