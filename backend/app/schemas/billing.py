"""`POST /v1/billing/verify` request (API_CONTRACT §8.1). The response is `MeResponse` (§6.2)."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class BillingVerifyRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schemaVersion: Literal[1]
    signedTransaction: str = Field(min_length=1, max_length=20_000)
