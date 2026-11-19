"""Refresh tokens are stored only Fernet-encrypted (D-151, API_GMAIL.md §2). Key = env `GMAIL_TOKEN_KEY`."""

import logging

from cryptography.fernet import Fernet, InvalidToken

from app.config import Settings
from app.errors import AppError

logger = logging.getLogger("easyphone.gmail")


def _fernet(settings: Settings) -> Fernet:
    if settings.GMAIL_TOKEN_KEY is None:
        logger.error("gmail misconfigured: GMAIL_TOKEN_KEY missing")
        raise AppError("internal", 500, True)
    try:
        return Fernet(settings.GMAIL_TOKEN_KEY.get_secret_value())
    except ValueError:
        logger.error("gmail misconfigured: GMAIL_TOKEN_KEY is not a Fernet key")
        raise AppError("internal", 500, True) from None


def encrypt(token: str, settings: Settings) -> bytes:
    return _fernet(settings).encrypt(token.encode())


def decrypt(blob: bytes, settings: Settings) -> str | None:
    """None when the key changed (the account then needs a reconnect, never a crash)."""
    try:
        return _fernet(settings).decrypt(bytes(blob)).decode()
    except InvalidToken:
        logger.warning("gmail token not decryptable (key changed?)")
        return None
