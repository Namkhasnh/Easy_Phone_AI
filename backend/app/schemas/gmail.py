"""`/v1/gmail/accounts` DTOs (API_GMAIL.md §3). Requests forbid unknown keys (API_CONTRACT §0.1)."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


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
