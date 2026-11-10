"""1B.12a: `/v1/transcribe` rate limit + spend cap on Postgres (marker `db`, D-237, API_CONTRACT §4.3)."""

import json
import os
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from app import deps
from app.auth import CurrentUser
from app.config import Settings, get_settings
from app.main import create_app
from app.services.llm import LLMClient
from tests.test_llm import FakeCompletions
from tests.test_parse_db import sql
from tests.test_transcribe import APP_HEADERS, M4A, META, tr

pytestmark = pytest.mark.db
URL = os.environ.get("TEST_DATABASE_URL", "")
NOW = datetime(2026, 11, 8, 11, 7, tzinfo=UTC)


@pytest.fixture(autouse=True)
def needs_url():
    if not URL:
        pytest.skip("TEST_DATABASE_URL not set")


def client_for(uid, fake, now=NOW, **over):
    settings = Settings(DATABASE_URL=SecretStr(URL), TRANSCRIBE_PER_HOUR=2, **over)
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[deps.current_user] = lambda: CurrentUser(id=uid)
    app.dependency_overrides[deps.clock] = lambda: now
    app.dependency_overrides[deps.llm] = lambda: LLMClient(settings, FakeCompletions(), fake)
    return TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS)


def post(client):
    return client.post("/v1/transcribe", files={"audio": ("a.m4a", M4A, "audio/mp4")}, data={"meta": META})


def new_user():
    uid = str(uuid.uuid4())
    sql("insert into auth.users (id) values ($1::uuid)", uid)
    return uid


def test_rate_limit_429_with_retry_after_and_zero_unit_rows():
    uid = new_user()
    fake = FakeCompletions(tr(), tr(), tr())
    with client_for(uid, fake) as c:
        assert post(c).status_code == 200
    with client_for(uid, fake, now=NOW + timedelta(minutes=10)) as c:
        assert post(c).status_code == 200
        third = post(c)
    assert third.status_code == 429
    err = third.json()["error"]
    assert err["code"] == "rate_limited" and err["retryable"] is True
    assert err["details"] == {"retryAfterSeconds": 3000}  # first row ages out 50 min later
    assert third.headers["Retry-After"] == "3000"
    assert len(fake.calls) == 2
    rows = sql("select units, endpoint, idempotency_key, cost_usd from usage_events where user_id = $1::uuid", uid)
    assert [(r["units"], r["endpoint"], r["idempotency_key"]) for r in rows] == [(0, "/v1/transcribe", None)] * 2
    assert all(r["cost_usd"] > 0 for r in rows)  # counts toward the spend cap


def test_window_slides_after_an_hour():
    uid = new_user()
    fake = FakeCompletions(tr(), tr(), tr())
    with client_for(uid, fake) as c:
        post(c), post(c)
    with client_for(uid, fake, now=NOW + timedelta(hours=1)) as c:
        assert post(c).status_code == 200


def test_failed_call_still_counts_and_keeps_cost():
    uid = new_user()
    import openai
    from tests.test_llm import REQ
    fake = FakeCompletions(openai.APITimeoutError(request=REQ))
    with client_for(uid, fake) as c:
        r = post(c)
    assert r.status_code == 503 and r.json()["error"]["code"] == "upstream_error"
    assert len(sql("select 1 from usage_events where user_id = $1::uuid", uid)) == 1


def test_transcribe_does_not_use_daily_quota():
    uid = new_user()
    fake = FakeCompletions(tr())
    with client_for(uid, fake, FREE_DAILY_QUOTA=0) as c:  # no parse units left today
        assert post(c).status_code == 200


def test_spend_cap_blocks_before_the_call():
    uid = new_user()
    fake = FakeCompletions()
    with client_for(uid, fake, MONTHLY_SPEND_CAP_USD=0.0) as c:
        r = post(c)
    assert r.status_code == 503 and r.json()["error"]["code"] == "spend_cap"
    assert fake.calls == [] and sql("select 1 from usage_events where user_id = $1::uuid", uid) == []
