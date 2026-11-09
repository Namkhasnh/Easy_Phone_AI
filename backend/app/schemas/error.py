"""Error envelope (API_CONTRACT §3.1, D-233). `errors.render()` builds it; this model is its contract.

`details` is the union of the per-code shapes in §3.2; unknown keys are refused so a typo in a fixture or
in a new `AppError(details=…)` fails a test instead of reaching the app.
"""

from typing import Literal

from pydantic import BaseModel, ConfigDict

from app.schemas.me import Quota

ErrorCode = Literal[
    "billing_invalid",
    "unauthorized",
    "quota_exceeded",
    "billing_account_mismatch",
    "not_found",
    "payload_too_large",
    "invalid_input",
    "client_outdated",
    "rate_limited",
    "internal",
    "llm_invalid_output",
    "upstream_error",
    "spend_cap",
]


class ErrorDetails(BaseModel):
    model_config = ConfigDict(extra="forbid")

    plan: Literal["free", "premium"] | None = None  # 402
    quota: Quota | None = None  # 402
    maxBytes: int | None = None  # 413
    maxChars: int | None = None  # 413
    field: str | None = None  # 422
    reason: str | None = None  # 422
    minVersion: str | None = None  # 426
    retryAfterSeconds: int | None = None  # 429


class ErrorBody(BaseModel):
    model_config = ConfigDict(extra="forbid")

    code: ErrorCode
    message: str
    retryable: bool
    requestId: str
    details: ErrorDetails | None = None


class ErrorEnvelope(BaseModel):
    model_config = ConfigDict(extra="forbid")

    error: ErrorBody
