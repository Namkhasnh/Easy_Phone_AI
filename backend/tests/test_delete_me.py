"""1G.1: `DELETE /v1/me` (API_CONTRACT §6.3, D-073). Supabase Admin API and Google faked; no DB."""

import httpx2
import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from app import deps
from app.config import Settings, get_settings
from app.main import create_app
from app.repositories import gmail_accounts as gmail_repo
from app.routers import gmail as gmail_router
from app.routers import me as me_router
from app.services import gmail_tokens
from app.services.supabase_admin import SupabaseAdmin

UID = "6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11"
KEY = Fernet.generate_key().decode()


class FakeOAuth:
    def __init__(self):
        self.revoked: list[str] = []

    async def revoke(self, token):
        self.revoked.append(token)


def setup(monkeypatch, status=204, rows=True):
    calls = []

    def handler(request: httpx2.Request) -> httpx2.Response:
        calls.append((request.method, request.url.path, request.headers.get("apikey")))
        return httpx2.Response(status)

    s = Settings(SUPABASE_URL="https://proj.supabase.co", SUPABASE_SERVICE_ROLE_KEY="service-key", GMAIL_TOKEN_KEY=KEY)
    enc = gmail_tokens.encrypt("1//refresh", s)

    async def for_user(conn, user_id):
        return [gmail_repo.GmailAccountRow("gma_1", "k@gmail.com", "connected", enc)] if rows else []

    monkeypatch.setattr(gmail_repo, "for_user", for_user)
    oauth = FakeOAuth()
    app = create_app()

    async def no_db():
        yield None

    app.dependency_overrides[get_settings] = lambda: s
    app.dependency_overrides[deps.current_user] = lambda: deps.CurrentUser(id=UID)
    app.dependency_overrides[deps.db] = no_db
    app.dependency_overrides[gmail_router.google_oauth] = lambda: oauth
    app.dependency_overrides[me_router.supabase_admin] = lambda: SupabaseAdmin(
        s, httpx2.AsyncClient(transport=httpx2.MockTransport(handler)))
    return TestClient(app, raise_server_exceptions=False), calls, oauth


def test_deletes_the_auth_user_and_revokes_gmail(monkeypatch):
    client, calls, oauth = setup(monkeypatch)
    r = client.delete("/v1/me")                                   # no X-Client-Version needed (§2, §6.3)
    assert r.status_code == 204 and r.content == b""
    assert calls == [("DELETE", f"/auth/v1/admin/users/{UID}", "service-key")]
    assert oauth.revoked == ["1//refresh"]


@pytest.mark.parametrize("status, http", [(404, 204), (500, 503), (401, 503)])
def test_already_deleted_is_fine_other_failures_retry(monkeypatch, status, http):
    client, _, _ = setup(monkeypatch, status=status, rows=False)
    r = client.delete("/v1/me")
    assert r.status_code == http
    if http == 503:
        assert r.json()["error"]["code"] == "upstream_error" and r.json()["error"]["retryable"] is True


def test_needs_a_token():
    app = create_app()
    assert TestClient(app, raise_server_exceptions=False).delete("/v1/me").status_code == 401
