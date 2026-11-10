"""1B.5: `metered()` against a real Postgres with 0001_init.sql (marker `db`). The full quota suite is 1B.6.

Run with `sh migrations/checks/run_db_tests.sh` (Docker).
"""

import asyncio
import os
import uuid
from datetime import UTC, datetime, timedelta
from decimal import Decimal

import asyncpg
import pytest

from app.config import Settings
from app.errors import AppError
from app.repositories import profiles
from app.services.metering import Deadline, metered

pytestmark = pytest.mark.db

URL = os.environ.get("TEST_DATABASE_URL", "")
NOW = datetime(2026, 11, 9, 5, 0, tzinfo=UTC)  # 12:00 Vietnam
S = Settings(FREE_DAILY_QUOTA=2)


@pytest.fixture(autouse=True)
def needs_url():
    if not URL:
        pytest.skip("TEST_DATABASE_URL not set")


async def connect() -> asyncpg.Connection:
    return await asyncpg.connect(URL, statement_cache_size=0)


async def new_user(c: asyncpg.Connection) -> str:
    uid = str(uuid.uuid4())
    await c.execute("insert into auth.users (id) values ($1::uuid)", uid)
    await profiles.upsert(c, uid, "vi")
    return uid


def key() -> str:
    return str(uuid.uuid4())


async def ok(budget, meter):
    meter.add(10, 5, Decimal("0.001"))
    return "draft"


async def boom(budget, meter):
    meter.add(10, 0, Decimal("0.0005"))
    raise AppError("llm_invalid_output", 502, True)


async def call(c, uid, k, run=ok, endpoint="/v1/parse", now=NOW, settings=S, deadline=None):
    return await metered(c, settings, endpoint=endpoint, units=1, user_id=uid, key=k, now=now, run=run, deadline=deadline)


async def row(c, uid, k):
    return await c.fetchrow(
        "select units, attempt, tokens_in, cost_usd from usage_events where user_id = $1::uuid and idempotency_key = $2",
        uid, k,
    )


def test_same_key_is_charged_once_and_retry_at_limit_is_not_blocked():
    async def body():
        c = await connect()
        uid, k = await new_user(c), key()
        first = await call(c, uid, k)
        assert first.result == "draft" and first.quota.used == 1 and first.quota.remaining == 1
        await call(c, uid, key())  # 2/2 used
        again = await call(c, uid, k)  # retry of the first call at the limit: allowed, still 2 used
        assert again.quota.used == 2
        r = await row(c, uid, k)
        assert (r["units"], r["attempt"], r["tokens_in"]) == (1, 2, 20)  # cost added on every attempt
        await c.close()

    asyncio.run(body())


def test_402_at_limit_leaves_no_row():
    async def body():
        c = await connect()
        uid = await new_user(c)
        await call(c, uid, key())
        await call(c, uid, key())
        k = key()
        with pytest.raises(AppError) as e:
            await call(c, uid, k)
        assert e.value.http_status == 402 and e.value.details["quota"]["remaining"] == 0
        assert e.value.details["plan"] == "free"
        assert await row(c, uid, k) is None
        await c.close()

    asyncio.run(body())


def test_error_refunds_but_keeps_cost():
    async def body():
        c = await connect()
        uid, k = await new_user(c), key()
        with pytest.raises(AppError):
            await call(c, uid, k, run=boom)
        r = await row(c, uid, k)
        assert r["units"] == 0 and r["cost_usd"] == Decimal("0.0005")
        await call(c, uid, k)  # retry succeeds → charged
        assert (await row(c, uid, k))["units"] == 1
        await c.close()

    asyncio.run(body())


def test_unexpected_exception_refunds():
    async def crash(budget, meter):
        raise ValueError("x")

    async def body():
        c = await connect()
        uid, k = await new_user(c), key()
        with pytest.raises(ValueError):
            await call(c, uid, k, run=crash)
        assert (await row(c, uid, k))["units"] == 0
        await c.close()

    asyncio.run(body())


