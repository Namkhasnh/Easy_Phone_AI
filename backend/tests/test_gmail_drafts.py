"""2.7: `POST /v1/gmail/drafts` (API_GMAIL.md §5, D-103, D-105, D-304, D-307). Gmail faked, key store faked."""

import base64
import email
import json
import logging
from datetime import UTC, datetime, timedelta
from email.policy import default
from pathlib import Path

import httpx2
import pytest
from fastapi.testclient import TestClient

from app import deps
from app.config import Settings, get_settings
from app.main import create_app
from app.repositories import gmail_draft_keys
from app.repositories.gmail_draft_keys import DraftKeyRow
from app.routers import gmail as gmail_router
from app.services import gmail_accounts
from app.services.gmail_client import GmailClient

FIXTURES = Path(__file__).parent / "fixtures" / "contract"
REQ = json.loads((FIXTURES / "gmaildraft.new.request.json").read_text(encoding="utf-8"))
KEY = "5b0e8f4a-1d0a-4c55-9a51-2f6c1c0f9e11"
HEADERS = {"X-Client-Version": "1.0(1)", "Idempotency-Key": KEY}
NOW = datetime(2026, 11, 18, 2, 0, tzinfo=UTC)


class FakeGmail:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str, dict | None]] = []

    def handler(self, request: httpx2.Request) -> httpx2.Response:
        body = json.loads(request.content) if request.content else None
        self.calls.append((request.method, request.url.path, body))
        path = request.url.path
        if request.method == "POST" and path.endswith("/drafts"):
            return httpx2.Response(200, json={"id": "r-5823", "message": {"id": "18c3001", "threadId": "t1"}})
        if path.endswith("/drafts/r-5823"):
            return httpx2.Response(200, json={"id": "r-5823", "message": {"id": "18c3001"}})
        if "/messages/" in path:
            return httpx2.Response(200, json={"id": "18c2f0a", "payload": {"headers": [
                {"name": "Message-ID", "value": "<abc@mail.gmail.com>"},
                {"name": "References", "value": "<root@mail.gmail.com>"},
                {"name": "Subject", "value": "Họp tổ chiều thứ Sáu"}]}})
        return httpx2.Response(404)

    def created_mime(self) -> email.message.EmailMessage:
        raw = next(b for m, p, b in self.calls if m == "POST")["message"]["raw"]
        return email.message_from_bytes(base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)), policy=default)


@pytest.fixture
def setup(monkeypatch):
    keys: dict[str, DraftKeyRow] = {}

    async def find(conn, user_id, key):
        return keys.get(key)

    async def insert(conn, user_id, key, account_id, draft_id):
        keys.setdefault(key, DraftKeyRow(account_id, draft_id, NOW))

    async def connected(conn, user_id, account_id, oauth, settings):
        return "khanh@gmail.com", "ya29.fresh"

    monkeypatch.setattr(gmail_draft_keys, "find", find)
    monkeypatch.setattr(gmail_draft_keys, "insert", insert)
    monkeypatch.setattr(gmail_accounts, "connected", connected)
    gmail = FakeGmail()
    app = create_app()
    s = Settings()

    async def no_db():
        yield None

    app.dependency_overrides[get_settings] = lambda: s
    app.dependency_overrides[deps.authed_user] = lambda: deps.AuthedUser(id="u1", locale="vi")
    app.dependency_overrides[deps.db] = no_db
    app.dependency_overrides[deps.clock] = lambda: NOW
    app.dependency_overrides[gmail_router.google_oauth] = lambda: None
    app.dependency_overrides[gmail_router.gmail_client] = lambda: GmailClient(
        s, httpx2.AsyncClient(transport=httpx2.MockTransport(gmail.handler)))
    return TestClient(app, raise_server_exceptions=False), gmail, keys


