"""`/v1/parse` business rules: prompt assembly, LLM call, post-processing (API_CONTRACT §7.1, AI_PROMPTS §1, §3, §9).

The result is a cleaned `ParsedDraftLLM` dict; the router adds `schemaVersion` + `requestId` (D-277).
Never logs request text or LLM output (D-059): only counts and `prompt.leak.<id>` markers.
"""

import logging
import re
import unicodedata
from datetime import date, datetime
from typing import Any
from zoneinfo import ZoneInfo

from app.config import Settings
from app.errors import AppError
from app.schemas.parse import ParseRequest
from app.services import prompts
from app.services.llm import LLMClient, StructuredCall
from app.services.metering import CostMeter, Deadline
from app.services.prompt_context import WEEKDAYS_VI, build_request_context, load_catalog
from app.services.schema_check import check
from app.services.task_draft_schema import SCHEMA_NAME, build
from app.services.untrusted import wrap_user_request

logger = logging.getLogger("easyphone.parse")

DATETIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
URL_RE = re.compile(r"(https?://\S+|www\.\S+)", re.I)
SMS_BODY_MAX = 2000  # AI_PROMPTS §9.4
MAX_DATE_CANDIDATES = 3  # AI_PROMPTS §3 DATES
FALLBACK_UNSUPPORTED_MESSAGE = "Chưa hỗ trợ yêu cầu này."  # TODO(spec): text when the backend (not the LLM) sets it


def _payload_too_large(settings: Settings) -> AppError:
    return AppError("payload_too_large", 413, False, details={"maxChars": settings.PARSE_TEXT_MAX_CHARS})


def check_text_length(req: ParseRequest, settings: Settings) -> None:
    """Step 3 (before any unit is reserved): `text` > 2000 chars → 413 `{ maxChars }` (API_CONTRACT §3.2, D-238)."""
    if len(req.text) > settings.PARSE_TEXT_MAX_CHARS:
        raise _payload_too_large(settings)


def build_messages(req: ParseRequest, settings: Settings) -> list[dict[str, str]]:
    """AI_PROMPTS §1: system (static file) → developer (`<request_context>`) → user (`<user_request>`)."""
    ctx = req.context
    current = None
    if ctx.answeringFieldId and ctx.currentDraft is not None:
        current = ctx.currentDraft.model_dump(mode="json", include={"steps", "followUpQuestion"})
    return [
        {"role": "system", "content": prompts.load("parse", settings.PROMPT_VERSION_PARSE)},
        {"role": "developer", "content": build_request_context(
            now=req.now, tz_name=req.timezone, locale=req.locale, enabled_kinds=settings.ENABLED_KINDS,
            saved_place_labels=req.savedPlaceLabels, answering_field_id=ctx.answeringFieldId, current_draft=current,
        )},
        {"role": "user", "content": wrap_user_request(req.text, settings.PARSE_TEXT_MAX_CHARS)},
    ]


async def parse(req: ParseRequest, settings: Settings, llm: LLMClient, budget: Deadline, meter: CostMeter) -> dict:
    schema = build(settings.ENABLED_KINDS)
    call = StructuredCall("parse", settings.PROMPT_VERSION_PARSE, settings.MODEL_PARSE,
                          build_messages(req, settings), SCHEMA_NAME, schema)
    raw = await llm.structured(call, lambda value: check(value, schema), budget, meter)
    return post_process(raw, req, settings)


# ---------- post-processing (API_CONTRACT §7.1 steps 2–4, AI_PROMPTS §9) ----------

def _norm(text: str) -> str:
    return unicodedata.normalize("NFC", text).casefold()


def _parse_dt(value: str) -> datetime | None:
    if not DATETIME_RE.match(value):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _encoded(value: str, field: dict[str, Any]) -> bool:
    """DATA_MODEL §1.6, same rules as Swift `Validator.isEncoded` (AI_PROMPTS §9.1 for dates)."""
    t = field["type"]
    if t == "text":
        return value == value.strip() and len(value) <= 2000
    if t == "longText":
        return len(value) <= 10_000
    if t == "dateTime":
        return _parse_dt(value) is not None
    if t == "date":
        if not DATE_RE.match(value):
            return False
        try:
            date.fromisoformat(value)
        except ValueError:
            return False
        return True
    if t == "durationMinutes":
        return value.isascii() and value.isdigit()
    if t == "bool":
        return value in ("true", "false")
    if t == "address":
        return "\n" not in value
    if t == "coordinate":
        parts = value.split(",")
        try:
            lat, lng = (float(p) for p in parts)
        except ValueError:
            return False
        return len(parts) == 2 and -90 <= lat <= 90 and -180 <= lng <= 180
    if t == "enumChoice":
        return "options" not in field or value in field["options"]  # sms `channel`: no options, checked on device (D-247)
    if t == "phone":
        return "\n" not in value  # raw OCR text before device normalization (§1.6)
    return False  # contactRef / placeRef never come from the LLM


def _local_day(value: str, tz: ZoneInfo) -> date:
    return _parse_dt(value).astimezone(tz).date()  # type: ignore[union-attr]


