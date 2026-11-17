"""`/v1/gmail/*` (API_GMAIL.md): accounts (§3, 0 units), new-mail summary (§4, 1 unit), drafts (§5, 0 units, never
sends). Routers stay thin."""

from datetime import datetime

import asyncpg
import httpx2
from fastapi import APIRouter, Depends, Request, Response

from app.deps import AuthedUser, Settings, authed_user, clock, db, get_settings, idempotency_key, llm, request_id
from app.schemas.gmail import (
    GmailAccountResponse,
    GmailAccountsResponse,
    GmailConnectRequest,
    GmailDraftRequest,
    GmailDraftResponse,
    GmailSummaryRequest,
    GmailSummaryResponse,
)
from app.services import gmail_accounts, gmail_drafts, gmail_summary, quota
from app.services.gmail_client import GmailClient
from app.services.google_oauth import GoogleOAuth
from app.services.llm import LLMClient
from app.services.metering import metered

router = APIRouter(prefix="/v1/gmail")


SUMMARY_ENDPOINT = "/v1/gmail/summary"


def _http(request: Request) -> httpx2.AsyncClient:
    """One HTTP client per app for Google, created on first use."""
    http = getattr(request.app.state, "google_http", None)
    if http is None:
        http = httpx2.AsyncClient()
        request.app.state.google_http = http
    return http


def google_oauth(request: Request, settings: Settings = Depends(get_settings)) -> GoogleOAuth:
    """Overridden in tests."""
    return GoogleOAuth(settings, _http(request))


def gmail_client(request: Request, settings: Settings = Depends(get_settings)) -> GmailClient:
    """Overridden in tests."""
    return GmailClient(settings, _http(request))


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


@router.post("/summary", response_model=GmailSummaryResponse)
async def summary(
    body: GmailSummaryRequest,
    response: Response,
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
    key: str = Depends(idempotency_key),
    oauth: GoogleOAuth = Depends(google_oauth),
    gmail: GmailClient = Depends(gmail_client),
    client: LLMClient = Depends(llm),
    rid: str = Depends(request_id),
) -> GmailSummaryResponse:
    """API_GMAIL §4 order: validation → account → Gmail list + get → (empty: 0 units, no LLM) → `metered()`."""
    gmail_summary.check_request(body, settings)
    email, token = await gmail_accounts.connected(conn, user.id, body.accountId, oauth, settings)
    inbox = await gmail.new_messages(token, body.window, body.maxMessages)
    if not inbox.messages:
        ent = await quota.entitlement(conn, user.id, settings, now)
        response.headers.update(quota.quota_headers(ent.quota))
        return GmailSummaryResponse(schemaVersion=settings.SCHEMA_VERSION, requestId=rid, accountEmail=email,
                                    totalFound=0, overview="", messages=[])
    out = await metered(
        conn, settings, endpoint=SUMMARY_ENDPOINT, units=settings.UNITS_GMAIL_SUMMARY, user_id=user.id, key=key,
        now=now, run=lambda budget, meter: gmail_summary.summarize(body, inbox, settings, client, budget, meter),
    )
    response.headers.update(quota.quota_headers(out.quota))
    return GmailSummaryResponse(schemaVersion=settings.SCHEMA_VERSION, requestId=rid, accountEmail=email,
                                **out.result)


@router.post("/drafts", response_model=GmailDraftResponse)
async def drafts(
    body: GmailDraftRequest,
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
    key: str = Depends(idempotency_key),  # the step's key: a retry returns the same draft (D-105)
    oauth: GoogleOAuth = Depends(google_oauth),
    gmail: GmailClient = Depends(gmail_client),
) -> GmailDraftResponse:
    draft_id, message_id = await gmail_drafts.create(conn, user.id, key, body, oauth, gmail, settings, now)
    return GmailDraftResponse(schemaVersion=settings.SCHEMA_VERSION, draftId=draft_id, messageId=message_id,
                              openUrl=settings.GMAIL_DRAFTS_URL)
