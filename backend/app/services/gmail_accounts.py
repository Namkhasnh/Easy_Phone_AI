"""Gmail account rules (API_GMAIL.md §3, §6): connect, list, disconnect, and a fresh access token for 2.4 / 2.7.

One account per user in MVP (D-306). Tokens are encrypted before they reach SQL (D-151). Never log an email
address or a token (D-059).
"""

import logging

import asyncpg

from app.config import Settings
from app.errors import AppError
from app.repositories import gmail_accounts as repo
from app.request_id import new_ulid
from app.schemas.gmail import GmailAccount, GmailConnectRequest
from app.services import gmail_tokens
from app.services.google_oauth import GoogleOAuth, ReconnectRequired

logger = logging.getLogger("easyphone.gmail")


def _dto(row: repo.GmailAccountRow) -> GmailAccount:
    return GmailAccount(accountId=row.id, email=row.email, status=row.status)  # type: ignore[arg-type]


async def connect(conn: asyncpg.Connection, user_id: str, req: GmailConnectRequest, oauth: GoogleOAuth,
                  settings: Settings) -> GmailAccount:
    grant = await oauth.exchange(req.code, req.codeVerifier, req.redirectUri)
    missing = [s for s in settings.GMAIL_REQUIRED_SCOPES if s not in grant.scopes]
    if missing:
        # The user unticked a box on the consent screen; this grant is useless, give it back.
        await oauth.revoke(grant.refresh_token)
        raise AppError("invalid_input", 422, False, details={"field": "scope", "reason": "missingScope"})
    existing = await repo.for_user(conn, user_id)
    others = [r for r in existing if r.email != grant.email]
    if len(others) >= settings.GMAIL_MAX_ACCOUNTS:
        await oauth.revoke(grant.refresh_token)
        raise AppError("gmail_account_limit", 409, False)
    account_id = await repo.upsert(conn, user_id, f"gma_{new_ulid()}", grant.email,
                                   gmail_tokens.encrypt(grant.refresh_token, settings), sorted(grant.scopes))
    logger.info("gmail connected account=%s", account_id)
    return GmailAccount(accountId=account_id, email=grant.email, status="connected")


async def accounts(conn: asyncpg.Connection, user_id: str) -> list[GmailAccount]:
    return [_dto(r) for r in await repo.for_user(conn, user_id)]


async def disconnect(conn: asyncpg.Connection, user_id: str, account_id: str, oauth: GoogleOAuth,
                     settings: Settings) -> None:
    """Idempotent: an unknown id is not an error (API_GMAIL §3.3)."""
    blob = await repo.delete(conn, user_id, account_id)
    if blob is None:
        return
    token = gmail_tokens.decrypt(blob, settings)
    if token:
        await oauth.revoke(token)
    logger.info("gmail disconnected account=%s", account_id)


async def access_token(conn: asyncpg.Connection, user_id: str, account_id: str, oauth: GoogleOAuth,
                       settings: Settings) -> str:
    """For one Gmail call: unknown account → 404 `gmail_not_connected`; dead token → 409 `gmail_reconnect_required`
    and the row is marked `needsReconnect` so S15 / S21 show "Kết nối lại Gmail" (spec §6.12 AC5)."""
    row = next((r for r in await repo.for_user(conn, user_id) if r.id == account_id), None)
    if row is None:
        raise AppError("gmail_not_connected", 404, False)
    token = gmail_tokens.decrypt(row.refresh_token_enc, settings) if row.status == "connected" else None
    if token is not None:
        try:
            return await oauth.access_token(token)
        except ReconnectRequired:
            pass
    if row.status != "needsReconnect":
        await repo.set_status(conn, user_id, account_id, "needsReconnect")
    raise AppError("gmail_reconnect_required", 409, False)
