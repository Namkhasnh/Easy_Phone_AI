"""0.13: JWT verification (API_CONTRACT §2, D-032). JWKS is faked; no network."""

import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi.testclient import TestClient
from jwt import PyJWKClientError
from pydantic import SecretStr

from app import auth
from app.config import Settings, get_settings
from app.main import create_app
from tests.conftest import test_router as extra_router

KID = "test-kid"
SUB = "6F1C2B7E-1D0A-4C55-9A51-2F6C1C0F9E11"
HS_SECRET = "test-hs256-secret-at-least-32-bytes-long!"
KEY = ec.generate_private_key(ec.SECP256R1())
OTHER_KEY = ec.generate_private_key(ec.SECP256R1())


class FakeJWKS:
    def get_signing_key_from_jwt(self, token: str):
        if jwt.get_unverified_header(token).get("kid") != KID:
            raise PyJWKClientError("Unable to find a signing key that matches")
        return type("K", (), {"key": KEY.public_key()})()


@pytest.fixture(autouse=True)
def fake_jwks(monkeypatch):
    monkeypatch.setattr(auth, "_jwks_client", lambda url: FakeJWKS())


def make_client(**settings) -> TestClient:
    app = create_app(extra_routers=[extra_router])
    app.dependency_overrides[get_settings] = lambda: Settings(SUPABASE_URL="https://x.supabase.co", **settings)
    return TestClient(app, raise_server_exceptions=False)


def claims(**over) -> dict:
    base = {"sub": SUB, "aud": "authenticated", "exp": int(time.time()) + 300, "role": "authenticated"}
    base.update(over)
    return {k: v for k, v in base.items() if v is not None}


def es256(key=KEY, kid=KID, **over) -> str:
    return jwt.encode(claims(**over), key, algorithm="ES256", headers={"kid": kid})


def bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def assert_401(resp, token: str | None = None) -> None:
    assert resp.status_code == 401
    err = resp.json()["error"]
    assert err["code"] == "unauthorized" and err["retryable"] is False
    if token:
        assert token not in resp.text


def test_valid_es256_returns_lowercase_sub():
    resp = make_client().get("/_test/whoami", headers=bearer(es256()))
    assert resp.status_code == 200
    assert resp.json() == {"userId": SUB.lower()}


def test_valid_hs256_with_secret():
    token = jwt.encode(claims(), HS_SECRET, algorithm="HS256")
    resp = make_client(SUPABASE_JWT_SECRET=SecretStr(HS_SECRET)).get("/_test/whoami", headers=bearer(token))
    assert resp.status_code == 200


@pytest.mark.parametrize(
    "headers",
    [{}, {"Authorization": ""}, {"Authorization": "Bearer "}, {"Authorization": "Basic abc"}, bearer("garbage")],
)
def test_missing_or_malformed_header(headers):
    assert_401(make_client().get("/_test/whoami", headers=headers))


@pytest.mark.parametrize(
    "token",
    [
        es256(exp=int(time.time()) - 10),  # expired
        es256(aud="anon"),  # wrong audience
        es256(aud=None),  # missing aud
        es256(exp=None),  # missing exp
        es256(sub=None),  # missing sub
        es256(sub="not-a-uuid"),
        es256(key=OTHER_KEY),  # bad signature
        es256(kid="unknown-kid"),
        jwt.encode(claims(), None, algorithm="none"),
        jwt.encode(claims(), HS_SECRET, algorithm="HS256"),  # no secret configured
    ],
    ids=["expired", "wrong-aud", "no-aud", "no-exp", "no-sub", "bad-sub", "bad-sig", "unknown-kid", "alg-none", "hs256-no-secret"],
)
def test_invalid_tokens_are_401(token):
    assert_401(make_client().get("/_test/whoami", headers=bearer(token)), token)


def test_hs256_wrong_secret():
    token = jwt.encode(claims(), "another-secret-also-32-bytes-long-xx", algorithm="HS256")
    resp = make_client(SUPABASE_JWT_SECRET=SecretStr(HS_SECRET)).get("/_test/whoami", headers=bearer(token))
    assert_401(resp, token)


def test_jwks_unreachable_is_500(monkeypatch):
    class Down:
        def get_signing_key_from_jwt(self, token):
            raise jwt.PyJWKClientConnectionError("down")

    monkeypatch.setattr(auth, "_jwks_client", lambda url: Down())
    resp = make_client().get("/_test/whoami", headers=bearer(es256()))
    assert resp.status_code == 500
    assert resp.json()["error"]["code"] == "internal"


def test_jwks_url_from_supabase_url(monkeypatch):
    seen = []
    monkeypatch.setattr(auth, "_jwks_client", lambda url: seen.append(url) or FakeJWKS())
    make_client().get("/_test/whoami", headers=bearer(es256()))
    assert seen == ["https://x.supabase.co/auth/v1/.well-known/jwks.json"]


def test_health_needs_no_token():
    assert make_client().get("/v1/health").status_code == 200
