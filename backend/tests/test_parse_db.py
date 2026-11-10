"""1B.10: `POST /v1/parse` end to end on Postgres (marker `db`): auth fake, real metering, fake OpenAI."""

import json
import os
import uuid
from datetime import UTC, datetime

import asyncpg
import pytest
from fastapi.testclient import TestClient
from pydantic import SecretStr

from app import deps
from app.auth import CurrentUser
from app.config import Settings, get_settings
from app.main import create_app
from app.services.llm import LLMClient
from tests.test_llm import FakeCompletions, resp
from tests.test_parse_route import LLM_SMS, body

APP_HEADERS = {"X-Client-Version": "1.0(1)"}  # what the app sends today (MARKETING_VERSION 1.0)

pytestmark = pytest.mark.db
URL = os.environ.get("TEST_DATABASE_URL", "")
NOW = datetime(2026, 11, 8, 11, 7, tzinfo=UTC)


@pytest.fixture(autouse=True)
def needs_url():
    if not URL:
        pytest.skip("TEST_DATABASE_URL not set")


def sql(query, *args):
    import asyncio

    async def go():
        c = await asyncpg.connect(URL, statement_cache_size=0)
        try:
            return await c.fetch(query, *args)
        finally:
            await c.close()

    return asyncio.run(go())


def client_for(uid, fake):
    settings = Settings(DATABASE_URL=SecretStr(URL), FREE_DAILY_QUOTA=1)
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings
    app.dependency_overrides[deps.current_user] = lambda: CurrentUser(id=uid)
    app.dependency_overrides[deps.clock] = lambda: NOW
    app.dependency_overrides[deps.llm] = lambda: LLMClient(settings, fake)
    return TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS)


def test_parse_charges_once_records_cost_and_402_after_limit():
    uid, key = str(uuid.uuid4()), str(uuid.uuid4())
    sql("insert into auth.users (id) values ($1::uuid)", uid)
    ok = resp(json.dumps(LLM_SMS, ensure_ascii=False))
    fake = FakeCompletions(ok, ok)
    with client_for(uid, fake) as client:
        first = client.post("/v1/parse", json=body(), headers={"Idempotency-Key": key})
        retry = client.post("/v1/parse", json=body(), headers={"Idempotency-Key": key})  # same call retried
        other = client.post("/v1/parse", json=body(), headers={"Idempotency-Key": str(uuid.uuid4())})
    assert first.status_code == 200 and retry.status_code == 200
    assert first.headers["X-Quota-Remaining"] == "0" and retry.headers["X-Quota-Remaining"] == "0"
    assert other.status_code == 402 and other.json()["error"]["details"]["plan"] == "free"
    rows = sql("select units, attempt, tokens_in, cost_usd from usage_events where user_id = $1::uuid", uid)
    assert [(r["units"], r["attempt"], r["tokens_in"]) for r in rows] == [(1, 2, 2000)]
    assert len(fake.calls) == 2  # the 402 never called OpenAI


def test_llm_invalid_twice_is_502_and_refunded():
    uid, key = str(uuid.uuid4()), str(uuid.uuid4())
    sql("insert into auth.users (id) values ($1::uuid)", uid)
    fake = FakeCompletions(resp("{}"), resp("{}"))
    with client_for(uid, fake) as client:
        r = client.post("/v1/parse", json=body(), headers={"Idempotency-Key": key})
    assert r.status_code == 502 and r.json()["error"]["code"] == "llm_invalid_output"
    rows = sql("select units, tokens_in from usage_events where user_id = $1::uuid", uid)
    assert [(x["units"], x["tokens_in"]) for x in rows] == [(0, 2000)]  # refund, cost kept for the spend cap