def test_new_draft_matches_the_fixture_and_is_never_sent(setup, caplog):
    client, gmail, keys = setup
    caplog.set_level(logging.DEBUG)
    r = client.post("/v1/gmail/drafts", json=REQ, headers=HEADERS)
    assert r.status_code == 200, r.text
    assert r.json() == json.loads((FIXTURES / "gmaildraft.created.response.json").read_text(encoding="utf-8"))
    assert [(m, p) for m, p, _ in gmail.calls] == [("POST", "/gmail/v1/users/me/drafts")]     # drafts.create only
    assert not any("send" in p for _, p, _ in gmail.calls)
    msg = gmail.created_mime()
    assert msg["To"] == "lan.nguyen@example.com" and msg["From"] == "khanh@gmail.com"
    assert msg["Subject"] == "Xin nghỉ ngày mai"
    assert msg.get_content().replace("\r\n", "\n").strip() == REQ["body"]            # CRLF on the wire
    assert "threadId" not in next(b for m, _, b in gmail.calls if m == "POST")["message"]
    assert keys[KEY].draft_id == "r-5823"
    for secret in ("lan.nguyen@example.com", "Xin nghỉ", "Mai em xin nghỉ"):
        assert secret not in caplog.text                                                     # D-059


def test_same_key_returns_the_same_draft_without_creating_another(setup):
    client, gmail, _ = setup
    first = client.post("/v1/gmail/drafts", json=REQ, headers=HEADERS).json()
    again = client.post("/v1/gmail/drafts", json=REQ, headers=HEADERS)
    assert again.status_code == 200 and again.json() == first
    assert [m for m, _, _ in gmail.calls].count("POST") == 1                                  # D-105


def test_same_key_other_account_or_expired_is_422(setup):
    client, _, keys = setup
    client.post("/v1/gmail/drafts", json=REQ, headers=HEADERS)
    other = client.post("/v1/gmail/drafts", json={**REQ, "accountId": "gma_01JD0000000000000000000009"},
                        headers=HEADERS)
    assert other.status_code == 422 and other.json()["error"]["details"]["reason"] == "idempotencyKeyAccountMismatch"
    keys[KEY] = DraftKeyRow(REQ["accountId"], "r-5823", NOW - timedelta(hours=25))
    old = client.post("/v1/gmail/drafts", json=REQ, headers=HEADERS)
    assert old.json()["error"]["details"]["reason"] == "idempotencyKeyExpired"


def test_reply_threads_the_draft(setup):
    client, gmail, _ = setup
    req = {**REQ, "subject": "", "replyTo": {"threadId": "18c2e00", "messageId": "18c2f0a"}}
    r = client.post("/v1/gmail/drafts", json=req, headers=HEADERS)
    assert r.status_code == 200
    assert next(b for m, _, b in gmail.calls if m == "POST")["message"]["threadId"] == "18c2e00"
    msg = gmail.created_mime()
    assert msg["Subject"] == "Re: Họp tổ chiều thứ Sáu"
    assert msg["In-Reply-To"] == "<abc@mail.gmail.com>"
    assert msg["References"] == "<root@mail.gmail.com> <abc@mail.gmail.com>"


@pytest.mark.parametrize("change", [
    {"to": []}, {"to": ["không phải email"]}, {"to": ["Lan <lan@example.com>"]}, {"to": [f"a{i}@x.vn" for i in range(6)]},
    {"body": ""}, {"subject": "x" * 201}, {"extra": 1}, {"replyTo": {"threadId": "../x", "messageId": "1"}},
])
def test_validation(setup, change):
    client, gmail, _ = setup
    assert client.post("/v1/gmail/drafts", json={**REQ, **change}, headers=HEADERS).status_code == 422
    assert gmail.calls == []


def test_key_required(setup):
    client, gmail, _ = setup
    r = client.post("/v1/gmail/drafts", json=REQ, headers={"X-Client-Version": "1.0(1)"})
    assert r.status_code == 422 and gmail.calls == []
