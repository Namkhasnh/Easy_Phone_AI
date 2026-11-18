"""1F.3: `POST /v1/billing/verify` (API_CONTRACT §8.1, D-083, D-239, D-240, D-284). Repos faked, JWS really signed."""

import base64
import datetime as dt
from datetime import UTC, datetime, timedelta

import jwt
import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.serialization import Encoding
from cryptography.x509.oid import NameOID
from fastapi.testclient import TestClient

from app import deps
from app.config import Settings, get_settings
from app.main import create_app
from app.repositories import profiles, subscriptions, usage
from app.repositories.subscriptions import SubscriptionRow

UID = "6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11"
OTHER = "11111111-2222-3333-4444-555555555555"
NOW = datetime(2026, 11, 18, 5, 0, tzinfo=UTC)
HEADERS = {"X-Client-Version": "1.0(1)"}


def signer():
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "StoreKit Testing in Xcode")])
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(1).not_valid_before(NOW - timedelta(days=1)).not_valid_after(NOW + timedelta(days=365))
            .sign(key, hashes.SHA256()))
    return key, base64.b64encode(cert.public_bytes(Encoding.DER)).decode()


KEY, X5C = signer()


def jws(key=KEY, x5c=X5C, **over) -> str:
    ms = lambda d: int(d.timestamp() * 1000)  # noqa: E731
    payload = {"transactionId": "2000000001", "originalTransactionId": "2000000000", "bundleId": "vn.namkhanh.easyphone",
               "productId": "easyphone.premium.monthly", "purchaseDate": ms(NOW), "expiresDate": ms(NOW + timedelta(days=30)),
               "appAccountToken": UID.upper(), "environment": "Xcode", "type": "Auto-Renewable Subscription"}
    payload.update(over)
    return jwt.encode(payload, key, algorithm="ES256", headers={"x5c": [x5c]})


class Store:
    def __init__(self):
        self.rows: dict[str, dict] = {}
        self.users = {UID, OTHER}

    async def for_user(self, conn, user_id):
        return [SubscriptionRow(r["product"], r["status"], r["expires"], r["env"])
                for r in self.rows.values() if r["user"] == user_id]

    async def owner_of(self, conn, original):
        return self.rows.get(original, {}).get("user")

    async def user_exists(self, conn, user_id):
        return user_id in self.users

    async def upsert(self, conn, user_id, product, original, expires, status, env):
        self.rows[original] = {"user": user_id, "product": product, "expires": expires, "status": status, "env": env}


@pytest.fixture
def setup(monkeypatch, tmp_path):
    store = Store()
    for name in ("for_user", "owner_of", "user_exists", "upsert"):
        monkeypatch.setattr(subscriptions, name, getattr(store, name))

    async def upsert_profile(conn, user_id, locale):
        return locale

    async def units(conn, user_id, start, end):
        return 0

    monkeypatch.setattr(profiles, "upsert", upsert_profile)
    monkeypatch.setattr(usage, "units_between", units)
    pin = tmp_path / "pin.sha256"
    s = Settings(ALLOW_XCODE_STOREKIT=True, XCODE_STOREKIT_PIN_FILE=str(pin))
    app = create_app()

    async def no_db():
        yield None

    app.dependency_overrides[get_settings] = lambda: s
    app.dependency_overrides[deps.current_user] = lambda: deps.CurrentUser(id=UID)
    app.dependency_overrides[deps.db] = no_db
    app.dependency_overrides[deps.clock] = lambda: NOW
    return TestClient(app, raise_server_exceptions=False), store, pin


def post(client, token):
    return client.post("/v1/billing/verify", json={"schemaVersion": 1, "signedTransaction": token}, headers=HEADERS)


def test_xcode_purchase_makes_premium_and_pins_the_certificate(setup):
    client, store, pin = setup
    r = post(client, jws())
    assert r.status_code == 200, r.text
    assert r.json()["plan"] == "premium" and r.json()["quota"]["limit"] == Settings().PREMIUM_DAILY_QUOTA
    assert r.json()["subscription"]["environment"] == "Xcode" and r.json()["subscription"]["status"] == "active"
    assert pin.exists() and len(pin.read_text().strip()) == 64
    assert post(client, jws()).status_code == 200 and len(store.rows) == 1                     # idempotent


def test_another_certificate_after_the_pin_is_refused(setup):
    client, _, _ = setup
    assert post(client, jws()).status_code == 200
    key2, x5c2 = signer()
    r = post(client, jws(key=key2, x5c=x5c2, originalTransactionId="2000000099"))
    assert r.status_code == 400 and r.json()["error"]["code"] == "billing_invalid"


@pytest.mark.parametrize("over", [
    {"bundleId": "com.other.app"}, {"productId": "easyphone.premium.weekly"}, {"environment": "Production"},
    {"environment": "Sandbox"}, {"originalTransactionId": ""},
])
def test_bad_transactions(setup, over):
    client, store, _ = setup
    r = post(client, jws(**over))
    assert r.status_code == 400 and r.json()["error"]["code"] == "billing_invalid" and store.rows == {}


def test_bad_signature_and_garbage(setup):
    client, _, _ = setup
    key2, _ = signer()
    assert post(client, jws(key=key2)).status_code == 400                          # signed by another key
    assert post(client, "not.a.jws").status_code == 400
    assert post(client, jwt.encode({"a": 1}, "secret", algorithm="HS256")).status_code == 400


def test_xcode_needs_the_flag(setup, monkeypatch):
    client, _, _ = setup
    client.app.dependency_overrides[get_settings] = lambda: Settings(ALLOW_XCODE_STOREKIT=False)
    assert post(client, jws()).status_code == 400


def test_account_mismatch_and_deleted_account_transfer(setup):
    client, store, _ = setup
    r = post(client, jws(appAccountToken=OTHER))
    assert r.status_code == 403 and r.json()["error"]["code"] == "billing_account_mismatch"
    store.users.discard(OTHER)                                                     # D-239: that account was deleted
    assert post(client, jws(appAccountToken=OTHER)).status_code == 200
    assert store.rows["2000000000"]["user"] == UID


def test_expired_and_revoked(setup):
    client, store, _ = setup
    ms = lambda d: int(d.timestamp() * 1000)  # noqa: E731
    r = post(client, jws(expiresDate=ms(NOW - timedelta(days=1))))
    assert r.json()["plan"] == "free" and store.rows["2000000000"]["status"] == "expired"
    r = post(client, jws(revocationDate=ms(NOW)))
    assert store.rows["2000000000"]["status"] == "revoked" and r.json()["plan"] == "free"


def test_listed_in_openapi(setup):
    client, _, _ = setup
    assert "/v1/billing/verify" in client.get("/openapi.json").json()["paths"]
