"""`/v1/guide` rules (API_CONTRACT §7.5, AI_PROMPTS §12, D-337 – D-340). The question is the user's own request
(`<user_request>`); secrets are masked again here before the LLM (D-340, the device masks first). After the LLM:
money flag OR keyword check, no verdict words ("an toàn", "không phải lừa đảo"…), no step that tells the user to give
an OTP / password away, limits on counts and lengths. Never logs the question or the answer (D-059).
"""

import re
import unicodedata
from typing import Any

from app.config import Settings
from app.errors import AppError
from app.schemas.guide import GuideRequest
from app.services import prompts
from app.services.llm import LLMClient, StructuredCall
from app.services.metering import CostMeter, Deadline
from app.services.schema_check import check
from app.services.untrusted import wrap_user_request

SCHEMA_NAME = "GuideLLM"
MAX_STEPS = 12
MAX_WARNINGS = 3
TITLE_MAX = 80
STEP_MAX = 240
HINT_MAX = 240
WARNING_MAX = 200
MASK = "•••"


def _fold(text: str) -> str:
    """Lower case, no diacritics, đ → d (for keyword checks only)."""
    t = unicodedata.normalize("NFD", text.casefold().replace("đ", "d"))
    return "".join(c for c in t if unicodedata.category(c) != "Mn")


# D-339: money-related on the backend side too (any one is enough). Folded words, matched on word boundaries.
MONEY_WORDS = [
    "chuyen tien", "chuyen khoan", "otp", "ma xac nhan", "ma xac thuc", "ngan hang", "thanh toan", "vi dien tu",
    "momo", "zalopay", "zalo pay", "vnpay", "nap tien", "rut tien", "vay", "so du", "tai khoan ngan hang", "the atm",
    "the tin dung", "mua hang", "dat hang", "shopee", "lazada", "tiki", "tiktok shop", "dau tu", "trung thuong",
    "qr", "ma qr", "tra tien", "gui tien", "tai khoan", "trieu", "muon tien", "tien coc", "nop phi",
]
_MONEY_RE = re.compile(r"\b(" + "|".join(re.escape(w) for w in MONEY_WORDS) + r")\b")

# D-339: never a verdict. Folded.
VERDICT_RE = re.compile(r"an toan|khong phai (la )?lua dao|khong lua dao|dang tin|yen tam|chac chan (la )?that")
# D-340: never tell the user to hand a secret to anyone (a step "nhập mã OTP vào app" is fine).
GIVE_SECRET_RE = re.compile(
    r"(doc|gui|cho|cung cap|bao(?! ve| mat)|dua|nhan tin|noi)\b[^.]{0,30}\b(otp|ma xac (nhan|thuc)|mat khau|ma pin|so the|cvv)"
)

# D-340 (backend side): digit runs that look like an OTP (4 – 8), an account (9 – 16) or a card (13 – 19, spaces
# or dashes allowed), and "mật khẩu / pass … <word>". Amounts, dates ("25/11/2026") and years ("năm 2026") stay.
_AMOUNT_AFTER = r"(?!\d|[ ]?(?:đ|đồng|dong|k|nghìn|ngàn|triệu|tr|vnd|vnđ|tiền|tien)\b)"  # an amount is not a secret ("482913 đọc" is not "đ")
_DIGITS_RE = re.compile(r"(?<![\d/])(?<!năm )(?<!nam )(?:(?:\d[ \-.]?){4,19}\d|\d{4})" + _AMOUNT_AFTER, re.IGNORECASE)
_PASSWORD_RE = re.compile(r"(?i)\b(mật khẩu|mat khau|password|pass|mã pin|ma pin|pin)\b(\s*(là|la|:)?\s*)(\S+)")


def mask_secrets(text: str) -> str:
    text = _PASSWORD_RE.sub(lambda m: f"{m.group(1)}{m.group(2)}{MASK}", text)
    return _DIGITS_RE.sub(MASK, text)


def is_money_related(text: str) -> bool:
    return bool(_MONEY_RE.search(_fold(text)))


def check_question_length(req: GuideRequest, settings: Settings) -> None:
    """Step 3 (before any unit is reserved): too long → 413 `{ maxChars }` (D-238 style)."""
    if len(req.question) > settings.GUIDE_QUESTION_MAX_CHARS:
        raise AppError("payload_too_large", 413, False, details={"maxChars": settings.GUIDE_QUESTION_MAX_CHARS})


