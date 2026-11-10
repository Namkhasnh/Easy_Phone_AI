"""1B.10c: `X-Client-Version` → 426 (API_CONTRACT §1, §3.2, §4.3 step 2). No DB."""

import pytest
from fastapi import APIRouter, Depends
from fastapi.testclient import TestClient
from pydantic import BaseModel, ConfigDict

from app import deps
from app.auth import CurrentUser
from app.config import Settings, get_settings
from app.deps import version_tuple
from app.main import create_app
from app.services import accounts

router = APIRouter(prefix="/_test")


class Body(BaseModel):
    model_config = ConfigDict(extra="forbid")
    x: int


@router.post("/versioned")
def versioned(body: Body, user: deps.AuthedUser = Depends(deps.authed_user)) -> dict:
    return {"ok": True}


@pytest.fixture(autouse=True)
def no_profile_db(monkeypatch):
    async def ensure(conn, user_id, accept_language):
        return "vi"

    monkeypatch.setattr(accounts, "ensure_profile", ensure)


async def fake_db():
    yield object()


def client(min_version="1.0.0", authed=True) -> TestClient:
    app = create_app(extra_routers=[router])
    app.dependency_overrides[get_settings] = lambda: Settings(MIN_CLIENT_VERSION=min_version)
    app.dependency_overrides[deps.db] = fake_db
    if authed:
        app.dependency_overrides[deps.current_user] = lambda: CurrentUser(id="u1")
    return TestClient(app, raise_server_exceptions=False)


def post(c, version=None, body=None):
    headers = {} if version is None else {"X-Client-Version": version}
    return c.post("/_test/versioned", json=body or {"x": 1}, headers=headers)


@pytest.mark.parametrize("version", ["1.0(1)", "1.0.0(12)", "1.0.0", "1", "2.3(45)", "1.10.0(1)"])
def test_current_or_newer_passes(version):
    c = client()
    assert post(c, version).status_code == 200


@pytest.mark.parametrize("version,minimum", [("1.0(1)", "1.0.1"), ("1.2.9(99)", "1.10.0"), ("0.9", "1.0")])
def test_older_is_426_with_min_version(version, minimum):
    c = client(minimum)
    r = post(c, version)
    assert r.status_code == 426
    err = r.json()["error"]
    assert err["code"] == "client_outdated" and err["details"] == {"minVersion": minimum} and err["retryable"] is False


@pytest.mark.parametrize("version,reason", [(None, "missing"), ("  ", "missing"), ("abc", "malformed"),
                                            ("1.0.0.0", "malformed"), ("1.0 (1)", "malformed"), ("v1.0", "malformed")])
def test_missing_or_malformed_is_422(version, reason):
    c = client()
    r = post(c, version)
    assert r.status_code == 422
    assert r.json()["error"]["details"] == {"field": "X-Client-Version", "reason": reason}


def test_order_auth_then_version_then_body():
    unauth = client("9.0.0", authed=False)
    assert post(unauth, "1.0(1)").status_code == 401  # 1 auth before 2 version
    old = client("9.0.0")
    assert post(old, "1.0(1)", body={"x": "not int", "extra": 1}).status_code == 426  # 2 version before 3 body


def test_health_needs_no_version():
    c = client("9.0.0")
    assert c.get("/v1/health").status_code == 200


def test_version_tuple_pads():
    assert version_tuple("1.0") == version_tuple("1.0.0") == (1, 0, 0)
    assert version_tuple("1.10") > version_tuple("1.9.9")
