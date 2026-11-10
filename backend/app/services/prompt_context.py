"""`<request_context>` block (AI_PROMPTS §1.1, D-058, D-254, D-056).

The backend computes every date (14-day calendar table) with `zoneinfo`; the LLM only looks dates up.
🔒 `deviceOnly` fields and `appBuilt` fields are never listed to the model.
"""

import json
from datetime import datetime, timedelta
from functools import lru_cache
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from app.services.untrusted import neutralize, wrap_current_draft

CATALOG_PATH = Path(__file__).resolve().parent.parent / "schemas" / "field_catalog.json"
CALENDAR_DAYS = 14  # AI_PROMPTS §1.1

# Monday = 0 (datetime.weekday()).
WEEKDAYS_VI = ["Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy", "Chủ nhật"]
DAY_NOTES_VI = {0: "hôm nay", 1: "mai", 2: "ngày kia"}


@lru_cache
def load_catalog() -> dict[str, Any]:
    return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))


def calendar_rows(now: datetime, tz_name: str, days: int = CALENDAR_DAYS) -> list[str]:
    """`2026-11-08 Chủ nhật (hôm nay)`, … — `days` rows starting at the local date of `now` in `tz_name`."""
    today = now.astimezone(ZoneInfo(tz_name)).date()
    rows = []
    for i in range(days):
        d = today + timedelta(days=i)
        note = DAY_NOTES_VI.get(i)
        rows.append(f"{d.isoformat()} {WEEKDAYS_VI[d.weekday()]}" + (f" ({note})" if note else ""))
    return rows


def catalog_lines(enabled_kinds: list[str], catalog: dict[str, Any] | None = None) -> list[str]:
    """`calendarEvent.create: title*, startDate*, endDate, …` for every enabled kind × operation (* = required).

    A field is listed when it is not 🔒 `deviceOnly`, not `appBuilt`, and allowed for that operation.
    """
    # TODO(spec): AI_PROMPTS §1.1 does not say how `conditional` required fields are shown; they are listed unstarred.
    lines = []
    for kind in (catalog or load_catalog())["kinds"]:
        if kind["kind"] not in enabled_kinds:
            continue
        for req in kind["required"]:
            op = req["operation"]
            names = []
            for f in kind["fields"]:
                if f["deviceOnly"] or f["appBuilt"]:
                    continue
                if "operations" in f and op not in f["operations"]:
                    continue
                names.append(f["id"] + ("*" if f["id"] in req["fields"] else ""))
            lines.append(f"{kind['kind']}.{op}: {', '.join(names)}")
    return lines


def _label(text: str) -> str:
    """Saved-place labels are user text: neutralized and kept on one line (no `,` / newline that breaks the list)."""
    return " ".join(neutralize(text).replace(",", " ").split())


def build_request_context(
    *,
    now: datetime,
    tz_name: str,
    locale: str,
    enabled_kinds: list[str],
    saved_place_labels: list[str],
    answering_field_id: str | None = None,
    current_draft: dict[str, Any] | None = None,
) -> str:
    """The `developer` message (AI_PROMPTS §1, layer 2). `now` must be aware (D-058)."""
    if now.tzinfo is None:
        raise ValueError("now must have an offset (D-058)")
    if answering_field_id is not None and not answering_field_id.isalnum():
        raise ValueError("answering_field_id must be a catalog id")  # never client text in the trusted block
    local = now.astimezone(ZoneInfo(tz_name))
    today = local.date()
    labels = [lbl for lbl in (_label(x) for x in saved_place_labels) if lbl]
    lines = [
        "<request_context>",
        f"now: {local.isoformat(timespec='seconds')}",
        f"timezone: {tz_name}",
        f"today: {WEEKDAYS_VI[today.weekday()]} {today.strftime('%d/%m/%Y')}",
        f"locale: {locale}",
        f"enabled_kinds: {', '.join(enabled_kinds)}",
        f"saved_place_labels: {', '.join(labels)}",  # TODO(spec): empty list shown as an empty value
        "calendar_next_14_days:",
        *(f"  {row}" for row in calendar_rows(now, tz_name)),
        "field_catalog:",
        *(f"  {line}" for line in catalog_lines(enabled_kinds)),
        f"answering_field: {answering_field_id or 'null'}",
        "</request_context>",
    ]
    block = "\n".join(lines)
    if answering_field_id and current_draft is not None:
        # TODO(spec): AI_PROMPTS §1.1 does not fix the <current_draft> format or message; compact JSON, same message.
        draft = json.dumps(current_draft, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        block += "\n" + wrap_current_draft(draft)
    return block
