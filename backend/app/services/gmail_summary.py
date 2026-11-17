"""`POST /v1/gmail/summary` rules (API_GMAIL.md §4, AI_PROMPTS §5, D-154, D-308, D-310).

Mail is untrusted: every message reaches the model only inside its own
`<untrusted_content source="email" messageId="…">` block (D-057). The output schema allows only the input ids, a
summary and a bool, so it cannot carry an action. Never logs subjects, bodies or summaries (D-059).
"""

from typing import Any
from zoneinfo import ZoneInfo

from app.config import Settings
from app.errors import AppError
from app.schemas.gmail import GmailSummaryRequest
from app.services import prompts
from app.services.gmail_client import Inbox, MailMessage
from app.services.llm import LLMClient, StructuredCall
from app.services.metering import CostMeter, Deadline
from app.services.prompt_context import build_request_context
from app.services.schema_check import check
from app.services import verification_code
from app.services.untrusted import wrap_untrusted

SCHEMA_NAME = "MailSummaryLLM"


def check_request(req: GmailSummaryRequest, settings: Settings) -> None:
    """Step 3 (before Gmail and before any unit): `maxMessages` ≤ `GMAIL_MAX_MESSAGES`."""
    if req.maxMessages > settings.GMAIL_MAX_MESSAGES:
        raise AppError("invalid_input", 422, False, details={"field": "maxMessages", "reason": "tooMany"})


def llm_schema(message_ids: list[str]) -> dict[str, Any]:
    def obj(props: dict[str, Any]) -> dict[str, Any]:
        return {"type": "object", "additionalProperties": False, "required": list(props), "properties": props}

    item = obj({
        "messageId": {"type": "string", "enum": message_ids},  # the citation (D-154): only ids we sent
        "summary": {"type": "string"},
        "needsReply": {"type": "boolean"},
    })
    return obj({"overview": {"type": "string"}, "messages": {"type": "array", "items": item}})


def _block(message: MailMessage, tz: ZoneInfo, settings: Settings) -> str:
    received = message.received_at.astimezone(tz).strftime("%H:%M %d/%m/%Y")
    text = f"From: {message.from_name}\nDate: {received}\nSubject: {message.subject}\n\n{message.body}"
    # Header lines + body; the body is already cut to GMAIL_BODY_MAX_CHARS by the Gmail client.
    return wrap_untrusted(text, "email", settings.GMAIL_BODY_MAX_CHARS + 500, messageId=message.message_id)


def build_messages(req: GmailSummaryRequest, inbox: Inbox, settings: Settings) -> list[dict[str, Any]]:
    """AI_PROMPTS §1: system (static file) → developer (`<request_context>`) → user (one block per message)."""
    tz = ZoneInfo(req.timezone)
    return [
        {"role": "system", "content": prompts.load("summarize", settings.PROMPT_VERSION_SUMMARIZE)},
        {"role": "developer", "content": build_request_context(
            now=req.now, tz_name=req.timezone, locale=req.locale, enabled_kinds=[], saved_place_labels=[],
        )},
        {"role": "user", "content": "\n\n".join(_block(m, tz, settings) for m in inbox.messages)},
    ]


async def summarize(req: GmailSummaryRequest, inbox: Inbox, settings: Settings, llm: LLMClient,
                    budget: Deadline, meter: CostMeter) -> dict[str, Any]:
    schema = llm_schema([m.message_id for m in inbox.messages])
    call = StructuredCall("summarize", settings.PROMPT_VERSION_SUMMARIZE, settings.MODEL_SUMMARIZE,
                          build_messages(req, inbox, settings), SCHEMA_NAME, schema)
    raw = await llm.structured(call, lambda value: check(value, schema), budget, meter)
    return post_process(raw, inbox, req, settings)


def _cut(text: str, limit: int) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def post_process(raw: dict[str, Any], inbox: Inbox, req: GmailSummaryRequest, settings: Settings) -> dict[str, Any]:
    """Every input message once, in Gmail order (oldest first); the LLM's summary when it gave one for that id
    (an unknown id is dropped, a repeated id keeps the first), else an empty summary."""
    # TODO(spec): API_GMAIL §4 does not say what to show for a message the model skipped; empty summary, subject stays.
    by_id: dict[str, dict[str, Any]] = {}
    for item in raw.get("messages") or []:
        by_id.setdefault(str(item.get("messageId")), item)
    tz = ZoneInfo(req.timezone)
    messages = []
    for m in inbox.messages:
        item = by_id.get(m.message_id, {})
        messages.append({
            "messageId": m.message_id, "threadId": m.thread_id, "fromName": m.from_name, "subject": m.subject,
            "receivedAt": m.received_at.astimezone(tz),
            "summary": _cut(str(item.get("summary") or ""), settings.GMAIL_SUMMARY_MAX_CHARS),
            "needsReply": bool(item.get("needsReply", False)),
            "verificationCode": verification_code.recent_code(m.subject, m.body, m.received_at, req.now,
                                                              settings.VERIFICATION_CODE_MAX_AGE_MINUTES),
        })
    return {"overview": _cut(str(raw.get("overview") or ""), settings.GMAIL_OVERVIEW_MAX_CHARS),
            "messages": messages, "totalFound": inbox.total_found}
