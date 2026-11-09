"""0.15: plan + quota day rules (API_CONTRACT §4.2, §4.5, D-224). Pure functions, no DB."""

from datetime import UTC, datetime, timedelta

from app.config import Settings
from app.repositories.subscriptions import SubscriptionRow
from app.services.quota import limit_for, plan_for, quota_day

TZ = "Asia/Ho_Chi_Minh"
NOW = datetime(2026, 11, 9, 5, 0, tzinfo=UTC)  # 12:00 in Vietnam


def sub(status="active", expires_in=timedelta(days=10)) -> SubscriptionRow:
    exp = NOW + expires_in if expires_in is not None else None
    return SubscriptionRow("easyphone.premium.monthly", status, exp, "Xcode")


def test_quota_day_is_local_calendar_day():
    start, end = quota_day(NOW, TZ)
    assert start.isoformat() == "2026-11-09T00:00:00+07:00"
    assert end.isoformat() == "2026-11-10T00:00:00+07:00"


def test_quota_day_boundary_just_before_and_at_local_midnight():
    before = datetime(2026, 11, 9, 16, 59, 59, tzinfo=UTC)  # 23:59:59 local
    at = datetime(2026, 11, 9, 17, 0, 0, tzinfo=UTC)  # 00:00:00 local, next day
    assert quota_day(before, TZ)[1].isoformat() == "2026-11-10T00:00:00+07:00"
    assert quota_day(at, TZ)[0].isoformat() == "2026-11-10T00:00:00+07:00"
    assert quota_day(at, TZ)[1].isoformat() == "2026-11-11T00:00:00+07:00"


def test_plan_free_without_subscription():
    assert plan_for([], NOW) == "free"


def test_plan_premium_statuses_when_not_expired():
    for status in ("active", "inGracePeriod", "billingRetry"):
        assert plan_for([sub(status)], NOW) == "premium"


def test_plan_free_for_other_statuses():
    for status in ("expired", "revoked", "refunded"):
        assert plan_for([sub(status)], NOW) == "free"


def test_plan_free_when_expired_or_no_expiry():
    assert plan_for([sub(expires_in=-timedelta(seconds=1))], NOW) == "free"
    assert plan_for([sub(expires_in=timedelta(0))], NOW) == "free"  # expires_at > now, strictly
    assert plan_for([sub(expires_in=None)], NOW) == "free"


def test_plan_premium_if_any_row_qualifies():
    rows = [sub("revoked", timedelta(days=300)), sub("active", timedelta(days=5))]
    assert plan_for(rows, NOW) == "premium"


def test_limits_come_from_config():
    s = Settings(FREE_DAILY_QUOTA=3, PREMIUM_DAILY_QUOTA=99)
    assert limit_for("free", s) == 3
    assert limit_for("premium", s) == 99
