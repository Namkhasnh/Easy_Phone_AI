"""Supabase Admin API (service role, backend only, D-033): delete the auth user (API_CONTRACT §6.3, D-073).
Never logs the key or the user's email (D-059)."""

import logging

import httpx2

from app.config import Settings
from app.errors import AppError

logger = logging.getLogger("easyphone.accounts")


class SupabaseAdmin:
    def __init__(self, settings: Settings, http: httpx2.AsyncClient) -> None:
        self._settings = settings
        self._http = http

    async def delete_user(self, user_id: str) -> None:
        """`404` = already gone → fine (idempotent). Other failures → 503 `upstream_error` (retryable)."""
        s = self._settings
        if not s.SUPABASE_URL or s.SUPABASE_SERVICE_ROLE_KEY is None:
            logger.error("accounts misconfigured: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing")
            raise AppError("internal", 500, True)
        key = s.SUPABASE_SERVICE_ROLE_KEY.get_secret_value()
        try:
            response = await self._http.delete(f"{s.SUPABASE_URL.rstrip('/')}/auth/v1/admin/users/{user_id}",
                                               headers={"apikey": key, "Authorization": f"Bearer {key}"},
                                               timeout=s.GOOGLE_HTTP_TIMEOUT_SECONDS)
        except httpx2.HTTPError as exc:
            logger.warning("supabase admin delete failed: %s", type(exc).__name__)
            raise AppError("upstream_error", 503, True) from None
        if response.status_code in (200, 204, 404):
            logger.info("account deleted status=%s", response.status_code)
            return
        logger.warning("supabase admin delete status=%s", response.status_code)
        raise AppError("upstream_error", 503, True)