def test_key_on_other_endpoint_or_expired_is_422():
    async def body():
        c = await connect()
        uid, k = await new_user(c), key()
        await call(c, uid, k)
        with pytest.raises(AppError) as e:
            await call(c, uid, k, endpoint="/v1/extract")
        assert e.value.details["reason"] == "idempotencyKeyEndpointMismatch"
        with pytest.raises(AppError) as e:
            await call(c, uid, k, now=NOW + timedelta(hours=24))
        assert e.value.details["reason"] == "idempotencyKeyExpired"
        assert (await row(c, uid, k))["attempt"] == 1  # rejected attempts roll back
        await c.close()

    asyncio.run(body())


def test_late_older_attempt_cannot_refund_newer_success():
    async def body():
        c1, c2 = await connect(), await connect()
        uid, k = await new_user(c1), key()
        started, release = asyncio.Event(), asyncio.Event()

        async def slow_fail(budget, meter):
            started.set()
            await release.wait()
            raise AppError("upstream_error", 503, True)

        old = asyncio.create_task(call(c1, uid, k, run=slow_fail))
        await started.wait()
        await call(c2, uid, k)  # attempt 2 succeeds
        release.set()
        with pytest.raises(AppError):
            await old
        r = await row(c1, uid, k)
        assert (r["units"], r["attempt"]) == (1, 2)
        await c1.close()
        await c2.close()

    asyncio.run(body())


def test_budget_exhausted_is_503_and_refunds():
    async def hang(budget, meter):
        await asyncio.sleep(5)

    async def body():
        c = await connect()
        uid, k = await new_user(c), key()
        with pytest.raises(AppError) as e:
            await call(c, uid, k, run=hang, deadline=Deadline(0.2))
        assert e.value.code == "upstream_error" and e.value.http_status == 503
        assert (await row(c, uid, k))["units"] == 0
        await c.close()

    asyncio.run(body())


def test_spend_cap_blocks_before_run():
    async def never(budget, meter):
        raise AssertionError("LLM must not run")

    async def body():
        c = await connect()
        uid = await new_user(c)
        spent = await c.fetchval(
            "select coalesce(sum(cost_usd), 0) from usage_events where created_at >= '2026-11-01' and created_at < '2026-12-01'"
        )
        capped = Settings(MONTHLY_SPEND_CAP_USD=float(spent))  # already reached
        k = key()
        with pytest.raises(AppError) as e:
            await call(c, uid, k, run=never, settings=capped)
        assert e.value.code == "spend_cap" and e.value.http_status == 503 and not e.value.retryable
        assert await row(c, uid, k) is None
        await c.close()

    asyncio.run(body())


def test_parallel_new_keys_cannot_exceed_limit():
    async def body():
        conns = [await connect() for _ in range(4)]
        uid = await new_user(conns[0])
        results = await asyncio.gather(*(call(c, uid, key()) for c in conns), return_exceptions=True)
        assert sum(not isinstance(r, Exception) for r in results) == 2
        assert all(r.http_status == 402 for r in results if isinstance(r, AppError))
        for c in conns:
            await c.close()

    asyncio.run(body())


# ---- 1B.6: rest of the API_CONTRACT §11 quota suite ----

LOCAL_2359 = datetime(2026, 11, 9, 16, 59, 59, tzinfo=UTC)  # 23:59:59 Asia/Ho_Chi_Minh
LOCAL_0000 = datetime(2026, 11, 9, 17, 0, 0, tzinfo=UTC)  # 00:00:00 next local day


def test_day_boundary_at_local_midnight():
    async def body():
        c = await connect()
        uid = await new_user(c)
        await call(c, uid, key(), now=LOCAL_2359)
        last = await call(c, uid, key(), now=LOCAL_2359)
        assert last.quota.remaining == 0 and last.quota.resets_at.isoformat() == "2026-11-10T00:00:00+07:00"
        with pytest.raises(AppError):
            await call(c, uid, key(), now=LOCAL_2359)
        fresh = await call(c, uid, key(), now=LOCAL_0000)  # new local day: limit is back
        assert (fresh.quota.used, fresh.quota.remaining) == (1, 1)
        assert fresh.quota.resets_at.isoformat() == "2026-11-11T00:00:00+07:00"
        await c.close()

    asyncio.run(body())


