"""`/v1/gmail/*` DTOs (API_GMAIL.md §3, §4). Requests forbid unknown keys (API_CONTRACT §0.1)."""

from typing import Literal
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


class GmailSummaryResponse(BaseModel):
    schemaVersion: int
    requestId: str
    accountEmail: str
    totalFound: int
    overview: str
    messages: list[GmailMessageSummary]
