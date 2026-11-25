"""`POST /v1/guide` wire DTOs (API_CONTRACT §7.5, D-337): a question about using the phone → step-by-step guide."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, field_validator


class GuideRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schemaVersion: Literal[1]
    question: str  # the user's own words, secrets already masked on device (D-340); > GUIDE_QUESTION_MAX_CHARS → 413
    locale: Literal["vi-VN", "en-US"]

    @field_validator("question")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("empty")
        return v


class GuideStep(BaseModel):
    text: str
    hint: str | None


class GuideResponse(BaseModel):
    schemaVersion: int
    requestId: str
    title: str | None
    steps: list[GuideStep]
    isMoneyRelated: bool  # LLM flag OR the backend keyword check (D-339); the app adds the fixed warnings
    scamWarnings: list[str]  # 0 – 3, situation-specific, only when money-related (D-339)
    unsupported: Literal["notAGuide"] | None
