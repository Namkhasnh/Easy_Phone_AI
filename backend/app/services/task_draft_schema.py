"""`ParsedDraftLLM` JSON Schema for OpenAI structured outputs (DATA_MODEL §6.3, D-054, D-277, D-035).

Generated from `field_catalog.json` + `ENABLED_KINDS`; never hand-written. `schemas/task_draft.json` is the snapshot
for the default `ENABLED_KINDS`, kept equal to `build()` by `tests/test_task_draft_schema.py` (regenerate with
`uv run python -m app.services.task_draft_schema`).

Strict mode (§6.3): `additionalProperties: false` on every object, every property in `required`, optional values
`["string", "null"]`. `kind` / `operation` / field `id` are enums.

A step is `anyOf` one branch per enabled kind, each with its own operation and field-id enums, so the schema itself
keeps 🔒 ids off a kind (e.g. `phoneNumber` is allowed on `ocr` — read from the photo — but never on `call` / `sms`,
D-056). Per-operation fields (`operations` in the catalog) and value encodings are still checked by the backend
after the call (API_CONTRACT §7.1 post-processing).
"""

import json
import sys
from pathlib import Path
from typing import Any

from app.services.prompt_context import load_catalog

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schemas" / "task_draft.json"
SCHEMA_NAME = "ParsedDraftLLM"

# API_CONTRACT §7.1: `unsupported.reason` values.
UNSUPPORTED_REASONS = [
    "recurringEvent", "invitation", "emailSend", "booking", "payment",
    "multiPageOcr", "bulkAction", "phaseNotEnabled", "viewCalendar", "other",
]
DATE_TYPES = {"dateTime", "date"}


def _obj(properties: dict[str, Any]) -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "required": list(properties), "properties": properties}


def _llm_fields(kind: dict[str, Any]) -> list[dict[str, Any]]:
    return [f for f in kind["fields"] if not f["deviceOnly"] and not f["appBuilt"]]  # D-056


def _step(kind: dict[str, Any]) -> dict[str, Any]:
    fields = _llm_fields(kind)
    field = _obj({
        "id": {"type": "string", "enum": [f["id"] for f in fields]},
        "value": {"type": ["string", "null"]},
        "confidence": {"type": ["number", "null"]},
        "sourceQuote": {"type": ["string", "null"]},
    })
    date_ids = [f["id"] for f in fields if f["type"] in DATE_TYPES]
    candidate = _obj({
        # A kind without date fields has no non-empty enum to give: plain string, and the backend drops any
        # candidate whose fieldId is not a date field of that kind (post-processing, 1B.10).
        "fieldId": {"type": "string", "enum": date_ids} if date_ids else {"type": "string"},
        "value": {"type": "string"},
        "label": {"type": "string"},
    })
    return _obj({
        "kind": {"type": "string", "enum": [kind["kind"]]},
        "operation": {"type": "string", "enum": [r["operation"] for r in kind["required"]]},
        "fields": {"type": "array", "items": field},
        "dateCandidates": {"type": "array", "items": candidate},
    })


def build(enabled_kinds: list[str], catalog: dict[str, Any] | None = None) -> dict[str, Any]:
    kinds = [k for k in (catalog or load_catalog())["kinds"] if k["kind"] in enabled_kinds]
    unsupported = _obj({
        "reason": {"type": "string", "enum": UNSUPPORTED_REASONS},
        "message": {"type": "string"},
        "date": {"type": ["string", "null"]},  # D-294: day to show for viewCalendar (YYYY-MM-DD)
    })
    return _obj({
        "steps": {"type": "array", "items": {"anyOf": [_step(k) for k in kinds]}},
        "followUpQuestion": {"type": ["string", "null"]},
        "unsupported": {"anyOf": [unsupported, {"type": "null"}]},
    })


def dumps(schema: dict[str, Any]) -> str:
    return json.dumps(schema, ensure_ascii=False, indent=2) + "\n"


if __name__ == "__main__":  # regenerate the snapshot
    from app.config import Settings

    SCHEMA_PATH.write_text(dumps(build(Settings().ENABLED_KINDS)), encoding="utf-8")
    sys.stdout.write(f"wrote {SCHEMA_PATH}\n")
