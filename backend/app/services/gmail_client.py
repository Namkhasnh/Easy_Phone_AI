"""Gmail REST calls (API_GMAIL.md §4): list + read new messages, read-only (D-310: never marks as read).

Uses the short-lived access token from `gmail_accounts.access_token()`. Gmail errors are mapped here only.
Never logs a subject, a body, a sender or a token (D-059): ids and counts only.
"""

import asyncio
import base64
import html
import logging
import re
from dataclasses import dataclass
from datetime import UTC, datetime
from email.utils import parseaddr

import httpx2

from app.config import Settings
from app.errors import AppError

logger = logging.getLogger("easyphone.gmail")

QUERIES = {"unread": "is:unread in:inbox", "today": "in:inbox newer_than:1d"}  # API_GMAIL §4 `window`
_TAG = re.compile(r"<(script|style)\b.*?</\1>|<[^>]+>", re.S | re.I)
_SPACES = re.compile(r"[ \t\r\f\v]+")
_BLANK_LINES = re.compile(r"\n\s*\n+")


@dataclass(frozen=True)
class MailMessage:
    message_id: str
    thread_id: str
    from_name: str  # display name, address only when there is no name
    subject: str
    received_at: datetime  # UTC
    body: str  # plain text, cut to GMAIL_BODY_MAX_CHARS


@dataclass(frozen=True)
class Inbox:
    messages: list[MailMessage]  # oldest first
    total_found: int


def _decode(data: str) -> str:
    padded = data + "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(padded.encode()).decode("utf-8", errors="replace")


def _parts(payload: dict) -> list[dict]:
    out = [payload]
    for part in payload.get("parts") or []:
        out.extend(_parts(part))
    return out


def html_to_text(raw: str) -> str:
    text = _TAG.sub(" ", re.sub(r"<br\s*/?>|</p>|</div>", "\n", raw, flags=re.I))
    return html.unescape(text)


def body_text(payload: dict, max_chars: int) -> str:
    """`text/plain` part, else the `text/html` part without tags; whitespace collapsed; cut to `max_chars`."""
    parts = _parts(payload)
    plain = [p for p in parts if p.get("mimeType") == "text/plain" and (p.get("body") or {}).get("data")]
    rich = [p for p in parts if p.get("mimeType") == "text/html" and (p.get("body") or {}).get("data")]
    if plain:
        text = _decode(plain[0]["body"]["data"])
    elif rich:
        text = html_to_text(_decode(rich[0]["body"]["data"]))
    else:
        text = ""
    text = _BLANK_LINES.sub("\n\n", _SPACES.sub(" ", text)).strip()
    return text[:max_chars]


def from_name(header: str) -> str:
    name, address = parseaddr(header)
    return (name or address or header).strip()


def parse_message(raw: dict, max_chars: int) -> MailMessage:
    payload = raw.get("payload") or {}
    headers = {h.get("name", "").lower(): h.get("value", "") for h in payload.get("headers") or []}
    millis = int(raw.get("internalDate") or 0)
    return MailMessage(
        message_id=raw["id"], thread_id=raw.get("threadId", raw["id"]),
        from_name=from_name(headers.get("from", "")), subject=headers.get("subject", "").strip(),
        received_at=datetime.fromtimestamp(millis / 1000, UTC), body=body_text(payload, max_chars),
    )


class GmailClient:
    def __init__(self, settings: Settings, http: httpx2.AsyncClient) -> None:
        self._settings = settings
        self._http = http

    async def _get(self, path: str, token: str, params: dict[str, str | int]) -> dict:
        try:
            response = await self._http.get(f"{self._settings.GMAIL_API_URL}{path}", params=params,
                                            headers={"Authorization": f"Bearer {token}"},
                                            timeout=self._settings.GOOGLE_HTTP_TIMEOUT_SECONDS)
        except httpx2.HTTPError as exc:
            logger.warning("gmail call failed: %s", type(exc).__name__)
            raise AppError("upstream_error", 503, True) from None
        if response.status_code in (401, 403):
            # Token without the Gmail scope / revoked between refresh and call → the user must reconnect.
            logger.info("gmail refused status=%s", response.status_code)
            raise AppError("gmail_reconnect_required", 409, False)
        if response.status_code != 200:
            logger.warning("gmail status=%s", response.status_code)
            raise AppError("upstream_error", 503, True)
        return response.json()

    async def new_messages(self, token: str, window: str, max_messages: int) -> Inbox:
        listing = await self._get("/messages", token, {"q": QUERIES[window], "maxResults": max_messages})
        ids = [m["id"] for m in listing.get("messages") or []][:max_messages]
        raws = await asyncio.gather(*(self._get(f"/messages/{i}", token, {"format": "full"}) for i in ids))
        messages = sorted((parse_message(r, self._settings.GMAIL_BODY_MAX_CHARS) for r in raws),
                          key=lambda m: m.received_at)
        total = max(len(messages), int(listing.get("resultSizeEstimate") or 0))
        logger.info("gmail listed count=%s total=%s", len(messages), total)
        return Inbox(messages, total)
