"""4L.3 (D-332): `lunarDate` encoding `[YYYY-]MM-DD[L][THH:mm]` — same cases as Swift `LunarFieldValueTests`."""

import pytest

from app.services.parse_service import _encoded

FIELD = {"id": "lunarDate", "type": "lunarDate"}


@pytest.mark.parametrize("value", ["03-10", "06-01L", "00-15", "00-01T06:00", "2027-03-10", "12-30T18:30", "01-01", "N0-15", "N1-01T06:00", "NX-05"])
def test_valid(value: str) -> None:
    assert _encoded(value, FIELD, "calendarEvent")


@pytest.mark.parametrize(
    "value",
    ["3-10", "13-01", "03-31", "03-00", "00-15L", "2027-00-15", "03-10T24:00", "03-10T06:60", "10/3", "",
     "2027-03-10L ", "1700-03-10", "03-10t06:00", "N2-15", "N0-15L", "2027-N1-15", "NX-31"],
)
def test_invalid(value: str) -> None:
    assert not _encoded(value, FIELD, "calendarEvent")


def test_solar_date_dropped_when_lunar_given() -> None:
    """D-332: the LLM never gives the solar date of a lunar request; post-processing clears it and its candidates."""
    from app.config import Settings
    from app.schemas.parse import ParseRequest
    from app.services.parse_service import post_process

    req = ParseRequest.model_validate({
        "schemaVersion": 1, "text": "giỗ ông 10/3 âm", "inputMode": "text", "now": "2026-11-23T10:00:00+07:00",
        "timezone": "Asia/Ho_Chi_Minh", "locale": "vi-VN", "savedPlaceLabels": [],
        "context": {"draftId": None, "answeringFieldId": None, "currentDraft": None},
    })
    raw = {"steps": [{"kind": "calendarEvent", "operation": "create", "fields": [
        {"id": "title", "value": "Giỗ ông", "confidence": 0.9, "sourceQuote": "giỗ ông"},
        {"id": "startDate", "value": "2027-04-16T00:00:00+07:00", "confidence": 0.5, "sourceQuote": None},
        {"id": "lunarDate", "value": "03-10", "confidence": 0.95, "sourceQuote": "10/3 âm"},
        {"id": "lunarRecurrence", "value": "yearly", "confidence": 0.9, "sourceQuote": "giỗ"}],
        "dateCandidates": [{"fieldId": "startDate", "value": "2027-04-16T00:00:00+07:00", "label": "x"}]}],
        "followUpQuestion": None, "unsupported": None}
    out = post_process(raw, req, Settings())
    fields = {f["id"]: f for f in out["steps"][0]["fields"]}
    assert fields["startDate"]["value"] is None and fields["startDate"]["confidence"] is None
    assert fields["lunarDate"]["value"] == "03-10" and out["steps"][0]["dateCandidates"] == []