def llm_schema() -> dict[str, Any]:
    def obj(props: dict[str, Any]) -> dict[str, Any]:
        return {"type": "object", "additionalProperties": False, "required": list(props), "properties": props}

    step = obj({"text": {"type": "string"}, "hint": {"type": ["string", "null"]}})
    return obj({
        "kind": {"type": "string", "enum": ["guide", "notAGuide"]},
        "title": {"type": "string"},
        "steps": {"type": "array", "items": step},
        "isMoneyRelated": {"type": "boolean"},
        "scamWarnings": {"type": "array", "items": {"type": "string"}},
    })


def validate(value: Any, schema: dict[str, Any]) -> list[str]:
    errors = check(value, schema)
    if errors:
        return errors
    if value["kind"] == "guide" and not any(s["text"].strip() for s in value["steps"]):
        return ["$.steps: a guide needs at least one step"]
    return []


def build_messages(req: GuideRequest, settings: Settings) -> list[dict[str, Any]]:
    """AI_PROMPTS §1 layers: system (static file) → user (`<user_request>`, masked). No catalog, no context."""
    return [
        {"role": "system", "content": prompts.load("guide", settings.PROMPT_VERSION_GUIDE)},
        {"role": "user", "content": wrap_user_request(mask_secrets(req.question), settings.GUIDE_QUESTION_MAX_CHARS)},
    ]


async def guide(req: GuideRequest, settings: Settings, llm: LLMClient, budget: Deadline, meter: CostMeter) -> dict:
    schema = llm_schema()
    call = StructuredCall("guide", settings.PROMPT_VERSION_GUIDE, settings.MODEL_GUIDE,
                          build_messages(req, settings), SCHEMA_NAME, schema)
    raw = await llm.structured(call, lambda value: validate(value, schema), budget, meter)
    return post_process(raw, req.question)


def _clean(text: str | None, limit: int) -> str | None:
    if text is None:
        return None
    t = " ".join(unicodedata.normalize("NFC", text).split())
    if not t:
        return None
    return t if len(t) <= limit else t[: limit - 1].rstrip() + "…"


_NEGATION_RE = re.compile(r"\b(khong|dung|chang|tu choi|khong nen|khong duoc|tuyet doi khong|khong bao gio|dung bao gio)\s+$")


def _allowed(text: str) -> bool:
    folded = _fold(text)
    if VERDICT_RE.search(folded):
        return False
    # "Đừng đọc mã OTP cho ai" is a warning, not a handover.
    return all(_NEGATION_RE.search(folded[max(0, m.start() - 24):m.start()])
               for m in GIVE_SECRET_RE.finditer(folded))


def post_process(raw: dict[str, Any], question: str) -> dict:
    """LLM shape → wire shape (API_CONTRACT §7.5)."""
    if raw.get("kind") != "guide":
        return {"title": None, "steps": [], "isMoneyRelated": is_money_related(question), "scamWarnings": [],
                "unsupported": "notAGuide"}
    steps: list[dict[str, Any]] = []
    for s in raw.get("steps", []):
        text = _clean(s.get("text"), STEP_MAX)
        if text is None or not _allowed(text):
            continue
        hint = _clean(s.get("hint"), HINT_MAX)
        steps.append({"text": text, "hint": hint if hint and _allowed(hint) else None})
        if len(steps) == MAX_STEPS:
            break
    title = _clean(raw.get("title"), TITLE_MAX)
    title = title if title and _allowed(title) else None
    money = bool(raw.get("isMoneyRelated")) or is_money_related(question) or any(
        is_money_related(s["text"]) for s in steps)
    warnings: list[str] = []
    if money:
        for w in raw.get("scamWarnings", []):
            text = _clean(w, WARNING_MAX)
            if text and _allowed(text) and text not in warnings:
                warnings.append(text)
            if len(warnings) == MAX_WARNINGS:
                break
    if not steps:
        raise AppError("llm_invalid_output", 502, True)  # every step was filtered out: never show an empty guide
    return {"title": title, "steps": steps, "isMoneyRelated": money, "scamWarnings": warnings, "unsupported": None}
