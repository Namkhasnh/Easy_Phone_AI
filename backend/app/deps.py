"""Shared `Depends` (ARCHITECTURE §7). `current_user`, `client_version`, `idempotency_key`, `db` come in their items."""

from fastapi import Request

from app.config import Settings, get_settings

__all__ = ["Settings", "get_settings", "request_id"]


def request_id(request: Request) -> str:
    return request.state.request_id
