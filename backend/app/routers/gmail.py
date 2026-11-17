"""`/v1/gmail/accounts` — connect / list / disconnect (API_GMAIL.md §3). 0 units. Routers stay thin."""

import asyncpg
import httpx2
from fastapi import APIRouter, Depends, Request, Response

from app.deps import AuthedUser, Settings, authed_user, db, get_settings
from app.schemas.gmail import GmailAccountResponse, GmailAccountsResponse, GmailConnectRequest
from app.services import gmail_accounts
from app.services.google_oauth import GoogleOAuth

router = APIRouter(prefix="/v1/gmail")


def google_oauth(request: Request, settings: Settings = Depends(get_settings)) -> GoogleOAuth:
    """One HTTP client per app, created on first use. Overridden in tests."""
    http = getattr(request.app.state, "google_http", None)
    if http is None:
        http = httpx2.AsyncClient()
        request.app.state.google_http = http
    return GoogleOAuth(settings, http)


@router.post("/accounts", response_model=GmailAccountResponse)
async def connect(
    body: GmailConnectRequest,
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),
    oauth: GoogleOAuth = Depends(google_oauth),
    settings: Settings = Depends(get_settings),
) -> GmailAccountResponse:
    account = await gmail_accounts.connect(conn, user.id, body, oauth, settings)
    return GmailAccountResponse(schemaVersion=settings.SCHEMA_VERSION, account=account)


@router.get("/accounts", response_model=GmailAccountsResponse)
async def list_accounts(
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),
    settings: Settings = Depends(get_settings),
) -> GmailAccountsResponse:
    return GmailAccountsResponse(schemaVersion=settings.SCHEMA_VERSION,
                                 accounts=await gmail_accounts.accounts(conn, user.id))


@router.delete("/accounts/{account_id}", status_code=204, response_class=Response)
async def disconnect(
    account_id: str,
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),
    oauth: GoogleOAuth = Depends(google_oauth),
    settings: Settings = Depends(get_settings),
) -> Response:
    await gmail_accounts.disconnect(conn, user.id, account_id, oauth, settings)
    return Response(status_code=204)
