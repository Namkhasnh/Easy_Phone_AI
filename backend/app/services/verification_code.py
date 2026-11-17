"""Verification codes in new mail (D-311). A fixed rule, never the LLM (it could misread or invent a code).

A code = 4–8 digits (optionally written "G-123456") or 6–8 capital letters + digits, within a short window
around a keyword ("mã", "code", "OTP", "xác minh", "verification", …). Years (1900–2099 as 4 digits) are skipped.
Never logged (D-059).
"""

import re
import unicodedata
from datetime import datetime, timedelta

_KEYWORD = re.compile(
    r"\b(m[aã]|code|otp|passcode|pin|x[aá]c (minh|th[uự]c|nh[aậ]n)|verification|verify|security|m[aậ]t kh[aẩ]u)\b",
    re.IGNORECASE,
)
# Not glued to other word / number / link characters; a sentence dot right after the code is fine.
_TOKEN = re.compile(r"(?<![\w./=+-])(?:[A-Z]-)?(\d{4,8}|(?=[A-Z0-9]*\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{6,8})(?![\w/=-]|\.\w)")
_BEFORE, _AFTER = 40, 120
# "mã đơn hàng", "mã giảm giá", "mã vận đơn"… are order / coupon numbers, not sign-in codes.
_NOT_A_CODE = re.compile(r"\s*(đơn|giảm|vận|khuyến|bưu|số thuế|sản phẩm|khách hàng|nhân viên|order|coupon|promo|tracking)",
                         re.IGNORECASE)


def _is_year(token: str) -> bool:
    return len(token) == 4 and token.isdigit() and 1900 <= int(token) <= 2099


def find(subject: str, body: str) -> str | None:
    """The code nearest after a keyword (else just before it). Subject and body are read as one text, so a keyword
    in the subject finds a code at the start of the body."""
    text = unicodedata.normalize("NFC", f"{subject}\n{body}")
    tokens = [(m.start(1), m.group(1)) for m in _TOKEN.finditer(text) if not _is_year(m.group(1))]
    for kw in _KEYWORD.finditer(text):
        if _NOT_A_CODE.match(text, kw.end()):
            continue
        after = [t for pos, t in tokens if kw.end() <= pos <= kw.end() + _AFTER]
        before = [t for pos, t in tokens if kw.start() - _BEFORE <= pos < kw.start()]
        if after or before:
            return (after or list(reversed(before)))[0]
    return None


def recent_code(subject: str, body: str, received_at: datetime, now: datetime, max_age_minutes: int) -> str | None:
    """Only for mail younger than `max_age_minutes`: an old code is useless and should not linger on screen."""
    if now - received_at > timedelta(minutes=max_age_minutes):
        return None
    return find(subject, body)
