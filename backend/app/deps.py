"""Shared `Depends` (ARCHITECTURE §7). `client_version`, `idempotency_key`, `db` come in their items."""

from fastapi import Depends, Header, Request

from app.auth import CurrentUser, verify_token
from app.config import Settings, get_settings
from app.errors import AppError

__all__ = ["CurrentUser", "Settings", "current_user", "get_settings", "request_id"]


def request_id(request: Request) -> str:
    return request.state.request_id


def current_user(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> CurrentUser:
    # Sync on purpose: FastAPI runs it in a threadpool; the JWKS fetch is blocking.
    # Profile upsert (D-236) is added with the DB layer (0.15).
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise AppError("unauthorized", 401, False)
    return verify_token(token.strip(), settings)
