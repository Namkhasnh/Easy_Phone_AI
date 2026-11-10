"""0.15: `GET /v1/me` + profile upsert (API_CONTRACT §2, §6.2, D-236). Repositories faked; no DB."""

from datetime import UTC, datetime, timedelta

import asyncpg
import pytest
from fastapi.testclient import TestClient

from app import deps
from app.auth import CurrentUser
from app.config import Settings, get_settings
from app.main import create_app
from app.repositories import profiles, subscriptions, usage
from app.repositories.subscriptions import SubscriptionRow

APP_HEADERS = {"X-Client-Version": "1.0(1)"}  # what the app sends today (MARKETING_VERSION 1.0)

UID = "6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11"
NOW = datetime(2026, 11, 9, 5, 0, tzinfo=UTC)  # 12:00 Vietnam


class FakeStore:
    def __init__(self) -> None:
        self.profiles: dict[str, str] = {}
        self.auth_users = {UID}
        self.subs: list[SubscriptionRow] = []
        self.used = 0
        self.window: tuple[datetime, datetime] | None = None

    async def upsert(self, conn, user_id, locale):
        if user_id not in self.auth_users:
            raise asyncpg.ForeignKeyViolationError("fk")
        return self.profiles.setdefault(user_id, locale)

    async def for_user(self, conn, user_id):
        return list(self.subs)

    async def units_between(self, conn, user_id, start, end):
        self.window = (start, end)
        return self.used


@pytest.fixture
def store(monkeypatch) -> FakeStore:
    s = FakeStore()
    monkeypatch.setattr(profiles, "upsert", s.upsert)
    monkeypatch.setattr(subscriptions, "for_user", s.for_user)
    monkeypatch.setattr(usage, "units_between", s.units_between)
    return s


async def fake_db():
    yield object()


def make_client(user_id: str = UID, **settings) -> TestClient:
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(**settings)
    app.dependency_overrides[deps.current_user] = lambda: CurrentUser(id=user_id)
    app.dependency_overrides[deps.db] = fake_db
    app.dependency_overrides[deps.clock] = lambda: NOW
    return TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS)


def test_me_free_user_body_and_headers(store):
    store.used = 3
    resp = make_client().get("/v1/me")
    assert resp.status_code == 200
    assert resp.json() == {
        "schemaVersion": 1,
        "userId": UID,
        "locale": "vi",
        "plan": "free",
        "quota": {"limit": 10, "used": 3, "remaining": 7, "resetsAt": "2026-11-10T00:00:00+07:00"},
        "subscription": None,
    }
    assert resp.headers["X-Quota-Limit"] == "10"
    assert resp.headers["X-Quota-Remaining"] == "7"
    assert resp.headers["X-Quota-Resets-At"] == "2026-11-10T00:00:00+07:00"
    assert resp.headers["X-Request-Id"].startswith("req_")
    start, end = store.window
    assert (start.isoformat(), end.isoformat()) == ("2026-11-09T00:00:00+07:00", "2026-11-10T00:00:00+07:00")


def test_me_premium_shows_latest_subscription_in_local_offset(store):
    store.subs = [
        SubscriptionRow("easyphone.premium.yearly", "active", NOW + timedelta(days=30, microseconds=5), "Xcode"),
        SubscriptionRow("easyphone.premium.monthly", "expired", NOW - timedelta(days=1), "Xcode"),
    ]
    body = make_client().get("/v1/me").json()
    assert body["plan"] == "premium"
    assert body["quota"]["limit"] == 200
    assert body["subscription"] == {
        "productId": "easyphone.premium.yearly",
        "status": "active",
        "expiresAt": "2026-12-09T12:00:00+07:00",
        "environment": "Xcode",
    }


def test_me_expired_subscription_is_free_but_still_listed(store):
    store.subs = [SubscriptionRow("easyphone.premium.monthly", "expired", NOW - timedelta(days=1), "Sandbox")]
    body = make_client().get("/v1/me").json()
    assert body["plan"] == "free"
    assert body["subscription"]["status"] == "expired"


def test_me_remaining_never_negative(store):
    store.used = 15
    resp = make_client(FREE_DAILY_QUOTA=10).get("/v1/me")
    assert resp.json()["quota"] == {"limit": 10, "used": 15, "remaining": 0, "resetsAt": "2026-11-10T00:00:00+07:00"}
    assert resp.headers["X-Quota-Remaining"] == "0"


def test_profile_created_once_with_locale_from_accept_language(store):
    client = make_client()
    assert client.get("/v1/me", headers={"Accept-Language": "en-US,en;q=0.9"}).json()["locale"] == "en"
    assert store.profiles == {UID: "en"}
    # Existing profile: locale is not changed by a later header (D-236, owner 2026-11-09)
    assert client.get("/v1/me", headers={"Accept-Language": "vi"}).json()["locale"] == "en"


def test_profile_locale_defaults_to_vi(store):
    assert make_client().get("/v1/me", headers={"Accept-Language": "fr"}).json()["locale"] == "vi"


def test_deleted_auth_user_is_unauthorized(store):
    resp = make_client(user_id="11111111-1111-1111-1111-111111111111").get("/v1/me")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "unauthorized"


def test_me_without_token_is_unauthorized(store):
    app = create_app()
    app.dependency_overrides[deps.db] = fake_db
    resp = TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS).get("/v1/me")
    assert resp.status_code == 401
    assert resp.json()["error"]["code"] == "unauthorized"


def test_me_without_database_url_is_internal(store):
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(DATABASE_URL=None)
    app.dependency_overrides[deps.current_user] = lambda: CurrentUser(id=UID)
    resp = TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS).get("/v1/me")
    assert resp.status_code == 500
    err = resp.json()["error"]
    assert err["code"] == "internal" and err["retryable"] is True


def test_me_database_unreachable_is_internal_without_leaking_url(store, caplog):
    url = "postgresql://user:topsecret@127.0.0.1:1/db"
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(DATABASE_URL=url, DB_CONNECT_TIMEOUT_SECONDS=1)
    app.dependency_overrides[deps.current_user] = lambda: CurrentUser(id=UID)
    resp = TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS).get("/v1/me")
    assert resp.status_code == 500 and resp.json()["error"]["code"] == "internal"
    assert "topsecret" not in caplog.text and "topsecret" not in resp.text


def test_health_does_not_touch_database():
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(DATABASE_URL=None)
    assert TestClient(app).get("/v1/health").status_code == 200
