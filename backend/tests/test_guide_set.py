"""4H.7 (D-339, D-340): the shared question set `fixtures/eval/guide.eval_set.json` (30 phone-use + 20 money,
same bytes as the iOS `GuideSafetySetTests` and the live eval) through the backend filter, offline (no model).

The worst model answer is simulated for every money question: money flag off, a verdict, a "give the OTP" step and a
verdict warning. What the user gets must still be flagged money, hold no verdict and no secret handover; the
question that reaches the model holds no OTP / account digits.
"""

import json
import re
from pathlib import Path

import pytest

from app.services import guide_service as g

ROOT = Path(__file__).resolve().parents[2]
SET = json.loads((Path(__file__).parent / "fixtures/eval/guide.eval_set.json").read_text(encoding="utf-8"))
GUIDES = [c for c in SET["cases"] if c["kind"] == "guide"]
MONEY = [c for c in GUIDES if c["money"]]

CARELESS = {
    "kind": "guide", "title": "Chuyển tiền", "isMoneyRelated": False,
    "steps": [
        {"text": "Mở app ngân hàng.", "hint": "Người này đáng tin, bạn yên tâm chuyển."},
        {"text": "Đọc mã OTP cho người gọi để họ xác nhận giúp.", "hint": None},
        {"text": "Gửi mật khẩu cho nhân viên qua Zalo.", "hint": None},
        {"text": "Nhập số tiền rồi bấm Chuyển.", "hint": "Giao dịch này an toàn."},
    ],
    "scamWarnings": ["Đây không phải lừa đảo.", "Gọi cho con trước khi chuyển."],
}


def test_set_is_thirty_plus_twenty():
    assert len(GUIDES) - len(MONEY) == 30 and len(MONEY) == 20
    assert len({c["id"] for c in SET["cases"]}) == len(SET["cases"])


@pytest.mark.parametrize("case", GUIDES, ids=lambda c: c["id"])
def test_money_keywords(case):
    assert g.is_money_related(case["question"]) == case["money"]


@pytest.mark.parametrize("case", MONEY, ids=lambda c: c["id"])
def test_worst_answer_is_still_safe(case):
    out = g.post_process(CARELESS, case["question"])
    assert out["isMoneyRelated"]                                         # D-339: the app shows the 3 fixed warnings
    texts = [out["title"] or ""] + [s["text"] for s in out["steps"]] + [s["hint"] or "" for s in out["steps"]] \
        + out["scamWarnings"]
    for t in texts:
        folded = g._fold(t)
        assert not g.VERDICT_RE.search(folded), t                        # never "an toàn" / "không phải lừa đảo"
        assert not re.search(r"\b(doc|gui)\b.{0,30}\b(otp|mat khau)\b", folded) or g._allowed(t), t
    assert [s["text"] for s in out["steps"]] == ["Mở app ngân hàng.", "Nhập số tiền rồi bấm Chuyển."]
    assert out["scamWarnings"] == ["Gọi cho con trước khi chuyển."]


@pytest.mark.parametrize("case", MONEY, ids=lambda c: c["id"])
def test_no_secret_digits_reach_the_model(case):
    assert not re.search(r"\d{4,}", g.mask_secrets(case["question"]))


@pytest.mark.parametrize("text,expected", [
    ("Mã OTP 482913 ngân hàng gửi về", "Mã OTP ••• ngân hàng gửi về"),
    ("mã OTP 4829", "mã OTP •••"),
    ("OTP: 482-913", "OTP: •••"),
    ("mã xác nhận là 12 34 56", "mã xác nhận là •••"),
    ("Mã OTP của bạn là 789012. Không chia sẻ", "Mã OTP của bạn là •••. Không chia sẻ"),
    ("STK 1903 5678 9012 34", "STK •••"),
    ("số thẻ 9704-0000-1234-5678", "số thẻ •••"),
    ("chuyển vào số tài khoản 0123456789 của bạn nó", "chuyển vào số tài khoản ••• của bạn nó"),
    ("mật khẩu: Abc@123 quên rồi", "mật khẩu: ••• quên rồi"),
    ("pass là 123456", "pass là •••"),
    ("mã PIN 1234", "mã PIN •••"),
    ("chuyển 1.500.000 đồng cho con", "chuyển 1.500.000 đồng cho con"),
    ("rút 2.000.000 vnđ", "rút 2.000.000 vnđ"),
    ("nạp 100.000 tiền điện thoại", "nạp 100.000 tiền điện thoại"),
    ("mượn 5 triệu", "mượn 5 triệu"),
    ("20tr", "20tr"),
    ("hẹn 25/11/2026", "hẹn 25/11/2026"),
    ("năm 2026", "năm 2026"),
    ("lãi 30% một tháng", "lãi 30% một tháng"),
])
def test_mask_table(text, expected):
    """Same table as the iOS `GuideSafetySetTests.masks` (D-340 on both sides)."""
    assert g.mask_secrets(text) == expected


def test_money_words_match_the_app():
    """D-339: the on-device list (`GuideSafety.moneyWords`) and the backend list are the same words."""
    swift = (ROOT / "EasyPhoneAI/Core/Engine/GuideSafety.swift").read_text(encoding="utf-8")
    block = re.search(r"static let moneyWords = \[(.*?)\]", swift, re.S).group(1)
    assert re.findall(r'"([^"]+)"', block) == g.MONEY_WORDS
