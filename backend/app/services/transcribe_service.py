"""`/v1/transcribe` rules (API_CONTRACT §7.4, D-237, D-238). Audio is checked in memory, never stored or logged."""

from pydantic import ValidationError

from app.config import Settings
from app.errors import AppError
from app.schemas.media import MediaMeta
from app.services.llm import AudioUpload, LLMClient, TranscriptResult
from app.services.metering import CostMeter, Deadline


def _invalid(field: str, reason: str) -> AppError:
    return AppError("invalid_input", 422, False, details={"field": field, "reason": reason})


def parse_meta(raw: str) -> MediaMeta:
    try:
        return MediaMeta.model_validate_json(raw)
    except ValidationError:
        raise _invalid("meta", "invalid") from None


def is_m4a_or_aac(data: bytes) -> bool:
    """MP4/M4A container (`ftyp` box at offset 4) or raw AAC ADTS (sync word 0xFFF, layer 0). Content-Type is not trusted."""
    if len(data) >= 12 and data[4:8] == b"ftyp":
        return True
    return len(data) >= 7 and data[0] == 0xFF and (data[1] & 0xF6) == 0xF0


def check_audio(data: bytes, settings: Settings) -> None:
    """Step 3 (before the rate-limit row): > 2 MB → 413 `{maxBytes}`; empty / not m4a-AAC → 422."""
    # TODO(spec): "≤ 60 s" (§7.4) is not measured (no decoder on the backend); the 2 MB cap bounds it.
    if len(data) > settings.TRANSCRIBE_MAX_BYTES:
        raise AppError("payload_too_large", 413, False, details={"maxBytes": settings.TRANSCRIBE_MAX_BYTES})
    if not data:
        raise _invalid("audio", "empty")
    if not is_m4a_or_aac(data):
        raise _invalid("audio", "notM4a")


async def transcribe(data: bytes, meta: MediaMeta, llm: LLMClient, budget: Deadline, meter: CostMeter) -> TranscriptResult:
    upload = AudioUpload(data=data, filename="audio.m4a", content_type="audio/mp4", language=meta.locale.split("-")[0])
    return await llm.transcribe(upload, budget, meter)
