"""`GET /v1/me` response = `MeResponse` (API_CONTRACT §4.5, §6.2). Dates: ISO 8601 with offset."""

from datetime import datetime
from typing import Annotated, Literal

from pydantic import AwareDatetime, BaseModel, PlainSerializer


def iso(dt: datetime) -> str:
    """`2026-11-09T00:00:00+07:00` (seconds precision, offset kept)."""
    return dt.isoformat(timespec="seconds")


IsoDatetime = Annotated[AwareDatetime, PlainSerializer(iso, return_type=str)]


class Quota(BaseModel):
    limit: int
    used: int
    remaining: int
    resetsAt: IsoDatetime


class Subscription(BaseModel):
    productId: str
    status: Literal["active", "expired", "inGracePeriod", "billingRetry", "revoked", "refunded"]
    expiresAt: IsoDatetime | None
    environment: Literal["Sandbox", "Production", "Xcode"]


class MeResponse(BaseModel):
    schemaVersion: int
    userId: str
    locale: str
    plan: Literal["free", "premium"]
    quota: Quota
    subscription: Subscription | None
