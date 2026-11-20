"""D-323: hard parse requests get `PARSE_HARD_REASONING_EFFORT`, easy ones stay on `LLM_REASONING_EFFORT`."""

import asyncio
import json
from pathlib import Path

import pytest

from app.config import Settings
from app.services import parse_service
from app.services.parse_service import is_hard

HARD = [
    "Nhắc tôi 2 giờ uống thuốc",                      # bare hour
    "Nhắc tôi 3/4 2 giờ nộp hồ sơ",                   # numeric date
    "Chủ nhật 3 giờ chiều đi đám cưới",
    "Thứ 7 9h sáng đi khám răng",
    "Hủy lịch nha sĩ thứ Sáu",
    "Lưu địa chỉ 25 Nguyễn Huệ, quận 1 là nhà con trai",
    "Họp tuần sau 9 giờ sáng",
    "mai nhắc tôi 7 giờ sáng uống thuốc 8 giờ sáng đi chợ",   # several hours
    "Nhắc tôi mùng 1 đi chùa lúc 6 giờ sáng",
]
EASY = [
    "Gọi cho mẹ",
    "Nhắn anh Minh là chiều nay em đến muộn",
    "Mai 3 giờ chiều đi siêu thị",
    "Nhắc tôi 9h30 tối gọi bố",
    "Chỉ đường đến sân bóng học viện kĩ thuật mật mã",
    "Soạn email trả lời cô Lan là em đồng ý",
]


@pytest.mark.parametrize("text", HARD)
def test_hard(text):
    assert is_hard(text)


@pytest.mark.parametrize("text", EASY)
def test_easy(text):
    assert not is_hard(text)


def test_every_failing_eval_date_case_is_routed_as_hard():
    """The cases that "none" got wrong and "low" fixed on 2026-11-19 (evals/…speed-low-subset)."""
    fixtures = Path(__file__).parent / "fixtures" / "prompts"
    for case in ["date_bare_hour_future", "date_day_month_order", "date_sunday_future", "date_sunday_passed",
                 "long_dictation", "x_place_save_custom"]:
        g = next(json.loads(p.read_text("utf-8")) for p in fixtures.glob("parse.*.json")
                 if json.loads(p.read_text("utf-8"))["case"] == case)
        assert is_hard(g["request"]["text"]), case


class _Capture:
    def __init__(self):
        self.calls = []

    async def structured(self, call, validate, budget, meter):
        self.calls.append(call)
        return {"steps": [], "followUpQuestion": None, "unsupported": {"reason": "other", "message": "x", "date": None}}


@pytest.mark.parametrize(("text", "effort"), [("Chủ nhật 3 giờ chiều đi đám cưới", "low"), ("Gọi cho mẹ", None)])
def test_parse_passes_the_override(text, effort, monkeypatch):
    fixture = json.loads((Path(__file__).parent / "fixtures" / "contract" / "parse.sms.request.json").read_text("utf-8"))
    fixture["text"] = text
    req = parse_service.ParseRequest.model_validate(fixture)
    monkeypatch.setattr(parse_service, "post_process", lambda raw, req, settings: raw)
    llm = _Capture()
    asyncio.run(parse_service.parse(req, Settings(), llm, None, None))
    assert llm.calls[0].reasoning_effort == effort
