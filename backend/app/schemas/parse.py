"""`POST /v1/parse` wire models (API_CONTRACT §7.1, DATA_MODEL §6.2, D-277).

`ParsedDraft` = the LLM output `ParsedDraftLLM` (`task_draft.json`) + `schemaVersion` + `requestId`.
Requests use `extra="forbid"`, so a 🔒 key (`contactId`, `targetRef`, …) inside `currentDraft` is a 422 (D-056).
"""

from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, field_validator

InputMode = Literal["text", "voice", "photo", "shortcut"]  # DATA_MODEL §1 InputMode
UnsupportedReason = Literal[
    "recurringEvent", "invitation", "emailSend", "booking", "payment",
    "multiPageOcr", "bulkAction", "phaseNotEnabled", "viewCalendar", "other",
]

# TODO(spec): API_CONTRACT §7.1 gives no limit for `savedPlaceLabels`; 50 labels × 100 chars keeps the prompt bounded.
MAX_LABELS = 50
MAX_LABEL_CHARS = 100


class _Wire(BaseModel):
    model_config = ConfigDict(extra="forbid")


class ParsedField(_Wire):
    id: str
    value: str | None
    confidence: float | None = Field(ge=0, le=1)
    sourceQuote: str | None


class DateCandidate(_Wire):
    fieldId: str
    value: str
    label: str


class ParsedStep(_Wire):
    kind: str
    operation: str
    fields: list[ParsedField]
    dateCandidates: list[DateCandidate]


class Unsupported(_Wire):
    reason: UnsupportedReason
    message: str
    date: str | None = None  # D-294: `viewCalendar` day, YYYY-MM-DD in the request timezone; else null


class ParsedDraft(_Wire):
    schemaVersion: int
    requestId: str
    steps: list[ParsedStep]
    followUpQuestion: str | None
    unsupported: Unsupported | None


class CurrentDraft(_Wire):
    """`context.currentDraft`: a `ParsedDraft` the app sends back while answering (no 🔒 fields)."""

    schemaVersion: int
    requestId: str | None = None  # TODO(spec): §7.1 example carries it; a draft built on device may not have one
    steps: list[ParsedStep]
    followUpQuestion: str | None = None
    unsupported: Unsupported | None = None


class ParseContext(_Wire):
    draftId: UUID | None
    answeringFieldId: str | None = Field(pattern=r"^[A-Za-z]{1,40}$")
    currentDraft: CurrentDraft | None


class ParseRequest(_Wire):
    schemaVersion: Literal[1]
    text: str  # 1–2000 chars after trim; > 2000 → 413 in the service (API_CONTRACT §3.2, D-238)
    inputMode: InputMode
    now: AwareDatetime  # ISO 8601 with offset (D-058); naive → 422
    timezone: str
    locale: Literal["vi-VN", "en-US"]
    savedPlaceLabels: list[str] = Field(max_length=MAX_LABELS)
    context: ParseContext

    @field_validator("text")
    @classmethod
    def _text_not_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("empty")
        return v

    @field_validator("timezone")
    @classmethod
    def _iana(cls, v: str) -> str:
        try:
            ZoneInfo(v)
        except (ZoneInfoNotFoundError, ValueError):
            raise ValueError("unknownTimezone") from None
        return v

    @field_validator("savedPlaceLabels")
    @classmethod
    def _labels(cls, v: list[str]) -> list[str]:
        if any(len(label) > MAX_LABEL_CHARS for label in v):
            raise ValueError("labelTooLong")
        return v
