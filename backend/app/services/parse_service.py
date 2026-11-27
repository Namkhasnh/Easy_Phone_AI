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
# D-247: `channel` = "sms" (the only catalog option) or a service id from `SupportedServices.json`, which only the
# device has (DATA_MODEL §7.1 rule 4). The backend checks the id's shape; the device checks that it exists.
SERVICE_ID_RE = re.compile(r"^[a-z][a-z0-9]{0,31}$")
SERVICE_ID_FIELDS = {("sms", "channel")}
SMS_BODY_MAX = 2000  # AI_PROMPTS §9.4
MAX_DATE_CANDIDATES = 3  # AI_PROMPTS §3 DATES
# AI_PROMPTS §8.4 "very long dictation": keep the first 5 steps and ask. The text is the doc's expected output.
# TODO(spec): DOC-33 — the rule is only in §8.4 (not in the §3 prompt or the §9 checks); enforced here.
MAX_STEPS = 5
TOO_MANY_STEPS_QUESTION = "Mình làm 5 việc đầu trước nhé?"
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


_HARD = re.compile(
    r"\bthu\s*([2-7]|hai|ba|tu|nam|sau|bay)\b|\bchu nhat\b|\bcn\b|\btuan\b|\bthang\b|\bmung\b|\bam lich\b"
    r"|\bram\b|\b\d{1,2}\s*/\s*\d{1,2}\b|\bluu\b"
)
_HOUR = re.compile(r"\b\d{1,2}\s*(?:gio|h|g)(?:\d{2})?\b(?:\s*(?:\d{1,2}|ruoi)\b)?(?:\s*phut)?(?P<part>\s+(?:sang|trua|chieu|toi|dem))?")


def _fold(text: str) -> str:
    text = unicodedata.normalize("NFD", text.lower().replace("đ", "d"))
    return "".join(c for c in text if unicodedata.category(c) != "Mn")


def is_hard(text: str) -> bool:
    """D-323: requests where the model needs to think about dates: a weekday / week / month / lunar word, a numeric
    date, saving an address, an hour without a day part ("2 giờ"), several hours, or a long dictation. Only used to
    choose the reasoning effort; the text is not logged (D-059)."""
    t = _fold(text)
    if len(t) > 90 or _HARD.search(t):
        return True
    hours = list(_HOUR.finditer(t))
    return len(hours) > 1 or any(m.group("part") is None for m in hours)


async def parse(req: ParseRequest, settings: Settings, llm: LLMClient, budget: Deadline, meter: CostMeter) -> dict:
    schema = build(settings.ENABLED_KINDS)
    hard = settings.PARSE_HARD_REASONING_EFFORT if settings.PARSE_HARD_REASONING_EFFORT and is_hard(req.text) else None
    call = StructuredCall("parse", settings.PROMPT_VERSION_PARSE, settings.MODEL_PARSE,
                          build_messages(req, settings), SCHEMA_NAME, schema, reasoning_effort=hard)
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


LUNAR_RE = re.compile(r"(?:(\d{4})-)?(\d{2}|N0|N1|NX)-(\d{2})(L)?(?:T(\d{2}):(\d{2}))?")


def _lunar_ok(value: str) -> bool:
    """D-332 `lunarDate` = `[YYYY-]MM-DD[L][THH:mm]`; month 00 = every month, N0 / N1 / NX = this / next lunar month /
    next occurrence (resolved on the phone); year and L only with 01–12. Same as Swift `LunarFieldValue`. The solar
    date is computed by the app, never by the LLM."""
    m = LUNAR_RE.fullmatch(value)
    if not m:
        return False
    year, month, day, leap, hour, minute = m.groups()
    if not 1 <= int(day) <= 30:
        return False
    numeric = month.isdigit()
    if numeric and not 0 <= int(month) <= 12:
        return False
    if (leap or year) and (not numeric or int(month) == 0):
        return False
    if year and not 1800 <= int(year) <= 2199:
        return False
    return hour is None or (int(hour) <= 23 and int(minute) <= 59)


def _encoded(value: str, field: dict[str, Any], kind: str = "") -> bool:
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
    if t == "lunarDate":
        return _lunar_ok(value)
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
        if (kind, field["id"]) in SERVICE_ID_FIELDS:
            return value in field.get("options", []) or bool(SERVICE_ID_RE.match(value))
        return "options" not in field or value in field["options"]
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
    valid = value is not None and _encoded(value, spec, kind)
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


