"""Untrusted-content marking (AI_PROMPTS §2, D-057). Every non-system text reaches the LLM only through here.

Attribute values are only values the backend controls (`source`, `messageId`); never content.
Span offsets (`/v1/extract`) are computed on the **original** text, never on the neutralized copy (§2.2).
"""

import re
import unicodedata

# `<` or full-width `＜` in front of one of OUR tag names (any case, optional spaces / slash).
TAG_RE = re.compile(r"[<＜]\s*/?\s*(untrusted_content|user_request|current_draft|request_context)", re.I)
# Control chars except \n and \t (category Cc). NUL included.
_CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f]")
_ATTR_VALUE = re.compile(r"^[A-Za-z0-9_.:-]{1,64}$")


def neutralize(text: str, max_chars: int | None = None) -> str:
    """NFC, strip control chars, break lookalikes of our tags (`<` → `‹`, U+2039), cap length (D-238)."""
    clean = _CONTROL.sub("", unicodedata.normalize("NFC", text))
    if max_chars is not None:
        clean = clean[:max_chars]
    return TAG_RE.sub(lambda m: "‹" + m.group(0)[1:], clean)


def wrap_untrusted(text: str, source: str, max_chars: int | None = None, **attrs: str) -> str:
    """`<untrusted_content source="ocr">…</untrusted_content>` (§2.1: ocr, email, web)."""
    pairs = {"source": source, **attrs}
    for key, value in pairs.items():
        if not _ATTR_VALUE.match(value):  # ids we generated only; content in an attribute is a bug
            raise ValueError(f"unsafe attribute {key}")
    a = " ".join(f'{k}="{v}"' for k, v in pairs.items())
    return f"<untrusted_content {a}>\n{neutralize(text, max_chars)}\n</untrusted_content>"


def wrap_user_request(text: str, max_chars: int | None = None) -> str:
    """The user's own request: trusted as intent, still neutralized (§2.2)."""
    return f"<user_request>\n{neutralize(text, max_chars)}\n</user_request>"


def wrap_current_draft(text: str) -> str:
    """Field values from an earlier step: data only (§2.1)."""
    return f"<current_draft>\n{neutralize(text)}\n</current_draft>"