def _label_for(d: date, today: date) -> str:
    """`Thứ Sáu 13/11` / `Thứ Sáu 13/11 (hôm nay)` (AI_PROMPTS §3 DATES)."""
    return f"{WEEKDAYS_VI[d.weekday()]} {d.strftime('%d/%m')}" + (" (hôm nay)" if d == today else "")


def _clean_candidates(step: dict, date_ids: set[str], tz: ZoneInfo, today: date) -> list[dict]:
    out = []
    for c in step.get("dateCandidates", []):
        if c["fieldId"] not in date_ids or _parse_dt(c["value"]) is None:
            continue
        # AI_PROMPTS §9.2: the weekday in the label must be the real weekday of `value`, else rebuild the label.
        d = _local_day(c["value"], tz)
        label = c["label"] if _norm(WEEKDAYS_VI[d.weekday()]) in _norm(c["label"]) else _label_for(d, today)
        out.append({"fieldId": c["fieldId"], "value": c["value"], "label": label})
    return out[:MAX_DATE_CANDIDATES]


def _clean_field(f: dict, spec: dict, kind: str, request_text: str) -> dict:
    value, confidence, quote = f.get("value"), f.get("confidence"), f.get("sourceQuote")
    if isinstance(value, str) and spec["type"] == "text":
        value = value.strip()
    valid = value is not None and _encoded(value, spec)
    if valid and kind == "sms" and spec["id"] == "body":
        # AI_PROMPTS §9.4: ≤ 2000 chars; no URL the user did not say.
        urls = URL_RE.findall(value)
        valid = len(value) <= SMS_BODY_MAX and all(_norm(u) in _norm(request_text) for u in urls)
    if value is not None and not valid:
        value, confidence = None, 0.0  # §7.1 step 2
    elif value is None:
        confidence = None
    elif confidence is not None:
        confidence = min(1.0, max(0.0, float(confidence)))
    if quote is not None and _norm(quote) not in _norm(request_text):
        quote = None  # AI_PROMPTS §9.3
    return {"id": spec["id"], "value": value, "confidence": confidence, "sourceQuote": quote}


def _clean_step(step: dict, kinds: dict[str, dict], enabled: list[str], req: ParseRequest,
                tz: ZoneInfo, today: date) -> dict | None:
    kind_name, op = step.get("kind"), step.get("operation")
    kind = kinds.get(kind_name)
    if kind is None or kind_name not in enabled:
        return None
    if op not in {r["operation"] for r in kind["required"]}:
        return None  # §7.1 step 3: invalid (kind, operation) pair
    specs = {f["id"]: f for f in kind["fields"]}
    fields, seen = [], set()
    for f in step.get("fields", []):
        spec = specs.get(f.get("id"))
        if spec is None:
            continue  # §7.1 step 2: catalog-unknown id
        if spec["deviceOnly"] or spec["appBuilt"]:
            logger.warning("prompt.leak.%s kind=%s", spec["id"], kind_name)  # AI_PROMPTS §9.6, no content
            continue
        if "operations" in spec and op not in spec["operations"]:
            continue
        if spec["id"] in seen:
            continue  # TODO(spec): duplicate field ids in one step — first one wins
        seen.add(spec["id"])
        fields.append(_clean_field(f, spec, kind_name, req.text))
    date_ids = {f["id"] for f in kind["fields"] if f["type"] in ("dateTime", "date") and not f["deviceOnly"]}
    return {"kind": kind_name, "operation": op, "fields": fields,
            "dateCandidates": _clean_candidates(step, date_ids, tz, today)}


def _unsupported(reason: str, message: str | None = None) -> dict:
    return {"steps": [], "followUpQuestion": None,
            "unsupported": {"reason": reason, "message": message or FALLBACK_UNSUPPORTED_MESSAGE}}


def post_process(raw: dict, req: ParseRequest, settings: Settings) -> dict:
    """`ParsedDraftLLM` → the same shape, cleaned. Never raises for bad values; it nulls or drops them."""
    if raw.get("unsupported"):
        u = raw["unsupported"]
        return _unsupported(u["reason"], u.get("message"))  # §9.5: unsupported ⇒ steps []
    kinds = {k["kind"]: k for k in load_catalog()["kinds"]}
    tz = ZoneInfo(req.timezone)
    today = req.now.astimezone(tz).date()
    llm_steps = raw.get("steps", [])
    steps = [s for s in (_clean_step(s, kinds, settings.ENABLED_KINDS, req, tz, today) for s in llm_steps) if s]
    if not llm_steps:
        return _unsupported("other")  # §9.5: steps [] ⇒ unsupported set
    if not steps:
        return _unsupported("phaseNotEnabled")  # §7.1 step 3
    if sum(s["operation"] == "delete" for s in steps) >= 2:
        return _unsupported("bulkAction")  # §9.5, D-280
    question = raw.get("followUpQuestion")
    question = (question.strip() or None) if isinstance(question, str) else None
    return {"steps": steps, "followUpQuestion": question, "unsupported": None}
