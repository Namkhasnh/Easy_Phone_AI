"""Plan + quota calculation (API_CONTRACT §4.2, §4.5, D-085). Reserve/commit/refund come in 1B.5."""

from dataclasses import dataclass
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

import asyncpg

from app.config import Settings
from app.repositories import subscriptions, usage
from app.repositories.subscriptions import SubscriptionRow

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
