"""`/v1/extract` rules (API_CONTRACT §7.2, AI_PROMPTS §4, §8.3, §9). `ocrText` is untrusted: it reaches the model only
inside `<untrusted_content source="ocr">` (D-057). The output schema has no field that can carry an action (§8.3).
Never logs the text or the values (D-059).
"""

import re
import unicodedata
from datetime import datetime
from typing import Any

from app.config import Settings
from app.errors import AppError
from app.schemas.extract import ExtractRequest
from app.services import prompts
from app.services.llm import LLMClient, StructuredCall
from app.services.metering import CostMeter, Deadline
from app.services.prompt_context import build_request_context
from app.services.schema_check import check
from app.services.untrusted import wrap_untrusted

SCHEMA_NAME = "ExtractLLM"
FIELD_IDS = ["title", "dateTime", "address", "personName", "phoneNumber"]
ACTIONS = ["calendarEvent", "reminder", "copyContactInfo", "ride"]
TITLE_MAX = 80
NO_SPAN_MAX_CONFIDENCE = 0.5
URL_RE = re.compile(r"https?://|www\.", re.I)
DATETIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?([+-]\d{2}:\d{2}|Z)$")


def check_text_length(req: ExtractRequest, settings: Settings) -> None:
    """Step 3 (before any unit is reserved): `ocrText` > `OCR_TEXT_MAX_CHARS` → 413 `{ maxChars }` (D-238)."""
    if len(req.ocrText) > settings.OCR_TEXT_MAX_CHARS:
        raise AppError("payload_too_large", 413, False, details={"maxChars": settings.OCR_TEXT_MAX_CHARS})


def llm_schema(settings: Settings) -> dict[str, Any]:
    def obj(props: dict[str, Any]) -> dict[str, Any]:
        return {"type": "object", "additionalProperties": False, "required": list(props), "properties": props}

    actions = [a for a in ACTIONS if a != "ride" or "ride" in settings.ENABLED_KINDS]
    field = obj({
        "id": {"type": "string", "enum": FIELD_IDS},
        "value": {"type": "string"},
        "confidence": {"type": "number"},
        "quote": {"type": ["string", "null"]},
    })
    return obj({
        "fields": {"type": "array", "items": field},
        "suggestedNextAction": {"anyOf": [{"type": "string", "enum": actions}, {"type": "null"}]},
    })


def build_messages(req: ExtractRequest, settings: Settings) -> list[dict[str, Any]]:
    """AI_PROMPTS §1: system (static file) → developer (`<request_context>`) → user (`<untrusted_content>`)."""
    return [
        {"role": "system", "content": prompts.load("extract", settings.PROMPT_VERSION_EXTRACT)},
        {"role": "developer", "content": build_request_context(
            now=req.now, tz_name=req.timezone, locale=req.locale, enabled_kinds=settings.ENABLED_KINDS,
            saved_place_labels=[],
        )},
        {"role": "user", "content": wrap_untrusted(req.ocrText, "ocr", settings.OCR_TEXT_MAX_CHARS)},
    ]


async def extract(req: ExtractRequest, settings: Settings, llm: LLMClient, budget: Deadline, meter: CostMeter) -> dict:
    schema = llm_schema(settings)
    call = StructuredCall("extract", settings.PROMPT_VERSION_EXTRACT, settings.MODEL_EXTRACT,
                          build_messages(req, settings), SCHEMA_NAME, schema)
    raw = await llm.structured(call, lambda value: check(value, schema), budget, meter)
    return post_process(raw, req.ocrText, settings)


# ---------- quote → UTF-16 span (AI_PROMPTS §4.2, D-255) ----------

def utf16_offset(text: str, index: int) -> int:
    """Code-point index → UTF-16 offset (API_CONTRACT §7.2)."""
    return len(text[:index].encode("utf-16-le")) // 2


def _normalized_with_map(text: str) -> tuple[str, list[int]]:
    """NFC, casefolded, whitespace runs collapsed to one space; `map[i]` = index in `text` of normalized char i."""
    out: list[str] = []
    mapping: list[int] = []
    prev_space = False
    for i, ch in enumerate(text):
        for c in unicodedata.normalize("NFC", ch).casefold():
            if c.isspace():
                if prev_space:
                    continue
                c, prev_space = " ", True
            else:
                prev_space = False
            out.append(c)
            mapping.append(i)
    return "".join(out), mapping


def find_span(text: str, quote: str | None) -> tuple[int, int] | None:
    """First exact match, then NFC + case + whitespace-collapsed match; UTF-16 (start, end) or None."""
    if not quote or not quote.strip():
        return None
    i = text.find(quote)
    if i >= 0:
        return utf16_offset(text, i), utf16_offset(text, i + len(quote))
    norm_text, mapping = _normalized_with_map(text)
    norm_quote, _ = _normalized_with_map(quote.strip())
    j = norm_text.find(norm_quote)
    if j < 0 or not norm_quote:
        return None
    start, last = mapping[j], mapping[j + len(norm_quote) - 1]
    return utf16_offset(text, start), utf16_offset(text, last + 1)


def _clean_value(field_id: str, value: str) -> str | None:
    value = unicodedata.normalize("NFC", value).strip()
    if not value:
        return None
    if field_id == "title":
        if len(value) > TITLE_MAX or URL_RE.search(value):  # §9.7
            return None
    if field_id == "dateTime":
        if not DATETIME_RE.match(value):
            return None
        try:
            datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None
    return value


def post_process(raw: dict[str, Any], ocr_text: str, settings: Settings) -> dict:
    """LLM shape → wire shape. One field per id; bad values dropped; title quote must be in the text (§9.7);
    no span → confidence ≤ 0.5 (API_CONTRACT §7.2)."""
    fields: list[dict[str, Any]] = []
    seen: set[str] = set()
    for f in raw.get("fields", []):
        fid = f.get("id")
        if fid not in FIELD_IDS or fid in seen:
            continue
        value = _clean_value(fid, str(f.get("value", "")))
        if value is None:
            continue
        span = find_span(ocr_text, f.get("quote"))
        if fid == "title" and span is None:
            continue  # §9.7: a title must come from the text (blocks invented / injected titles)
        conf = f.get("confidence")
        conf = min(1.0, max(0.0, float(conf))) if isinstance(conf, (int, float)) else 0.5
        if span is None:
            conf = min(conf, NO_SPAN_MAX_CONFIDENCE)
        seen.add(fid)
        fields.append({"id": fid, "value": value, "confidence": conf,
                       "span": {"start": span[0], "end": span[1]} if span else None})
    action = raw.get("suggestedNextAction")
    if action not in ACTIONS or (action == "ride" and "ride" not in settings.ENABLED_KINDS):
        action = None
    if not fields:
        action = None  # empty / blurry text → fields [] + null (§7.2)
    return {"fields": fields, "suggestedNextAction": action}