# Eval 2026-11-27: words the user said that the model sometimes leaves out (the step itself was right).
_MAPS_WORDS = [(re.compile(r"google ?map"), "googleMaps"), (re.compile(r"apple ?map|bản đồ (của )?apple"), "appleMaps")]
_SNOOZE_WORDS = [(re.compile(r"\b15 ?phút|mười lăm phút"), "min15"), (re.compile(r"\b1 ?tiếng|một tiếng|1 giờ nữa"), "hour1"),
                 (re.compile(r"sáng mai"), "tomorrowMorning")]
_YEAR_WORDS = re.compile(r"\b(19|20)\d{2}\b|năm sau|năm tới|sang năm|năm nay")


def _said(fields: list[dict], kind: str, op: str, text: str, specs: dict[str, dict]) -> None:
    """Fill `mapsApp` / `snoozeOption` from the user's own words when the model left them empty (never overrides)."""
    words = {("place", "open"): ("mapsApp", _MAPS_WORDS), ("reminder", "snooze"): ("snoozeOption", _SNOOZE_WORDS)}
    if (kind, op) not in words:
        return
    fid, table = words[(kind, op)]
    if fid not in specs or any(f["id"] == fid and f["value"] for f in fields):
        return
    folded = _norm(text)
    for pattern, value in table:
        m = pattern.search(folded)
        if m:
            fields[:] = [f for f in fields if f["id"] != fid]
            fields.append({"id": fid, "value": value, "confidence": 0.9, "sourceQuote": text[m.start():m.end()]
                           if _norm(text[m.start():m.end()]) == m.group(0) else None})
            return


def _past_date_moved(fields: list[dict], date_ids: set[str], text: str, tz: ZoneInfo, today: date) -> None:
    """D-106 (eval 2026-11-27, date_numeric_past): a day / month already passed this year (≤ 180 days ago), moved by
    the model to next year without the user saying a year → confidence ≤ 0.5, so the app asks instead of guessing."""
    if _YEAR_WORDS.search(_norm(text)):
        return
    for f in fields:
        if f["id"] not in date_ids or not f["value"] or f["confidence"] is None or f["confidence"] <= 0.5:
            continue
        d = _local_day(f["value"], tz)
        if d.year != today.year + 1:
            continue
        try:
            same_this_year = d.replace(year=today.year)
        except ValueError:  # 29/02
            continue
        if 0 < (today - same_this_year).days <= 180:
            f["confidence"] = 0.5


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
    _said(fields, kind_name, op, req.text, specs)
    _past_date_moved(fields, date_ids, req.text, tz, today)
    candidates = _clean_candidates(step, date_ids, tz, today)
    if any(f["id"] == "lunarDate" and f["value"] for f in fields):
        # D-332: with a lunar date the phone computes the solar one; a solar date / candidate from the LLM is dropped.
        for f in fields:
            if f["id"] in date_ids:
                f["value"], f["confidence"] = None, None
        candidates = []
    return {"kind": kind_name, "operation": op, "fields": fields, "dateCandidates": candidates}


def _unsupported(reason: str, message: str | None = None, day: str | None = None) -> dict:
    return {"steps": [], "followUpQuestion": None,
            "unsupported": {"reason": reason, "message": message or FALLBACK_UNSUPPORTED_MESSAGE, "date": day}}


def _view_day(value: object, today: date) -> str:
    """D-294: a valid YYYY-MM-DD from the LLM, else today (the user asked to see a day; never fail for it)."""
    if isinstance(value, str):
        try:
            return date.fromisoformat(value.strip()).isoformat()
        except ValueError:
            pass
    return today.isoformat()


def post_process(raw: dict, req: ParseRequest, settings: Settings) -> dict:
    """`ParsedDraftLLM` → the same shape, cleaned. Never raises for bad values; it nulls or drops them."""
    tz = ZoneInfo(req.timezone)
    today = req.now.astimezone(tz).date()
    if raw.get("unsupported"):
        u = raw["unsupported"]
        if u["reason"] == "viewCalendar":  # D-294: open S11 for that day, nothing to execute
            return _unsupported("viewCalendar", u.get("message"), _view_day(u.get("date"), today))
        return _unsupported(u["reason"], u.get("message"))  # §9.5: unsupported ⇒ steps []
    kinds = {k["kind"]: k for k in load_catalog()["kinds"]}
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
    if len(steps) > MAX_STEPS:
        steps, question = steps[:MAX_STEPS], TOO_MANY_STEPS_QUESTION
    return {"steps": steps, "followUpQuestion": question, "unsupported": None}
