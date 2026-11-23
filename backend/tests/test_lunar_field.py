"""4L.3 (D-332): `lunarDate` encoding `[YYYY-]MM-DD[L][THH:mm]` — same cases as Swift `LunarFieldValueTests`."""

import pytest

from app.services.parse_service import _encoded

FIELD = {"id": "lunarDate", "type": "lunarDate"}


@pytest.mark.parametrize("value", ["03-10", "06-01L", "00-15", "00-01T06:00", "2027-03-10", "12-30T18:30", "01-01"])
def test_valid(value: str) -> None:
    assert _encoded(value, FIELD, "calendarEvent")


@pytest.mark.parametrize(
    "value",
    ["3-10", "13-01", "03-31", "03-00", "00-15L", "2027-00-15", "03-10T24:00", "03-10T06:60", "10/3", "",
     "2027-03-10L ", "1700-03-10", "03-10t06:00"],
)
def test_invalid(value: str) -> None:
    assert not _encoded(value, FIELD, "calendarEvent")
