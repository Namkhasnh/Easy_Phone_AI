"""`POST /v1/extract` wire DTOs (API_CONTRACT §7.2). LLM shape (quotes) vs wire shape (UTF-16 spans): D-255."""

from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator

ExtractFieldId = Literal["title", "dateTime", "address", "personName", "phoneNumber"]  # catalog §4 `ocr`
NextAction = Literal["calendarEvent", "reminder", "copyContactInfo", "ride"]


class ExtractRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schemaVersion: Literal[1]
    ocrText: str  # untrusted (D-057); > OCR_TEXT_MAX_CHARS → 413 in the service (D-238)
    now: AwareDatetime  # D-058
    timezone: str
    locale: Literal["vi-VN", "en-US"]

    @field_validator("ocrText")
    @classmethod
    def _not_blank(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("empty")  # the app must not call extract for empty OCR text (§7.2)
        return v

    @field_validator("timezone")
    @classmethod
    def _iana(cls, v: str) -> str:
        try:
            ZoneInfo(v)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("unknownTimezone") from None
        return v


class Span(BaseModel):
    start: int = Field(ge=0)  # UTF-16 offsets into `ocrText` (DATA_MODEL §1.7)
    end: int = Field(ge=0)


class ExtractField(BaseModel):
    id: ExtractFieldId
    value: str
    confidence: float = Field(ge=0, le=1)
    span: Span | None


class ExtractResponse(BaseModel):
    schemaVersion: int
    requestId: str
    fields: list[ExtractField]
    suggestedNextAction: NextAction | None
