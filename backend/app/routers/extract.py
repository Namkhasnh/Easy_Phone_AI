"""`POST /v1/extract` — OCR text → fields with spans (API_CONTRACT §7.2, 1 unit). Thin: rules live in `extract_service`."""

from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, Response

from app.deps import AuthedUser, Settings, authed_user, clock, db, get_settings, idempotency_key, llm, request_id
from app.schemas.extract import ExtractRequest, ExtractResponse
from app.services import extract_service, quota
from app.services.llm import LLMClient
from app.services.metering import metered

router = APIRouter(prefix="/v1")

ENDPOINT = "/v1/extract"


@router.post("/extract", response_model=ExtractResponse)
async def extract(
    body: ExtractRequest,
    response: Response,
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
    key: str = Depends(idempotency_key),  # own key, ≠ the `/v1/ocr` one (D-245)
    client: LLMClient = Depends(llm),
    rid: str = Depends(request_id),
) -> ExtractResponse:
    extract_service.check_text_length(body, settings)  # step 3: 413 before any unit is reserved
    out = await metered(
        conn, settings, endpoint=ENDPOINT, units=settings.UNITS_EXTRACT, user_id=user.id, key=key, now=now,
        run=lambda budget, meter: extract_service.extract(body, settings, client, budget, meter),
    )
    response.headers.update(quota.quota_headers(out.quota))
    return ExtractResponse(schemaVersion=settings.SCHEMA_VERSION, requestId=rid, **out.result)
