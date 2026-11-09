"""0.11: config defaults match the documented DEFAULTs (D-091, D-232, D-246, D-262, D-285, D-237)."""

from app.config import Settings


def test_defaults(monkeypatch):
    s = Settings(_env_file=None)
    assert (s.FREE_DAILY_QUOTA, s.PREMIUM_DAILY_QUOTA) == (10, 200)
    assert (s.REQUEST_BUDGET_SECONDS, s.LLM_TIMEOUT_SECONDS) == (18, 12)
    assert s.MONTHLY_SPEND_CAP_USD == 5
    assert s.TRANSCRIBE_PER_HOUR == 30
    assert s.QUOTA_DAY_TZ == "Asia/Ho_Chi_Minh"
    assert s.ALLOW_XCODE_STOREKIT is False
    assert not {"emailReply", "ride", "food"} & set(s.ENABLED_KINDS)  # D-150
    assert s.OPENAI_API_KEY is None


def test_env_overrides(monkeypatch):
    monkeypatch.setenv("FREE_DAILY_QUOTA", "3")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.setenv("ENABLED_KINDS", '["reminder"]')
    s = Settings(_env_file=None)
    assert s.FREE_DAILY_QUOTA == 3
    assert s.ENABLED_KINDS == ["reminder"]
    assert s.OPENAI_API_KEY.get_secret_value() == "sk-test"
    assert "sk-test" not in repr(s)
