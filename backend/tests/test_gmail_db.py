"""2.2: `gmail_accounts` repository against a real Postgres with 0001 + 0002 (marker `db`, API_GMAIL.md §7).

Run with `sh migrations/checks/run_db_tests.sh` (Docker). Excluded from the default suite.
"""

import asyncio
import os
import uuid

import asyncpg
import pytest

from app.repositories import gmail_accounts as repo

pytestmark = pytest.mark.db

URL = os.environ.get("TEST_DATABASE_URL", "")
A = "gma_01JD0000000000000000000000"
B = "gma_01JD0000000000000000000001"


async def scenario() -> None:
    conn = await asyncpg.connect(URL, statement_cache_size=0)
    try:
        uid = str(uuid.uuid4())
        await conn.execute("insert into auth.users (id) values ($1::uuid)", uid)
        await conn.execute("insert into profiles (id) values ($1::uuid)", uid)

        assert await repo.for_user(conn, uid) == []
        assert await repo.upsert(conn, uid, A, "k@gmail.com", b"enc-1", ["s1"]) == A
        await repo.set_status(conn, uid, A, "needsReconnect")
        # same email again: same id, new token, connected again
        assert await repo.upsert(conn, uid, B, "k@gmail.com", b"enc-2", ["s1", "s2"]) == A
        rows = await repo.for_user(conn, uid)
        assert rows == [repo.GmailAccountRow(A, "k@gmail.com", "connected", b"enc-2")]

        other = str(uuid.uuid4())
        await conn.execute("insert into auth.users (id) values ($1::uuid)", other)
        await conn.execute("insert into profiles (id) values ($1::uuid)", other)
        assert await repo.delete(conn, other, A) is None  # not theirs
        assert await repo.delete(conn, uid, A) == b"enc-2"
        assert await repo.delete(conn, uid, A) is None
        assert await repo.for_user(conn, uid) == []
    finally:
        await conn.close()


def test_repository_round_trip():
    asyncio.run(scenario())
