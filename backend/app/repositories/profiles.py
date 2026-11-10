"""SQL for `profiles` (DATA_MODEL §9). No business rules here."""

import asyncpg


async def upsert(conn: asyncpg.Connection, user_id: str, locale: str) -> str:
    """Create the row if missing (D-236) and return the stored locale. Existing rows are not changed.

    Raises `asyncpg.ForeignKeyViolationError` when `auth.users` has no such id (account deleted).
    """
    locale_now = await conn.fetchval(
        "insert into profiles (id, locale) values ($1::uuid, $2) on conflict (id) do nothing returning locale",
        user_id,
        locale,
    )
    if locale_now is not None:
        return locale_now
    return await conn.fetchval("select locale from profiles where id = $1::uuid", user_id)
