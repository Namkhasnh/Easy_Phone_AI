"""1B.10: `POST /v1/parse` route wiring without a DB (`metered` faked). Full pipeline on Postgres: test_parse_db.py."""

import json
from datetime import UTC, datetime
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import deps
from app.config import Settings, get_settings
from app.main import create_app
from app.routers import parse as parse_router
from app.services.llm import LLMClient
from app.services.metering import CostMeter, Deadline, Metered
from app.services.quota import QuotaInfo
from tests.test_llm import FakeCompletions, resp

APP_HEADERS = {"X-Client-Version": "1.0(1)"}  # what the app sends today (MARKETING_VERSION 1.0)

FIXTURES = Path(__file__).parent / "fixtures" / "contract"
KEY = "0b9a3c2e-5f4d-4e6a-9b1c-2d3e4f5a6b7c"
SECRET = "Nhắn anh Minh là chiều nay em đến muộn"
LLM_SMS = {"steps": [{"kind": "sms", "operation": "open", "fields": [
    {"id": "recipientName", "value": "anh Minh", "confidence": 0.95, "sourceQuote": "anh Minh"},
    {"id": "body", "value": "Chiều nay em đến muộn nhé.", "confidence": 0.85, "sourceQuote": None},
    {"id": "channel", "value": "sms", "confidence": 0.6, "sourceQuote": None}], "dateCandidates": []}],
    "followUpQuestion": None, "unsupported": None}


def body(**over):
    b = json.loads((FIXTURES / "parse.sms.request.json").read_text(encoding="utf-8"))
    b.update(over)
    return b


@pytest.fixture
def setup(monkeypatch):
    fake = FakeCompletions(resp(json.dumps(LLM_SMS, ensure_ascii=False)))
    calls = []

    async def fake_metered(conn, settings, *, endpoint, units, user_id, key, now, run, deadline=None):
        calls.append({"endpoint": endpoint, "units": units, "key": key})
        result = await run(Deadline(18), CostMeter())
        return Metered(result, QuotaInfo(10, 4, 6, datetime.fromisoformat("2026-11-09T00:00:00+07:00")))

    monkeypatch.setattr(parse_router, "metered", fake_metered)
    app = create_app()

    async def no_db():
        yield None

    app.dependency_overrides[deps.authed_user] = lambda: deps.AuthedUser(id="u1", locale="vi")
    app.dependency_overrides[deps.db] = no_db
    app.dependency_overrides[deps.llm] = lambda: LLMClient(Settings(), fake)
    app.dependency_overrides[deps.clock] = lambda: datetime(2026, 11, 8, 11, 7, tzinfo=UTC)
    return TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS), fake, calls


def test_ok_matches_fixture_shape_and_sets_quota_headers(setup, caplog):
    client, fake, calls = setup
    caplog.set_level("DEBUG")
    r = client.post("/v1/parse", json=body(), headers={"Idempotency-Key": KEY})
    assert r.status_code == 200
    got = r.json()
    expected = json.loads((FIXTURES / "parse.sms.response.json").read_text(encoding="utf-8"))
    assert got["requestId"] == r.headers["X-Request-Id"]
    assert {k: v for k, v in got.items() if k != "requestId"} == {k: v for k, v in expected.items() if k != "requestId"}
    assert r.headers["X-Quota-Limit"] == "10" and r.headers["X-Quota-Remaining"] == "6"
    assert r.headers["X-Quota-Resets-At"] == "2026-11-09T00:00:00+07:00"
    assert calls == [{"endpoint": "/v1/parse", "units": 1, "key": KEY}]
    assert fake.calls[0]["model"] == "gpt-4o-mini"
    assert SECRET not in caplog.text and "anh Minh" not in caplog.text  # D-059


def test_missing_key_is_422_and_llm_not_called(setup):
    client, fake, calls = setup
    r = client.post("/v1/parse", json=body())
    assert r.status_code == 422 and r.json()["error"]["details"]["field"] == "Idempotency-Key"
    assert fake.calls == [] and calls == []


def test_invalid_body_never_reaches_metering(setup):
    client, fake, calls = setup
    r = client.post("/v1/parse", json=body(now="2026-11-08T18:07:00"), headers={"Idempotency-Key": KEY})
    assert r.status_code == 422 and r.json()["error"]["code"] == "invalid_input"
    assert calls == []


def test_text_too_long_is_413_before_metering(setup):
    client, fake, calls = setup
    r = client.post("/v1/parse", json=body(text="a" * 2001), headers={"Idempotency-Key": KEY})
    assert r.status_code == 413 and r.json()["error"]["details"] == {"maxChars": 2000}
    assert calls == []


def test_route_is_listed_in_openapi(setup):
    client, _, _ = setup
    assert "/v1/parse" in client.get("/openapi.json").json()["paths"]
