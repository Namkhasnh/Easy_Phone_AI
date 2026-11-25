"""`POST /v1/guide` — a question about using the phone → step-by-step guide (API_CONTRACT §7.5, D-337, 1 unit).
Thin: rules live in `guide_service`."""

from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, Response

from app.deps import (
    AuthedUser,
    Settings,
    authed_user,
    clock,
    db,
    get_settings,
    idempotency_key,
    llm,
    request_id,
)
from app.schemas.guide import GuideRequest, GuideResponse
from app.services import guide_service, quota
from app.services.llm import LLMClient
from app.services.metering import metered

router = APIRouter(prefix="/v1")

ENDPOINT = "/v1/guide"


@router.post("/guide", response_model=GuideResponse)
async def guide(
    body: GuideRequest,
    response: Response,
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
    key: str = Depends(idempotency_key),
    client: LLMClient = Depends(llm),
    rid: str = Depends(request_id),
) -> GuideResponse:
    guide_service.check_question_length(body, settings)  # step 3: 413 before any unit is reserved
    out = await metered(
        conn, settings, endpoint=ENDPOINT, units=settings.UNITS_GUIDE, user_id=user.id, key=key, now=now,
        run=lambda budget, meter: guide_service.guide(body, settings, client, budget, meter),
    )
    response.headers.update(quota.quota_headers(out.quota))
    return GuideResponse(schemaVersion=settings.SCHEMA_VERSION, requestId=rid, **out.result)
