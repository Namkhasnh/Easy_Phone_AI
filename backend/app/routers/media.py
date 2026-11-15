"""`POST /v1/ocr` (API_CONTRACT §7.3, 1 unit, metered) and `POST /v1/transcribe` (§7.4, 0 units, rate-limited). Thin."""

from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, File, Form, Response, UploadFile

from app.deps import AuthedUser, Settings, authed_user, clock, db, get_settings, idempotency_key, llm, request_id
from app.schemas.media import OCRResponse, TranscribeResponse
from app.services import ocr_service, quota, transcribe_service
from app.services.llm import LLMClient
from app.services.metering import metered, rate_limited

router = APIRouter(prefix="/v1")

TRANSCRIBE = "/v1/transcribe"
OCR = "/v1/ocr"


@router.post("/ocr", response_model=OCRResponse)
async def ocr(
    response: Response,
    image: UploadFile = File(...),
    meta: str = Form(...),
    user: AuthedUser = Depends(authed_user),  # 401 → 426
    conn: asyncpg.Connection = Depends(db),
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
    key: str = Depends(idempotency_key),
    client: LLMClient = Depends(llm),
    rid: str = Depends(request_id),
) -> OCRResponse:
    # Step 3: 413 / 422 before any unit is reserved; the image is read once, in memory, never stored.
    data = await image.read(settings.OCR_MAX_BYTES + 1)
    ocr_service.check_image(data, settings)
    ocr_service.parse_meta(meta)
    out = await metered(
        conn, settings, endpoint=OCR, units=settings.UNITS_OCR, user_id=user.id, key=key, now=now,
        run=lambda budget, meter: ocr_service.ocr(data, settings, client, budget, meter),
    )
    response.headers.update(quota.quota_headers(out.quota))
    lines = out.result
    return OCRResponse(schemaVersion=settings.SCHEMA_VERSION, requestId=rid,
                       text="\n".join(l["text"] for l in lines), lines=lines)


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
