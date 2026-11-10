"""`POST /v1/transcribe` (API_CONTRACT §7.4, 0 units, rate-limited). `/v1/ocr` joins in 1D. Thin."""

from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.deps import AuthedUser, Settings, authed_user, clock, db, get_settings, llm, request_id
from app.schemas.media import TranscribeResponse
from app.services import transcribe_service
from app.services.llm import LLMClient
from app.services.metering import rate_limited

router = APIRouter(prefix="/v1")

TRANSCRIBE = "/v1/transcribe"


@router.post("/transcribe", response_model=TranscribeResponse)
async def transcribe(
    audio: UploadFile = File(...),
    meta: str = Form(...),
    user: AuthedUser = Depends(authed_user),  # 401 → 426
    conn: asyncpg.Connection = Depends(db),
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
    client: LLMClient = Depends(llm),
    rid: str = Depends(request_id),
) -> TranscribeResponse:
    # Step 3: validation before any row is written (413 / 422).
    data = await audio.read(settings.TRANSCRIBE_MAX_BYTES + 1)
    transcribe_service.check_audio(data, settings)
    parsed_meta = transcribe_service.parse_meta(meta)
    result = await rate_limited(
        conn, settings, endpoint=TRANSCRIBE, per_hour=settings.TRANSCRIBE_PER_HOUR, user_id=user.id, now=now,
        run=lambda budget, meter: transcribe_service.transcribe(data, parsed_meta, client, budget, meter),
    )
    return TranscribeResponse(schemaVersion=settings.SCHEMA_VERSION, requestId=rid, text=result.text,
                              confidence=result.confidence)
