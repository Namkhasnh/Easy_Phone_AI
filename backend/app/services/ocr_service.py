"""`/v1/ocr` rules (API_CONTRACT §7.3, D-061, 1 unit, fallback only). The image is checked and sent in memory, never
stored or logged (ARCHITECTURE §9). The read text is untrusted (AI_PROMPTS §2.2): it is only returned to the app,
which sends it to `/v1/extract` wrapped as `<untrusted_content source="ocr">`. Never logs text (D-059).
"""

import base64
import unicodedata
from typing import Any

from pydantic import ValidationError

from app.config import Settings
from app.errors import AppError
from app.schemas.media import MediaMeta
from app.services import prompts
from app.services.llm import LLMClient, StructuredCall
from app.services.metering import CostMeter, Deadline
from app.services.schema_check import check

SCHEMA_NAME = "OCRLinesLLM"


def _invalid(field: str, reason: str) -> AppError:
    return AppError("invalid_input", 422, False, details={"field": field, "reason": reason})


def parse_meta(raw: str) -> MediaMeta:
    try:
        return MediaMeta.model_validate_json(raw)
    except ValidationError:
        raise _invalid("meta", "invalid") from None


def jpeg_size(data: bytes) -> tuple[int, int] | None:
    """(width, height) from the first SOF marker, or None when `data` is not a readable JPEG."""
    if len(data) < 4 or data[:3] != b"\xff\xd8\xff":
        return None
    i = 2
    while i + 4 <= len(data):
        if data[i] != 0xFF:
            return None
        marker = data[i + 1]
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:  # no length
            i += 2
            continue
        length = int.from_bytes(data[i + 2:i + 4], "big")
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            if i + 9 > len(data):
                return None
            height = int.from_bytes(data[i + 5:i + 7], "big")
            width = int.from_bytes(data[i + 7:i + 9], "big")
            return width, height
        if marker == 0xDA:  # start of scan before any SOF
            return None
        i += 2 + length
    return None


def check_image(data: bytes, settings: Settings) -> None:
    """Step 3 (before any unit is reserved): > 4 MB or long side > 2048 px → 413; empty / not JPEG → 422."""
    if len(data) > settings.OCR_MAX_BYTES:
        raise AppError("payload_too_large", 413, False, details={"maxBytes": settings.OCR_MAX_BYTES})
    if not data:
        raise _invalid("image", "empty")
    size = jpeg_size(data)
    if size is None:
        raise _invalid("image", "notJpeg")
    if max(size) > settings.OCR_MAX_PIXELS:
        # TODO(spec): §7.3 gives `{maxBytes}` for 413 only; `maxPixels` added for the long-side limit.
        raise AppError("payload_too_large", 413, False, details={"maxPixels": settings.OCR_MAX_PIXELS})


def schema() -> dict[str, Any]:
    def obj(props: dict[str, Any]) -> dict[str, Any]:
        return {"type": "object", "additionalProperties": False, "required": list(props), "properties": props}

    box = obj({k: {"type": "number"} for k in ("x", "y", "width", "height")})
    return obj({"lines": {"type": "array", "items": obj({"text": {"type": "string"}, "box": box})}})


def build_messages(jpeg: bytes, settings: Settings) -> list[dict[str, Any]]:
    url = "data:image/jpeg;base64," + base64.b64encode(jpeg).decode("ascii")
    return [
        {"role": "system", "content": prompts.load("ocr", settings.PROMPT_VERSION_OCR)},
        {"role": "user", "content": [{"type": "image_url", "image_url": {"url": url, "detail": "high"}}]},
    ]


def _unit(v: Any) -> float:
    return min(1.0, max(0.0, float(v))) if isinstance(v, (int, float)) else 0.0


def post_process(raw: dict[str, Any], settings: Settings) -> list[dict[str, Any]]:
    """NFC text, empty lines dropped, boxes clamped to 0–1, total text capped at `OCR_TEXT_MAX_CHARS` (D-238)."""
    lines: list[dict[str, Any]] = []
    total = 0
    for line in raw.get("lines", []):
        text = unicodedata.normalize("NFC", str(line.get("text", ""))).strip()
        if not text:
            continue
        if total + len(text) > settings.OCR_TEXT_MAX_CHARS:
            break
        total += len(text) + 1
        b = line.get("box") or {}
        x, y = _unit(b.get("x")), _unit(b.get("y"))
        lines.append({"text": text, "box": {"x": x, "y": y, "width": min(_unit(b.get("width")), 1 - x),
                                             "height": min(_unit(b.get("height")), 1 - y)}})
    return lines


async def ocr(jpeg: bytes, settings: Settings, llm: LLMClient, budget: Deadline, meter: CostMeter) -> list[dict[str, Any]]:
    s = schema()
    call = StructuredCall("ocr", settings.PROMPT_VERSION_OCR, settings.MODEL_VISION, build_messages(jpeg, settings),
                          SCHEMA_NAME, s)
    raw = await llm.structured(call, lambda value: check(value, s), budget, meter)
    return post_process(raw, settings)
