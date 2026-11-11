"""Media endpoints (`/v1/transcribe` now, `/v1/ocr` in 1D): multipart `meta` part + responses (API_CONTRACT §7.3–7.4)."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class MediaMeta(BaseModel):
    """The `meta` part: a JSON string `{ "schemaVersion": 1, "locale": "vi-VN" }`."""

    model_config = ConfigDict(extra="forbid")
    schemaVersion: Literal[1]
    locale: Literal["vi-VN", "en-US"]


class TranscribeResponse(BaseModel):
    schemaVersion: int
    requestId: str
    text: str
    confidence: float | None = Field(ge=0, le=1)  # null when the model gives no score (D-238)
