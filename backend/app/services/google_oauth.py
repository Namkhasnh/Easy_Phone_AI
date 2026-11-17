"""Google OAuth for Gmail (API_GMAIL.md §2, D-151, D-310): code exchange, refresh, revoke.

The app (iOS OAuth client, PKCE) sends the one-time `code` + `codeVerifier`; only this module ever sees tokens.
Google errors are mapped here, nowhere else. Never log a code, token or address (D-059).
"""

import logging
from dataclasses import dataclass

import httpx2
import jwt

from app.config import Settings
from app.errors import AppError

logger = logging.getLogger("easyphone.google")

GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


class ReconnectRequired(Exception):
    """The refresh token no longer works (`invalid_grant`: 7-day Testing expiry, revoked, password change)."""


@dataclass(frozen=True)
class TokenGrant:
    refresh_token: str
    access_token: str
    scopes: frozenset[str]
    email: str


def redirect_uri(client_id: str) -> str:
    """The reversed client id scheme Google gives every iOS client: `com.googleusercontent.apps.<id>:/oauth2redirect`."""
    return f"com.googleusercontent.apps.{client_id.removesuffix('.apps.googleusercontent.com')}:/oauth2redirect"


def _client_id(settings: Settings) -> str:
    if not settings.GMAIL_CLIENT_ID:
        logger.error("gmail misconfigured: GMAIL_CLIENT_ID missing")
        raise AppError("internal", 500, True)
    return settings.GMAIL_CLIENT_ID


def _upstream(exc: Exception) -> AppError:
    logger.warning("google call failed: %s", type(exc).__name__)
    return AppError("upstream_error", 503, True)


class GoogleOAuth:
    def __init__(self, settings: Settings, http: httpx2.AsyncClient) -> None:
        self._settings = settings
        self._http = http

    async def _post(self, url: str, data: dict[str, str]) -> httpx2.Response:
        try:
            response = await self._http.post(url, data=data, timeout=self._settings.GOOGLE_HTTP_TIMEOUT_SECONDS)
        except httpx2.HTTPError as exc:
            raise _upstream(exc) from None
        if response.status_code >= 500 or response.status_code == 429:
            logger.warning("google %s status=%s", url.rsplit("/", 1)[-1], response.status_code)
            raise AppError("upstream_error", 503, True)
        return response

    async def exchange(self, code: str, code_verifier: str, redirect: str) -> TokenGrant:
        """One-time code → tokens + the account email (from the `id_token`, received straight from Google over TLS,
        so the OIDC rules allow reading it without a signature check; `aud` / `iss` are still checked)."""
        client_id = _client_id(self._settings)
        if redirect != redirect_uri(client_id):
            raise AppError("invalid_input", 422, False, details={"field": "redirectUri", "reason": "mismatch"})
        response = await self._post(self._settings.GOOGLE_TOKEN_URL, {
            "client_id": client_id, "code": code, "code_verifier": code_verifier,
            "redirect_uri": redirect, "grant_type": "authorization_code",
        })
        if response.status_code != 200:
            logger.info("google exchange refused status=%s", response.status_code)
            raise AppError("invalid_input", 422, False, details={"field": "code", "reason": "exchangeFailed"})
        body = response.json()
        refresh, access = body.get("refresh_token"), body.get("access_token")
        if not refresh or not access:
            # `access_type=offline` + `prompt=consent` always give a refresh token; without it Gmail stops in an hour.
            raise AppError("invalid_input", 422, False, details={"field": "code", "reason": "noRefreshToken"})
        try:
            claims = jwt.decode(body.get("id_token", ""), options={"verify_signature": False})
        except jwt.PyJWTError:
            raise AppError("invalid_input", 422, False, details={"field": "code", "reason": "noIdToken"}) from None
        email = claims.get("email")
        if claims.get("aud") != client_id or claims.get("iss") not in GOOGLE_ISSUERS or not email \
                or claims.get("email_verified") is False:
            raise AppError("invalid_input", 422, False, details={"field": "code", "reason": "badIdToken"})
        return TokenGrant(refresh_token=refresh, access_token=access,
                          scopes=frozenset(str(body.get("scope", "")).split()), email=str(email).lower())

    async def access_token(self, refresh_token: str) -> str:
        """Fresh access token for one request (not stored). `invalid_grant` → `ReconnectRequired`."""
        response = await self._post(self._settings.GOOGLE_TOKEN_URL, {
            "client_id": _client_id(self._settings), "refresh_token": refresh_token, "grant_type": "refresh_token",
        })
        if response.status_code != 200:
            error = response.json().get("error") if response.headers.get("content-type", "").startswith(
                "application/json") else None
            logger.info("google refresh refused status=%s error=%s", response.status_code, error)
            raise ReconnectRequired()
        return str(response.json()["access_token"])

    async def revoke(self, token: str) -> None:
        """Best effort (disconnect, account limit, DELETE /v1/me): failures are logged, never raised."""
        try:
            response = await self._http.post(self._settings.GOOGLE_REVOKE_URL, data={"token": token},
                                             timeout=self._settings.GOOGLE_HTTP_TIMEOUT_SECONDS)
            if response.status_code != 200:
                logger.info("google revoke status=%s", response.status_code)
        except httpx2.HTTPError as exc:
            logger.info("google revoke failed: %s", type(exc).__name__)
