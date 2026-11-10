"""1B.12a: `/v1/transcribe` without a DB (API_CONTRACT §7.4, D-237, D-238). Real metering: test_transcribe_db.py."""

import asyncio
import json
import math
from datetime import UTC, datetime
from decimal import Decimal
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app import deps
from app.config import Settings
from app.errors import AppError
from app.main import create_app
from app.routers import media as media_router
from app.services import transcribe_service as ts
from app.services.llm import AudioUpload, LLMClient
from app.services.metering import CostMeter, Deadline
from tests.test_llm import REQ, FakeCompletions, status_error

import openai

APP_HEADERS = {"X-Client-Version": "1.0(1)"}
M4A = b"\x00\x00\x00\x20ftypM4A \x00\x00\x00\x00" + b"\x00" * 100  # minimal MP4 header
ADTS = bytes([0xFF, 0xF1, 0x50, 0x80, 0x02, 0x1F, 0xFC]) + b"\x00" * 50
META = json.dumps({"schemaVersion": 1, "locale": "vi-VN"})
SECRET = "nhắn anh minh là chiều nay em đến muộn"


def tr(text=SECRET, logprobs=(-0.1, -0.3), usage="tokens"):
    u = None
    if usage == "tokens":
        u = SimpleNamespace(type="tokens", input_tokens=500, output_tokens=20)
    elif usage == "duration":
        u = SimpleNamespace(type="duration", seconds=30)
    lps = [SimpleNamespace(token="t", bytes=[], logprob=v) for v in logprobs] if logprobs is not None else None
    return SimpleNamespace(text=text, logprobs=lps, usage=u)


def run_llm(fake, meter=None, budget=None):
    client = LLMClient(Settings(), FakeCompletions(), fake)
    upload = AudioUpload(M4A, "audio.m4a", "audio/mp4", "vi")
    return asyncio.run(client.transcribe(upload, budget or Deadline(18), meter or CostMeter()))


# ---- LLMClient.transcribe ----

def test_sends_model_language_logprobs_and_timeout():
    fake = FakeCompletions(tr())
    out = run_llm(fake)
    kw = fake.calls[0]
    assert kw["model"] == "gpt-4o-mini-transcribe" and kw["language"] == "vi" and kw["include"] == ["logprobs"]
    assert kw["file"] == ("audio.m4a", M4A, "audio/mp4") and kw["timeout"] == 12
    assert out.text == SECRET
    assert out.confidence == round(math.exp(-0.2), 2)


def test_no_logprobs_means_null_confidence():
    assert run_llm(FakeCompletions(tr(logprobs=None))).confidence is None  # D-238


@pytest.mark.parametrize("usage,expected", [
    ("tokens", Decimal("0.000725")),     # 500 × 1.25 + 20 × 5.00 per 1M
    ("duration", Decimal("0.003000")),   # 30 s × 0.006 / min
    (None, Decimal("0.006000")),         # no usage → assume 60 s (spend cap never undercounts)
])
def test_cost_recorded(usage, expected):
    meter = CostMeter()
    run_llm(FakeCompletions(tr(usage=usage)), meter=meter)
    assert meter.cost_usd == expected


@pytest.mark.parametrize("exc,code", [
    (openai.APITimeoutError(request=REQ), "upstream_error"),
    (status_error(openai.RateLimitError, 429), "upstream_error"),
    (status_error(openai.BadRequestError, 400), "internal"),
])
def test_sdk_errors_mapped(exc, code):
    with pytest.raises(AppError) as e:
        run_llm(FakeCompletions(exc))
    assert e.value.code == code


def test_logs_never_contain_the_transcript(caplog):
    caplog.set_level("DEBUG")
    run_llm(FakeCompletions(tr()))
    assert "prompt=transcribe" in caplog.text and SECRET not in caplog.text


# ---- validation ----

def test_audio_checks():
    s = Settings()
    ts.check_audio(M4A, s)
    ts.check_audio(ADTS, s)
    for data, status in [(b"", 422), (b"RIFF....WAVEfmt " + b"\x00" * 20, 422), (M4A + b"\x00" * s.TRANSCRIBE_MAX_BYTES, 413)]:
        with pytest.raises(AppError) as e:
            ts.check_audio(data, s)
        assert e.value.http_status == status
    with pytest.raises(AppError) as e:
        ts.check_audio(M4A + b"\x00" * s.TRANSCRIBE_MAX_BYTES, s)
    assert e.value.details == {"maxBytes": 2 * 1024 * 1024}


@pytest.mark.parametrize("raw", ["", "{", '{"schemaVersion": 2, "locale": "vi-VN"}', '{"schemaVersion": 1}',
                                 '{"schemaVersion": 1, "locale": "vi-VN", "x": 1}'])
def test_bad_meta_is_422(raw):
    with pytest.raises(AppError) as e:
        ts.parse_meta(raw)
    assert e.value.details == {"field": "meta", "reason": "invalid"}


# ---- route (rate_limited faked) ----

@pytest.fixture
def route(monkeypatch):
    fake = FakeCompletions(tr())
    calls = []

    async def fake_rate_limited(conn, settings, *, endpoint, per_hour, user_id, now, run, deadline=None):
        calls.append({"endpoint": endpoint, "per_hour": per_hour})
        return await run(Deadline(18), CostMeter())

    monkeypatch.setattr(media_router, "rate_limited", fake_rate_limited)
    app = create_app()

    async def no_db():
        yield None

    app.dependency_overrides[deps.authed_user] = lambda: deps.AuthedUser(id="u1", locale="vi")
    app.dependency_overrides[deps.db] = no_db
    app.dependency_overrides[deps.llm] = lambda: LLMClient(Settings(), FakeCompletions(), fake)
    app.dependency_overrides[deps.clock] = lambda: datetime(2026, 11, 8, 11, 7, tzinfo=UTC)
    return TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS), calls


def post(client, audio=M4A, meta=META):
    files = {"audio": ("speech.m4a", audio, "audio/mp4")} if audio is not None else {}
    data = {"meta": meta} if meta is not None else {}
    return client.post("/v1/transcribe", files=files, data=data)


def test_ok(route):
    client, calls = route
    r = post(client)
    assert r.status_code == 200
    body = r.json()
    assert body["text"] == SECRET and body["schemaVersion"] == 1 and body["requestId"] == r.headers["X-Request-Id"]
    assert 0 <= body["confidence"] <= 1
    assert calls == [{"endpoint": "/v1/transcribe", "per_hour": 30}]
    assert "X-Quota-Limit" not in r.headers  # 0 units: not a metered endpoint


@pytest.mark.parametrize("audio,meta,status", [
    (None, META, 422), (M4A, None, 422), (b"not audio at all", META, 422), (M4A, "{}", 422),
    (M4A + b"\x00" * (2 * 1024 * 1024), META, 413),
])
def test_bad_upload_never_reaches_rate_limit(route, audio, meta, status):
    client, calls = route
    assert post(client, audio, meta).status_code == status
    assert calls == []


def test_listed_in_openapi(route):
    client, _ = route
    assert "/v1/transcribe" in client.get("/openapi.json").json()["paths"]
