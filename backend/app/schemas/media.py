"""Media endpoints `/v1/ocr`, `/v1/transcribe`: multipart `meta` part + responses (API_CONTRACT §7.3–7.4)."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class MediaMeta(BaseModel):
    """The `meta` part: a JSON string `{ "schemaVersion": 1, "locale": "vi-VN" }`."""

    model_config = ConfigDict(extra="forbid")
    schemaVersion: Literal[1]
    locale: Literal["vi-VN", "en-US"]


class OCRBox(BaseModel):
    """Vision `NormalizedRect` space: 0–1, origin bottom-left (API_CONTRACT §7.3)."""

    x: float = Field(ge=0, le=1)
    y: float = Field(ge=0, le=1)
    width: float = Field(ge=0, le=1)
    height: float = Field(ge=0, le=1)


class OCRLine(BaseModel):
    text: str
    box: OCRBox


class OCRResponse(BaseModel):
    schemaVersion: int
    requestId: str
    text: str  # `lines[].text` joined by "\n"
    lines: list[OCRLine]


class TranscribeResponse(BaseModel):
    schemaVersion: int
    requestId: str
    text: str
    confidence: float | None = Field(ge=0, le=1)  # null when the model gives no score (D-238)
