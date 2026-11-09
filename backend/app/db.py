"""asyncpg pool for the Supabase Postgres database (D-261, ARCHITECTURE §7.1).

The pool is created lazily on first use, so `/v1/health` and app start-up never need the database.
Never log the connection string (D-207) or row contents (D-059).
"""

import asyncio
import logging

import asyncpg

from app.config import Settings
from app.errors import AppError

logger = logging.getLogger("easyphone.db")


class Database:
    def __init__(self) -> None:
        self._pool: asyncpg.Pool | None = None
        self._lock = asyncio.Lock()

    async def pool(self, settings: Settings) -> asyncpg.Pool:
        if self._pool is not None:
            return self._pool
        async with self._lock:
            if self._pool is None:
                if settings.DATABASE_URL is None:
                    logger.error("db misconfigured: DATABASE_URL missing")
                    raise AppError("internal", 500, True)
                try:
                    self._pool = await asyncpg.create_pool(
                        settings.DATABASE_URL.get_secret_value(),
                        min_size=0,
                        max_size=settings.DB_POOL_MAX_SIZE,
                        # Supabase poolers (pgbouncer) do not support prepared-statement caching.
                        statement_cache_size=0,
                        timeout=settings.DB_CONNECT_TIMEOUT_SECONDS,
                    )
                except (OSError, asyncio.TimeoutError, asyncpg.PostgresError) as exc:
                    logger.error("db connect failed: %s", type(exc).__name__)
                    raise AppError("internal", 500, True) from None
        return self._pool

    async def close(self) -> None:
        if self._pool is not None:
            await self._pool.close()
            self._pool = None
