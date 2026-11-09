"""0.15: repositories + `GET /v1/me` against a real Postgres with 0001_init.sql (marker `db`).

Run with `sh migrations/checks/run_db_tests.sh` (Docker). Excluded from the default suite.
"""

import asyncio
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
from app.repositories import profiles, subscriptions, usage

pytestmark = pytest.mark.db

URL = os.environ.get("TEST_DATABASE_URL", "")
NOW = datetime(2026, 11, 9, 5, 0, tzinfo=UTC)  # 12:00 Vietnam


def run(coro):
    return asyncio.run(coro)


async def with_conn(fn):
    conn = await asyncpg.connect(URL, statement_cache_size=0)
    try:
        return await fn(conn)
    finally:
        await conn.close()


@pytest.fixture
def uid() -> str:
    """A fresh auth user (no profile yet)."""
    user_id = str(uuid.uuid4())
    run(with_conn(lambda c: c.execute("insert into auth.users (id) values ($1::uuid)", user_id)))
    return user_id


@pytest.fixture(autouse=True)
def needs_url():
    if not URL:
        pytest.skip("TEST_DATABASE_URL not set")


def test_upsert_creates_once_and_keeps_locale(uid):
    async def body(c):
        assert await profiles.upsert(c, uid, "en") == "en"
        assert await profiles.upsert(c, uid, "vi") == "en"
        return await c.fetchval("select count(*) from profiles where id = $1::uuid", uid)

    assert run(with_conn(body)) == 1


def test_upsert_missing_auth_user_raises_fk():
    with pytest.raises(asyncpg.ForeignKeyViolationError):
        run(with_conn(lambda c: profiles.upsert(c, str(uuid.uuid4()), "vi")))


def test_subscriptions_latest_first_nulls_last(uid):
    async def body(c):
        await profiles.upsert(c, uid, "vi")
        rows = [("tx1", None, "expired"), ("tx2", "2026-12-01T00:00:00Z", "active"), ("tx3", "2026-01-01T00:00:00Z", "expired")]
        for tx, exp, status in rows:
            await c.execute(
                "insert into subscriptions (user_id, product_id, original_transaction_id, expires_at, status, environment)"
                " values ($1::uuid, 'easyphone.premium.monthly', $2, $3, $4, 'Xcode')",
                uid, f"{uid}-{tx}", datetime.fromisoformat(exp) if exp else None, status,
            )
        return await subscriptions.for_user(c, uid)

    got = run(with_conn(body))
    assert [s.status for s in got] == ["active", "expired", "expired"]
    assert got[0].expires_at == datetime(2026, 12, 1, tzinfo=UTC) and got[-1].expires_at is None


def test_usage_sum_is_half_open_window_and_per_user(uid):
    async def body(c):
        await profiles.upsert(c, uid, "vi")
        for created, units in [
            ("2026-11-08T16:59:59Z", 5),  # 23:59:59 local, previous day
            ("2026-11-08T17:00:00Z", 1),  # 00:00 local: counts
            ("2026-11-09T10:00:00Z", 2),
            ("2026-11-09T11:00:00Z", 0),  # refunded
            ("2026-11-09T17:00:00Z", 7),  # next local midnight: excluded
        ]:
            await c.execute(
                "insert into usage_events (user_id, endpoint, units, created_at) values ($1::uuid, '/v1/parse', $2, $3)",
                uid, units, datetime.fromisoformat(created),
            )
        start = datetime.fromisoformat("2026-11-09T00:00:00+07:00")
        end = datetime.fromisoformat("2026-11-10T00:00:00+07:00")
        return await usage.units_between(c, uid, start, end), await usage.units_between(c, str(uuid.uuid4()), start, end)

    assert run(with_conn(body)) == (3, 0)


def make_client(user_id: str) -> TestClient:
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(DATABASE_URL=SecretStr(URL))
    app.dependency_overrides[deps.current_user] = lambda: CurrentUser(id=user_id)
    app.dependency_overrides[deps.clock] = lambda: NOW
    return TestClient(app, raise_server_exceptions=False)


def test_me_end_to_end_creates_profile(uid):
    with make_client(uid) as client:  # `with` runs lifespan → pool closed at the end
        resp = client.get("/v1/me", headers={"Accept-Language": "en"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["userId"] == uid and body["locale"] == "en" and body["plan"] == "free"
    assert body["quota"] == {"limit": 10, "used": 0, "remaining": 10, "resetsAt": "2026-11-10T00:00:00+07:00"}
    assert run(with_conn(lambda c: c.fetchval("select locale from profiles where id = $1::uuid", uid))) == "en"


def test_me_end_to_end_deleted_auth_user_is_401():
    with make_client(str(uuid.uuid4())) as client:
        resp = client.get("/v1/me")
    assert resp.status_code == 401 and resp.json()["error"]["code"] == "unauthorized"
