"""Eval 2026-11-27 fixes in `parse_service.post_process` (no model): words the user said fill `mapsApp` /
`snoozeOption` when the model left them out; a passed day / month moved to next year without a year word gets a low
confidence so the app asks (D-106)."""


import pytest

from app.config import Settings
from app.schemas.parse import ParseRequest
from app.services import parse_service as p

NOW = "2026-11-08T18:07:00+07:00"


def req(text: str) -> ParseRequest:
    return ParseRequest.model_validate({
        "schemaVersion": 1, "text": text, "inputMode": "text", "now": NOW, "timezone": "Asia/Ho_Chi_Minh",
        "locale": "vi-VN", "savedPlaceLabels": [], "context": {"draftId": None, "answeringFieldId": None,
                                                                "currentDraft": None}})


def run(text: str, kind: str, op: str, fields: list[dict]) -> dict:
    raw = {"steps": [{"kind": kind, "operation": op, "fields": fields, "dateCandidates": []}],
           "followUpQuestion": None, "unsupported": None}
    out = p.post_process(raw, req(text), Settings())
    return {f["id"]: f for f in out["steps"][0]["fields"]}


def f(fid, value, conf=0.9, quote=None):
    return {"id": fid, "value": value, "confidence": conf, "sourceQuote": quote}


@pytest.mark.parametrize("text,app", [("Mở Google Maps tìm bệnh viện gần nhất", "googleMaps"),
                                      ("mở google map chỉ đường về nhà", "googleMaps"),
                                      ("Dùng Apple Maps tìm cây xăng", "appleMaps")])
def test_maps_app_from_the_words(text, app):
    got = run(text, "place", "open", [f("query", "bệnh viện")])
    assert got["mapsApp"]["value"] == app


def test_maps_app_never_overrides_the_model():
    got = run("Mở Google Maps tìm chợ", "place", "open", [f("query", "chợ"), f("mapsApp", "appleMaps")])
    assert got["mapsApp"]["value"] == "appleMaps"


def test_no_maps_word_no_field():
    assert "mapsApp" not in run("Tìm bệnh viện gần nhất", "place", "open", [f("query", "bệnh viện")])


@pytest.mark.parametrize("text,option", [("Hoãn lời nhắc uống thuốc thêm 15 phút", "min15"),
                                         ("Để 1 tiếng nữa nhắc lại", "hour1"),
                                         ("Hoãn sang sáng mai", "tomorrowMorning")])
def test_snooze_from_the_words(text, option):
    got = run(text, "reminder", "snooze", [f("title", "Uống thuốc")])
    assert got["snoozeOption"]["value"] == option


@pytest.mark.parametrize("text,value,expected", [
    ("Nhắc tôi 5/11 9 giờ đóng tiền điện", "2027-11-05T09:00:00+07:00", 0.5),      # 3 days ago → asks
    ("Nhắc tôi 5/11/2027 9 giờ đóng tiền điện", "2027-11-05T09:00:00+07:00", 0.9),  # year said
    ("Nhắc tôi 5/11 năm sau đóng tiền", "2027-11-05T09:00:00+07:00", 0.9),          # "năm sau" said
    ("Nhắc tôi 10/1 đóng học phí", "2027-01-10T09:00:00+07:00", 0.9),               # 302 days ago: plain next one
    ("Nhắc tôi 20/11 đóng tiền", "2026-11-20T09:00:00+07:00", 0.9),                 # this year, ahead
])
def test_passed_date_moved_to_next_year_asks(text, value, expected):
    got = run(text, "reminder", "create", [f("title", "Đóng tiền"), f("dueDate", value)])
    assert got["dueDate"]["confidence"] == expected
