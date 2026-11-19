"""2.2: `/v1/gmail/accounts` + Google OAuth exchange / refresh / revoke (API_GMAIL.md §2, §3, §6, D-151, D-306).

Repository faked in memory, Google faked with `httpx2.MockTransport`; no DB, no network.
"""

import asyncio
import logging
import re
from pathlib import Path
from urllib.parse import parse_qs

import httpx2
import jwt
import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app import deps
from app.auth import CurrentUser
from app.config import Settings, get_settings
from app.errors import AppError
from app.main import create_app
from app.repositories import gmail_accounts as repo
from app.repositories import profiles
from app.routers import gmail as gmail_router
from app.services import gmail_accounts, gmail_tokens
from app.services.google_oauth import GoogleOAuth, redirect_uri

UID = "6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11"
CLIENT_ID = "123-abc.apps.googleusercontent.com"
REDIRECT = "com.googleusercontent.apps.123-abc:/oauth2redirect"
KEY = Fernet.generate_key().decode()
SCOPES = "openid https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.compose email"
HEADERS = {"X-Client-Version": "1.0(1)"}
BODY = {"schemaVersion": 1, "code": "4/0Ae-code", "codeVerifier": "v" * 43, "redirectUri": REDIRECT}


def settings(**kw) -> Settings:
    return Settings(GMAIL_CLIENT_ID=CLIENT_ID, GMAIL_TOKEN_KEY=KEY, **kw)


def id_token(email="Khanh@Gmail.com", aud=CLIENT_ID, iss="https://accounts.google.com") -> str:
    return jwt.encode({"email": email, "email_verified": True, "aud": aud, "iss": iss}, "x" * 32, algorithm="HS256")


