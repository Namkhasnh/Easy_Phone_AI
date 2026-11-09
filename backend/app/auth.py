"""Supabase JWT verification (API_CONTRACT §2, D-032).

Primary path: asymmetric keys (ES256/RS256) from the project JWKS. Fallback: HS256 with `SUPABASE_JWT_SECRET`.
Never log the token (D-059).
"""

import logging
import uuid
from dataclasses import dataclass
from functools import lru_cache

import jwt
from jwt import PyJWKClient, PyJWKClientConnectionError, PyJWKClientError

from app.config import Settings
from app.errors import AppError

logger = logging.getLogger("easyphone.auth")

ASYMMETRIC_ALGS = {"ES256", "RS256"}


@dataclass(frozen=True)
class CurrentUser:
    id: str  # lowercase UUID = JWT `sub`


def _unauthorized() -> AppError:
    return AppError("unauthorized", 401, False)


@lru_cache
def _jwks_client(url: str) -> PyJWKClient:
    return PyJWKClient(url, cache_keys=True)  # keys cached per process


def _jwks_url(settings: Settings) -> str:
    if not settings.SUPABASE_URL:
        logger.error("auth misconfigured: SUPABASE_URL missing for JWKS")
        raise AppError("internal", 500, True)
    return settings.SUPABASE_URL.rstrip("/") + "/auth/v1/.well-known/jwks.json"


def _signing_key(token: str, alg: str, settings: Settings) -> object:
    if alg in ASYMMETRIC_ALGS:
        try:
            return _jwks_client(_jwks_url(settings)).get_signing_key_from_jwt(token).key
        except PyJWKClientConnectionError:
            logger.error("auth jwks fetch failed")
            raise AppError("internal", 500, True) from None
        except (PyJWKClientError, jwt.PyJWTError):
            raise _unauthorized() from None
    if alg == "HS256" and settings.SUPABASE_JWT_SECRET is not None:
        return settings.SUPABASE_JWT_SECRET.get_secret_value()
    raise _unauthorized()  # unknown alg, `none`, or HS256 without a secret


def verify_token(token: str, settings: Settings) -> CurrentUser:
    try:
        alg = jwt.get_unverified_header(token).get("alg", "")
    except jwt.PyJWTError:
        raise _unauthorized() from None
    key = _signing_key(token, alg, settings)
    try:
        claims = jwt.decode(
            token,
            key,
            algorithms=[alg],
            audience=settings.JWT_AUDIENCE,
            options={"require": ["exp", "sub", "aud"]},
        )
        return CurrentUser(id=str(uuid.UUID(str(claims["sub"]))))
    except (jwt.PyJWTError, ValueError) as exc:
        logger.info("auth rejected: %s", type(exc).__name__)
        raise _unauthorized() from None
