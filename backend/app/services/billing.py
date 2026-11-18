"""`POST /v1/billing/verify` rules (API_CONTRACT §8.1, D-083, D-085, D-239, D-240, D-284).

The JWS signature is always checked with the key of the leaf certificate in its `x5c` header. Apple environments
also need the Apple root chain (not built: the thesis has no App Store Connect, D-284 → `billing_invalid`).
`Xcode` transactions (local `.storekit`, Debug) are accepted only with `ALLOW_XCODE_STOREKIT=true`, and their leaf
certificate is pinned on first use (config comment). Never logs the JWS or ids of the Apple account (D-059).
"""

import base64
import hashlib
import logging
from datetime import UTC, datetime
from pathlib import Path

import asyncpg
import jwt
from cryptography import x509

from app.config import Settings
from app.errors import AppError
from app.repositories import subscriptions

logger = logging.getLogger("easyphone.billing")
BACKEND_DIR = Path(__file__).resolve().parents[2]


def _invalid(reason: str) -> AppError:
    logger.info("billing invalid reason=%s", reason)
    return AppError("billing_invalid", 400, False)


def _leaf(jws: str) -> x509.Certificate:
    try:
        header = jwt.get_unverified_header(jws)
        chain = header.get("x5c") or []
        if header.get("alg") != "ES256" or not chain:
            raise _invalid("header")
        return x509.load_der_x509_certificate(base64.b64decode(chain[0]))
    except AppError:
        raise
    except (jwt.PyJWTError, ValueError, TypeError):
        raise _invalid("header") from None


def _pin_xcode(cert: x509.Certificate, settings: Settings) -> None:
    """Trust on first use for the owner's Xcode signing certificate (dev backend only)."""
    fingerprint = hashlib.sha256(cert.public_bytes(encoding=_der())).hexdigest()
    path = BACKEND_DIR / settings.XCODE_STOREKIT_PIN_FILE
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(fingerprint + "\n", encoding="utf-8")
        logger.info("billing pinned xcode storekit leaf certificate")
        return
    if path.read_text(encoding="utf-8").strip() != fingerprint:
        raise _invalid("xcodeCertificate")


def _der():
    from cryptography.hazmat.primitives.serialization import Encoding
    return Encoding.DER


def decode(jws: str, settings: Settings) -> dict:
    """Step 1–2: signature, environment, bundle, product. Returns the transaction payload."""
    cert = _leaf(jws)
    try:
        payload = jwt.decode(jws, key=cert.public_key(), algorithms=["ES256"],
                             options={"verify_aud": False, "verify_exp": False, "verify_iat": False})
    except jwt.PyJWTError:
        raise _invalid("signature") from None
    environment = payload.get("environment")
    if environment not in settings.ALLOWED_ENVIRONMENTS:
        raise _invalid("environment")
    if environment == "Xcode":
        if not settings.ALLOW_XCODE_STOREKIT:
            raise _invalid("xcodeNotAllowed")
        _pin_xcode(cert, settings)
    else:
        # TODO(spec): Apple root chain (App Store Server Library) for Sandbox / Production — no paid account (D-284).
        raise _invalid("appleChainNotBuilt")
    if payload.get("bundleId") != settings.APP_BUNDLE_ID or payload.get("productId") not in settings.PRODUCT_IDS:
        raise _invalid("bundleOrProduct")
    if not payload.get("originalTransactionId"):
        raise _invalid("noOriginalTransaction")
    return payload


def _when(ms) -> datetime | None:
    return datetime.fromtimestamp(int(ms) / 1000, UTC) if ms else None


def status_of(payload: dict, now: datetime) -> tuple[str, datetime | None]:
    expires = _when(payload.get("expiresDate"))
    if payload.get("revocationDate"):
        return "revoked", expires
    return ("active" if expires and expires > now else "expired"), expires


async def verify(conn: asyncpg.Connection, user_id: str, jws: str, settings: Settings, now: datetime) -> None:
    """Steps 1–4 of API_CONTRACT §8.1; the caller answers with `MeResponse` (step 5)."""
    payload = decode(jws, settings)
    token = str(payload.get("appAccountToken") or "").lower()
    original = str(payload["originalTransactionId"])
    if token != user_id:
        # D-239: the purchase belonged to an account that no longer exists → it moves to this user.
        if not token or await subscriptions.user_exists(conn, token):
            logger.info("billing account mismatch")
            raise AppError("billing_account_mismatch", 403, False)
    owner = await subscriptions.owner_of(conn, original)
    if owner and owner != user_id and await subscriptions.user_exists(conn, owner):
        logger.info("billing account mismatch (row owner)")
        raise AppError("billing_account_mismatch", 403, False)
    status, expires = status_of(payload, now)
    await subscriptions.upsert(conn, user_id, payload["productId"], original, expires, status, payload["environment"])
    logger.info("billing verified status=%s environment=%s", status, payload["environment"])
