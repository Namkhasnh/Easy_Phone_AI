"""Contract fixtures (API_CONTRACT §11): the same bytes are decoded by the iOS `ContractFixtureTests`."""

import json
import re
from pathlib import Path
from typing import get_args

import pytest
from pydantic import BaseModel

from app.errors import MESSAGES
from app.schemas.error import ErrorCode, ErrorEnvelope
from app.schemas.health import HealthResponse
from app.schemas.me import MeResponse
from app.schemas.media import TranscribeResponse
from app.schemas.parse import ParsedDraft, ParseRequest

FIXTURES = Path(__file__).parent / "fixtures" / "contract"
NAME = re.compile(r"^(?P<endpoint>[a-z]+)\.(?P<case>[A-Za-z_]+)\.(?P<kind>request|response)\.json$")

# endpoint prefix -> response model. A new endpoint adds its row here with its fixtures (§13).
RESPONSE_MODELS: dict[str, type[BaseModel]] = {
    "health": HealthResponse,
    "me": MeResponse,
    "error": ErrorEnvelope,
    "parse": ParsedDraft,
    "transcribe": TranscribeResponse,
}
REQUEST_MODELS: dict[str, type[BaseModel]] = {
    "parse": ParseRequest,
}

# 🔒 keys never leave the device (D-056, API_CONTRACT §11).
LOCKED_KEYS = {"contactId", "phoneNumber", "targetRef", "calendarId", "resultEvidence", "imagePath"}

FILES = sorted(FIXTURES.glob("*.json"))


def _load(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def _keys(value: object) -> set[str]:
    if isinstance(value, dict):
        return set(value) | {k for v in value.values() for k in _keys(v)}
    if isinstance(value, list):
        return {k for v in value for k in _keys(v)}
    return set()


def test_folder_is_not_empty() -> None:
    assert FILES


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.name)
def test_name_and_known_endpoint(path: Path) -> None:
    match = NAME.match(path.name)
    assert match, f"{path.name} is not <endpoint>.<case>.request|response.json"
    models = RESPONSE_MODELS if match["kind"] == "response" else REQUEST_MODELS
    assert match["endpoint"] in models


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.name)
def test_fixture_validates_and_round_trips(path: Path) -> None:
    endpoint, _, kind, _ = path.name.split(".")
    model = (RESPONSE_MODELS if kind == "response" else REQUEST_MODELS)[endpoint]
    raw = _load(path)
    parsed = model.model_validate(raw)
    # Same bytes back: date format (`+07:00`, seconds), key names, nulls.
    dumped = parsed.model_dump(mode="json", exclude_unset=True)
    if endpoint == "parse" and kind == "request":
        dumped["now"] = raw["now"]  # AwareDatetime re-serializes; the value itself is checked below
        assert parsed.now.isoformat() == raw["now"]
    assert dumped == raw


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.name)
def test_no_locked_keys(path: Path) -> None:
    assert not (_keys(_load(path)) & LOCKED_KEYS)


def test_every_error_code_has_one_fixture() -> None:
    codes = set(get_args(ErrorCode))
    assert codes == set(MESSAGES), "§3.2 codes in schemas/error.py and errors.MESSAGES differ"
    for code in codes:
        envelope = ErrorEnvelope.model_validate(_load(FIXTURES / f"error.{code}.response.json"))
        assert envelope.error.code == code


def test_error_fixture_message_is_the_vi_fallback() -> None:
    for code, texts in MESSAGES.items():
        envelope = ErrorEnvelope.model_validate(_load(FIXTURES / f"error.{code}.response.json"))
        assert envelope.error.message == texts["vi"]


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("get", "/_test/app-error", None),
        ("get", "/nope", None),
        ("get", "/_test/crash", None),
        ("post", "/_test/echo", {"schemaVersion": 1}),
    ],
)
def test_rendered_errors_match_the_envelope_model(client, method, path, body) -> None:
    response = client.request(method, path, json=body)
    assert response.status_code >= 400
    ErrorEnvelope.model_validate(response.json())