class FakeGoogle:
    """Token + revoke endpoints. `token_status` / `refresh_status` / `scope` / `email` change per test."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, dict[str, list[str]]]] = []
        self.token_status = 200
        self.refresh_error = None
        self.scope = SCOPES
        self.email = "Khanh@Gmail.com"
        self.aud = CLIENT_ID

    def handler(self, request: httpx2.Request) -> httpx2.Response:
        form = parse_qs(request.content.decode())
        self.calls.append((request.url.path, form))
        if request.url.path == "/revoke":
            return httpx2.Response(200)
        if form["grant_type"] == ["refresh_token"]:
            if self.refresh_error:
                return httpx2.Response(400, json={"error": self.refresh_error})
            return httpx2.Response(200, json={"access_token": "ya29.fresh", "expires_in": 3599})
        if self.token_status != 200:
            return httpx2.Response(self.token_status, json={"error": "invalid_grant"})
        return httpx2.Response(200, json={
            "access_token": "ya29.access", "refresh_token": "1//refresh-secret", "expires_in": 3599,
            "scope": self.scope, "id_token": id_token(self.email, self.aud),
        })

    def oauth(self, s: Settings) -> GoogleOAuth:
        return GoogleOAuth(s, httpx2.AsyncClient(transport=httpx2.MockTransport(self.handler),
                                                 base_url="https://oauth2.googleapis.com"))

    def paths(self) -> list[str]:
        return [p for p, _ in self.calls]


class FakeRepo:
    def __init__(self) -> None:
        self.rows: dict[str, dict] = {}  # id -> row

    async def for_user(self, conn, user_id):
        return [repo.GmailAccountRow(i, r["email"], r["status"], r["enc"])
                for i, r in self.rows.items() if r["user"] == user_id]

    async def upsert(self, conn, user_id, new_id, email, token_enc, scopes):
        for i, r in self.rows.items():
            if r["user"] == user_id and r["email"] == email:
                r.update(enc=token_enc, status="connected", scopes=scopes)
                return i
        self.rows[new_id] = {"user": user_id, "email": email, "enc": token_enc, "status": "connected", "scopes": scopes}
        return new_id

    async def delete(self, conn, user_id, account_id):
        row = self.rows.get(account_id)
        if row is None or row["user"] != user_id:
            return None
        return self.rows.pop(account_id)["enc"]

    async def set_status(self, conn, user_id, account_id, status):
        self.rows[account_id]["status"] = status


@pytest.fixture
def google() -> FakeGoogle:
    return FakeGoogle()


@pytest.fixture
def store(monkeypatch) -> FakeRepo:
    s = FakeRepo()
    for name in ("for_user", "upsert", "delete", "set_status"):
        monkeypatch.setattr(repo, name, getattr(s, name))

    async def upsert_profile(conn, user_id, locale):
        return locale

    monkeypatch.setattr(profiles, "upsert", upsert_profile)
    return s


async def fake_db():
    yield object()


@pytest.fixture
def client(store, google) -> TestClient:
    app = create_app()
    s = settings()
    app.dependency_overrides[get_settings] = lambda: s
    app.dependency_overrides[deps.current_user] = lambda: CurrentUser(id=UID)
    app.dependency_overrides[deps.db] = fake_db
    app.dependency_overrides[gmail_router.google_oauth] = lambda: google.oauth(s)
    return TestClient(app, raise_server_exceptions=False)


def connect(client, **body):
    return client.post("/v1/gmail/accounts", json={**BODY, **body}, headers=HEADERS)


# --- connect (§3.1) -------------------------------------------------------------------------------------------


def test_connect_stores_only_an_encrypted_token(client, store, google, caplog):
    caplog.set_level(logging.DEBUG)
    resp = connect(client)
    assert resp.status_code == 200, resp.text
    account = resp.json()["account"]
    assert resp.json()["schemaVersion"] == 1
    assert re.fullmatch(r"gma_[0-9A-Z]{26}", account["accountId"])
    assert account == {"accountId": account["accountId"], "email": "khanh@gmail.com", "status": "connected"}
    row = store.rows[account["accountId"]]
    assert b"refresh-secret" not in row["enc"]
    assert gmail_tokens.decrypt(row["enc"], settings()) == "1//refresh-secret"
    form = google.calls[0][1]
    assert form["code_verifier"] == ["v" * 43] and form["client_id"] == [CLIENT_ID]
    assert form["redirect_uri"] == [REDIRECT] and "client_secret" not in form  # iOS client: PKCE, no secret
    assert "refresh-secret" not in resp.text and "ya29" not in resp.text
    for secret in ("refresh-secret", "ya29", "4/0Ae-code", "khanh@gmail.com"):
        assert secret not in caplog.text.lower()  # D-059


def test_redirect_must_be_the_ios_client_scheme(client, google):
    assert redirect_uri(CLIENT_ID) == REDIRECT
    resp = connect(client, redirectUri="https://evil.example/cb")
    assert resp.status_code == 422
    assert resp.json()["error"]["details"] == {"field": "redirectUri", "reason": "mismatch"}
    assert google.calls == []  # refused before any Google call


def test_missing_scope_is_refused_and_the_grant_revoked(client, store, google):
    google.scope = "openid email https://www.googleapis.com/auth/gmail.readonly"
    resp = connect(client)
    assert resp.status_code == 422
    assert resp.json()["error"]["details"] == {"field": "scope", "reason": "missingScope"}
    assert google.paths() == ["/token", "/revoke"] and store.rows == {}


def test_one_account_only_same_email_replaces(client, store, google):
    first = connect(client).json()["account"]["accountId"]
    again = connect(client).json()["account"]["accountId"]
    assert again == first and len(store.rows) == 1
    google.email = "other@gmail.com"
    resp = connect(client)
    assert resp.status_code == 409 and resp.json()["error"]["code"] == "gmail_account_limit"
    assert google.paths()[-1] == "/revoke" and len(store.rows) == 1  # D-306


def test_reconnect_marks_the_account_connected_again(client, store):
    account_id = connect(client).json()["account"]["accountId"]
    store.rows[account_id]["status"] = "needsReconnect"
    assert connect(client).json()["account"]["status"] == "connected"
    assert store.rows[account_id]["status"] == "connected"


@pytest.mark.parametrize("status, code, http", [(400, "invalid_input", 422), (503, "upstream_error", 503)])
def test_google_exchange_errors(client, google, status, code, http):
    google.token_status = status
    resp = connect(client)
    assert resp.status_code == http and resp.json()["error"]["code"] == code


def test_id_token_for_another_client_is_refused(client, google):
    google.aud = "someone-else.apps.googleusercontent.com"
    resp = connect(client)
    assert resp.status_code == 422 and resp.json()["error"]["details"]["reason"] == "badIdToken"


def test_request_rejects_unknown_keys_and_short_verifier(client):
    assert connect(client, extra=1).status_code == 422
    assert connect(client, codeVerifier="short").status_code == 422


def test_missing_config_is_internal(store, google):
    app = create_app()
    s = Settings(GMAIL_CLIENT_ID=None, GMAIL_TOKEN_KEY=None)
    app.dependency_overrides[get_settings] = lambda: s
    app.dependency_overrides[deps.current_user] = lambda: CurrentUser(id=UID)
    app.dependency_overrides[deps.db] = fake_db
    app.dependency_overrides[gmail_router.google_oauth] = lambda: google.oauth(s)
    resp = TestClient(app, raise_server_exceptions=False).post("/v1/gmail/accounts", json=BODY, headers=HEADERS)
    assert resp.status_code == 500 and google.calls == []


# --- list / disconnect (§3.2, §3.3) ----------------------------------------------------------------------------


def test_list_and_disconnect(client, store, google):
    assert client.get("/v1/gmail/accounts", headers=HEADERS).json() == {"schemaVersion": 1, "accounts": []}
    account_id = connect(client).json()["account"]["accountId"]
    listed = client.get("/v1/gmail/accounts", headers=HEADERS).json()["accounts"]
    assert listed == [{"accountId": account_id, "email": "khanh@gmail.com", "status": "connected"}]

    resp = client.delete(f"/v1/gmail/accounts/{account_id}", headers=HEADERS)
    assert resp.status_code == 204 and resp.content == b"" and store.rows == {}
    assert google.calls[-1] == ("/revoke", {"token": ["1//refresh-secret"]})
    calls = len(google.calls)
    assert client.delete(f"/v1/gmail/accounts/{account_id}", headers=HEADERS).status_code == 204  # idempotent
    assert len(google.calls) == calls


def test_needs_auth_and_client_version(store, google):
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: settings()
    plain = TestClient(app, raise_server_exceptions=False)
    assert plain.get("/v1/gmail/accounts", headers=HEADERS).status_code == 401


# --- access token for 2.4 / 2.7 (§6) ----------------------------------------------------------------------------


def run(coro):
    return asyncio.new_event_loop().run_until_complete(coro)


def test_access_token_refreshes_and_marks_needs_reconnect(client, store, google):
    account_id = connect(client).json()["account"]["accountId"]
    oauth = google.oauth(settings())
    assert run(gmail_accounts.access_token(None, UID, account_id, oauth, settings())) == "ya29.fresh"

    google.refresh_error = "invalid_grant"  # 7-day Testing expiry
    with pytest.raises(AppError) as err:
        run(gmail_accounts.access_token(None, UID, account_id, oauth, settings()))
    assert (err.value.code, err.value.http_status) == ("gmail_reconnect_required", 409)
    assert store.rows[account_id]["status"] == "needsReconnect"
    listed = client.get("/v1/gmail/accounts", headers=HEADERS).json()["accounts"]
    assert listed[0]["status"] == "needsReconnect"

    with pytest.raises(AppError) as err:
        run(gmail_accounts.access_token(None, UID, "gma_01JD0000000000000000000000", oauth, settings()))
    assert (err.value.code, err.value.http_status) == ("gmail_not_connected", 404)


def test_token_key_change_needs_reconnect_not_crash(client, store, google):
    account_id = connect(client).json()["account"]["accountId"]
    other = Settings(GMAIL_CLIENT_ID=CLIENT_ID, GMAIL_TOKEN_KEY=Fernet.generate_key().decode())
    with pytest.raises(AppError) as err:
        run(gmail_accounts.access_token(None, UID, account_id, google.oauth(other), other))
    assert err.value.code == "gmail_reconnect_required"


# --- never send (D-103, D-304) ----------------------------------------------------------------------------------


def test_routes_listed_and_nothing_can_send(client):
    paths = client.get("/openapi.json").json()["paths"]
    assert "/v1/gmail/accounts" in paths and "/v1/gmail/accounts/{account_id}" in paths
    assert not [p for p in paths if "send" in p.lower()]
    app_dir = Path(__file__).resolve().parents[1] / "app"
    source = "\n".join(p.read_text(encoding="utf-8") for p in app_dir.rglob("*.py"))
    assert "messages/send" not in source and "drafts/send" not in source
