"""`/v1/gmail/*` DTOs (API_GMAIL.md §3, §4, §5). Requests forbid unknown keys (API_CONTRACT §0.1)."""

from typing import Annotated, Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator

from app.schemas.me import IsoDatetime


class GmailConnectRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schemaVersion: int
    code: str = Field(min_length=1, max_length=2048)
    codeVerifier: str = Field(min_length=43, max_length=128)  # RFC 7636 §4.1
    redirectUri: str = Field(min_length=1, max_length=512)


class GmailAccount(BaseModel):
    accountId: str
    email: str
    status: Literal["connected", "needsReconnect"]


class GmailAccountResponse(BaseModel):
    schemaVersion: int
    account: GmailAccount


class GmailAccountsResponse(BaseModel):
    schemaVersion: int
    accounts: list[GmailAccount]


# ---- POST /v1/gmail/summary (API_GMAIL §4) ----

class GmailSummaryRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schemaVersion: Literal[1]
    accountId: str = Field(min_length=1, max_length=64)
    window: Literal["unread", "today"]
    maxMessages: int = Field(ge=1)  # ≤ GMAIL_MAX_MESSAGES, checked in the service (config, D-038)
    now: AwareDatetime  # D-058
    timezone: str
    locale: Literal["vi-VN", "en-US"]

    @field_validator("timezone")
    @classmethod
    def _iana(cls, v: str) -> str:
        try:
            ZoneInfo(v)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("unknownTimezone") from None
        return v


class GmailMessageSummary(BaseModel):
    messageId: str
    threadId: str
    fromName: str  # display name only; the sender address is not sent (API_GMAIL §4)
    subject: str
    receivedAt: IsoDatetime
    summary: str
    needsReply: bool
    verificationCode: str | None = None  # D-311: fixed rule, recent mail only; shown + copied, never read aloud


class GmailSummaryResponse(BaseModel):
    schemaVersion: int
    requestId: str
    accountEmail: str
    totalFound: int
    overview: str
    messages: list[GmailMessageSummary]


# ---- POST /v1/gmail/drafts (API_GMAIL §5) ----

EMAIL_RE = r"^[^@\s<>,;\"]+@[^@\s<>,;\"]+\.[^@\s<>,;\"]+$"  # one plain address, no display name (RFC 5322 subset)


class ReplyTo(BaseModel):
    model_config = ConfigDict(extra="forbid")

    threadId: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9]+$")
    messageId: str = Field(min_length=1, max_length=64, pattern=r"^[A-Za-z0-9]+$")


class GmailDraftRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schemaVersion: Literal[1]
    accountId: str = Field(min_length=1, max_length=64)
    to: list[Annotated[str, Field(max_length=254, pattern=EMAIL_RE)]] = Field(min_length=1, max_length=5)
    subject: str = Field(max_length=200)
    body: str = Field(min_length=1, max_length=10_000)  # D-238
    replyTo: ReplyTo | None = None


class GmailDraftResponse(BaseModel):
    schemaVersion: int
    draftId: str
    messageId: str
    openUrl: str
