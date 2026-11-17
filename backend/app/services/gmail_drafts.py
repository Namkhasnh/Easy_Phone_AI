"""`POST /v1/gmail/drafts` rules (API_GMAIL.md §5, D-103, D-105, D-304, D-307): a plain-text draft in Gmail Drafts,
never sent. A retry with the same `Idempotency-Key` returns the draft it already made (24 h). 0 units, no LLM.
Never logs addresses, subjects or bodies (D-059).
"""

import base64
import logging
from datetime import datetime, timedelta
from email.message import EmailMessage
from email.policy import SMTP

import asyncpg

from app.config import Settings
from app.errors import AppError
from app.repositories import gmail_draft_keys
from app.schemas.gmail import GmailDraftRequest
from app.services import gmail_accounts
from app.services.gmail_client import GmailClient
from app.services.google_oauth import GoogleOAuth

logger = logging.getLogger("easyphone.gmail")


def _invalid_key(reason: str) -> AppError:
    return AppError("invalid_input", 422, False, details={"field": "Idempotency-Key", "reason": reason})


def reply_subject(original: str) -> str:
    original = original.strip()
    return original if original.lower().startswith("re:") else f"Re: {original}".strip()


def mime(req: GmailDraftRequest, sender: str, reply: dict[str, str] | None) -> str:
    """RFC 5322 message, UTF-8 plain text, base64url (`raw` for `drafts.create`)."""
    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = ", ".join(req.to)
    subject = req.subject.strip()
    if reply is not None:
        subject = subject or reply_subject(reply.get("subject", ""))
        if reply.get("message-id"):
            msg["In-Reply-To"] = reply["message-id"]
            msg["References"] = " ".join(x for x in (reply.get("references", ""), reply["message-id"]) if x)
    msg["Subject"] = subject
    msg.set_content(req.body, charset="utf-8")
    return base64.urlsafe_b64encode(msg.as_bytes(policy=SMTP)).decode().rstrip("=")


async def create(conn: asyncpg.Connection, user_id: str, key: str, req: GmailDraftRequest, oauth: GoogleOAuth,
                 gmail: GmailClient, settings: Settings, now: datetime) -> tuple[str, str]:
    """(draftId, messageId). Order: stored key → account + token → reply headers → drafts.create → store key."""
    stored = await gmail_draft_keys.find(conn, user_id, key)
    if stored is not None:
        if stored.account_id != req.accountId:
            raise _invalid_key("idempotencyKeyAccountMismatch")
        if now - stored.created_at >= timedelta(hours=settings.IDEMPOTENCY_WINDOW_HOURS):
            raise _invalid_key("idempotencyKeyExpired")
    email, token = await gmail_accounts.connected(conn, user_id, req.accountId, oauth, settings)
    if stored is not None:
        logger.info("gmail draft reused account=%s", req.accountId)
        return stored.draft_id, await gmail.draft_message_id(token, stored.draft_id)
    reply = await gmail.reply_headers(token, req.replyTo.messageId) if req.replyTo else None
    draft_id, message_id = await gmail.create_draft(token, mime(req, email, reply),
                                                    req.replyTo.threadId if req.replyTo else None)
    await gmail_draft_keys.insert(conn, user_id, key, req.accountId, draft_id)
    logger.info("gmail draft created account=%s", req.accountId)
    return draft_id, message_id
