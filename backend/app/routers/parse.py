"""`POST /v1/parse` — text → `ParsedDraft` (API_CONTRACT §7.1, 1 unit). Thin: rules live in `parse_service`."""

from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, Response

from app.deps import AuthedUser, Settings, authed_user, clock, db, get_settings, idempotency_key, llm, request_id
from app.schemas.parse import ParsedDraft, ParseRequest
from app.services import parse_service, quota
from app.services.llm import LLMClient
from app.services.metering import metered

router = APIRouter(prefix="/v1")

ENDPOINT = "/v1/parse"


@router.post("/parse", response_model=ParsedDraft, response_model_exclude_unset=False)
async def parse(
    body: ParseRequest,
    response: Response,
    user: AuthedUser = Depends(authed_user),  # step 1 auth (401) → step 2 client version (426)
    conn: asyncpg.Connection = Depends(db),  # same connection as `authed_user`
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
    key: str = Depends(idempotency_key),
    client: LLMClient = Depends(llm),
    rid: str = Depends(request_id),
) -> ParsedDraft:
    parse_service.check_text_length(body, settings)  # step 3: 413 before any unit is reserved
    out = await metered(
        conn, settings, endpoint=ENDPOINT, units=settings.UNITS_PARSE, user_id=user.id, key=key, now=now,
        run=lambda budget, meter: parse_service.parse(body, settings, client, budget, meter),
    )
    response.headers.update(quota.quota_headers(out.quota))
    return ParsedDraft(schemaVersion=settings.SCHEMA_VERSION, requestId=rid, **out.result)