async def make_premium(c, uid, expires):
    await c.execute(
        "insert into subscriptions (user_id, product_id, original_transaction_id, expires_at, status, environment)"
        " values ($1::uuid, 'easyphone.premium.monthly', $2, $3, 'active', 'Xcode')",
        uid, f"tx-{uid}", expires,
    )


def test_premium_limit_applies_immediately_and_used_is_kept():
    settings = Settings(FREE_DAILY_QUOTA=2, PREMIUM_DAILY_QUOTA=3)

    async def body():
        c = await connect()
        uid = await new_user(c)
        await call(c, uid, key(), settings=settings)
        await call(c, uid, key(), settings=settings)
        with pytest.raises(AppError) as e:
            await call(c, uid, key(), settings=settings)
        assert e.value.details["plan"] == "free"
        await make_premium(c, uid, NOW + timedelta(days=30))  # = what billing verify writes (1F)
        up = await call(c, uid, key(), settings=settings)
        assert (up.quota.limit, up.quota.used, up.quota.remaining) == (3, 3, 0)
        with pytest.raises(AppError) as e:
            await call(c, uid, key(), settings=settings)
        assert e.value.details["plan"] == "premium" and e.value.details["quota"]["limit"] == 3
        await c.close()

    asyncio.run(body())


def test_expired_premium_is_free_limit():
    async def body():
        c = await connect()
        uid = await new_user(c)
        await make_premium(c, uid, NOW - timedelta(seconds=1))
        got = await call(c, uid, key(), settings=Settings(FREE_DAILY_QUOTA=2, PREMIUM_DAILY_QUOTA=3))
        assert got.quota.limit == 2
        await c.close()

    asyncio.run(body())


def test_last_attempt_fails_means_zero_units_even_if_older_succeeds_late():
    async def body():
        c1, c2 = await connect(), await connect()
        uid, k = await new_user(c1), key()
        started, release = asyncio.Event(), asyncio.Event()

        async def slow_ok(budget, meter):
            started.set()
            await release.wait()
            meter.add(1, 1, Decimal("0.0001"))
            return "late"

        old = asyncio.create_task(call(c1, uid, k, run=slow_ok))
        await started.wait()
        with pytest.raises(AppError):
            await call(c2, uid, k, run=boom)  # attempt 2 (latest) fails → refund
        release.set()
        assert (await old).result == "late"
        r = await row(c1, uid, k)
        assert (r["units"], r["attempt"]) == (0, 2)  # charged only if the LAST attempt was 2xx (§4.4)
        assert r["cost_usd"] == Decimal("0.0006")  # both attempts' cost counted
        await c1.close()
        await c2.close()

    asyncio.run(body())


def test_parallel_same_key_is_charged_once():
    async def body():
        conns = [await connect() for _ in range(3)]
        uid, k = await new_user(conns[0]), key()
        await asyncio.gather(*(call(c, uid, k) for c in conns))
        r = await row(conns[0], uid, k)
        assert (r["units"], r["attempt"]) == (1, 3)
        total = await conns[0].fetchval("select sum(units) from usage_events where user_id = $1::uuid", uid)
        assert total == 1
        for c in conns:
            await c.close()

    asyncio.run(body())


def test_me_reflects_metered_usage():
    from tests.test_db import make_client

    async def body():
        c = await connect()
        uid = await new_user(c)
        await call(c, uid, key(), settings=Settings())
        with pytest.raises(AppError):
            await call(c, uid, key(), run=boom, settings=Settings())  # refunded: not counted
        await c.close()
        return uid

    uid = asyncio.run(body())
    with make_client(uid) as client:
        resp = client.get("/v1/me")
    assert resp.json()["quota"]["used"] == 1
    assert resp.headers["X-Quota-Remaining"] == "9" and resp.headers["X-Quota-Limit"] == "10"
