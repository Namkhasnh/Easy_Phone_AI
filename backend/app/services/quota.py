"""Plan + quota calculation, reserve, spend cap (API_CONTRACT §4.2–§4.5, D-085, D-087, D-231).

Called by `services/metering.py` inside the per-user advisory-lock transaction.
"""

from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta
from decimal import Decimal
from zoneinfo import ZoneInfo

import asyncpg

from app.config import Settings
from app.errors import AppError
from app.repositories import subscriptions, usage
from app.repositories.subscriptions import SubscriptionRow
from app.repositories.usage import UsageRow

PREMIUM_STATUSES = frozenset({"active", "inGracePeriod", "billingRetry"})


@dataclass(frozen=True)
class QuotaInfo:
    limit: int
    used: int
    remaining: int
    resets_at: datetime  # aware, in QUOTA_DAY_TZ


@dataclass(frozen=True)
class Entitlement:
    plan: str  # free | premium
    quota: QuotaInfo
    subscription: SubscriptionRow | None


def quota_day(now: datetime, tz_name: str) -> tuple[datetime, datetime]:
    """[start, end) of the calendar day containing `now` in `tz_name` (D-224). `end` = next local midnight."""
    tz = ZoneInfo(tz_name)
    local = now.astimezone(tz)
    start = datetime.combine(local.date(), time(0), tz)
    end = datetime.combine(local.date() + timedelta(days=1), time(0), tz)
    return start, end


def plan_for(subs: list[SubscriptionRow], now: datetime) -> str:
    """`premium` iff **a** row is active/grace/billing-retry **and** not expired (DATA_MODEL §9)."""
    for sub in subs:
        if sub.status in PREMIUM_STATUSES and sub.expires_at is not None and sub.expires_at > now:
            return "premium"
    return "free"


def limit_for(plan: str, settings: Settings) -> int:
    return settings.PREMIUM_DAILY_QUOTA if plan == "premium" else settings.FREE_DAILY_QUOTA


async def entitlement(conn: asyncpg.Connection, user_id: str, settings: Settings, now: datetime) -> Entitlement:
    subs = await subscriptions.for_user(conn, user_id)
    plan = plan_for(subs, now)
    start, end = quota_day(now, settings.QUOTA_DAY_TZ)
    used = await usage.units_between(conn, user_id, start, end)
    limit = limit_for(plan, settings)
    latest = subs[0] if subs else None  # API_CONTRACT §6.2: row with the latest `expires_at`
    return Entitlement(plan, QuotaInfo(limit, used, max(0, limit - used), end), latest)


def quota_json(q: QuotaInfo) -> dict:
    """API_CONTRACT §4.5 `Quota` object."""
    return {"limit": q.limit, "used": q.used, "remaining": q.remaining, "resetsAt": q.resets_at.isoformat()}


async def reserve(
    conn: asyncpg.Connection, user_id: str, row: UsageRow, units: int, settings: Settings, now: datetime
) -> QuotaInfo:
    """D-231 reserve: `used` (without this row) + `units` > limit → 402; else `row.units = units`.

    Must run inside the advisory-lock transaction. Returns the quota **after** this request (for `X-Quota-*`).
    """
    subs = await subscriptions.for_user(conn, user_id)
    plan = plan_for(subs, now)
    limit = limit_for(plan, settings)
    start, end = quota_day(now, settings.QUOTA_DAY_TZ)
    used_other = await usage.units_between_excluding(conn, user_id, start, end, row.id)
    if used_other + units > limit:
        q = QuotaInfo(limit, used_other, max(0, limit - used_other), end)
        raise AppError("quota_exceeded", 402, False, details={"plan": plan, "quota": quota_json(q)})
    await usage.set_units(conn, row.id, units)
    # TODO(spec): a retry whose row was created on the previous quota day re-charges that day, not today.
    used = used_other + (units if start <= row.created_at < end else 0)
    return QuotaInfo(limit, used, max(0, limit - used), end)


def month_utc(now: datetime) -> tuple[datetime, datetime]:
    """[start, end) of the current UTC calendar month (spend cap, API_CONTRACT §4.3)."""
    n = now.astimezone(UTC)
    start = datetime(n.year, n.month, 1, tzinfo=UTC)
    end = datetime(n.year + (n.month == 12), n.month % 12 + 1, 1, tzinfo=UTC)
    return start, end


async def check_spend_cap(conn: asyncpg.Connection, settings: Settings, now: datetime) -> None:
    """`sum(cost_usd)` this UTC month across all users ≥ `MONTHLY_SPEND_CAP_USD` → 503 `spend_cap` (D-087)."""
    start, end = month_utc(now)
    spent = await usage.cost_between(conn, start, end)
    if spent >= Decimal(str(settings.MONTHLY_SPEND_CAP_USD)):
        raise AppError("spend_cap", 503, False)
