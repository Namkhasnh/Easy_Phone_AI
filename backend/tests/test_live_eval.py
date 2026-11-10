"""1B.15: the live-eval scorer itself (CI, no cost). Every golden fixture scores 100 % against its own `expected`."""

import copy
import json
from pathlib import Path

import pytest

from tests.live_eval import CaseResult, ModelRun, fuzzy_equal, report, score, summary

GOLDEN = Path(__file__).parent / "fixtures" / "prompts"
FILES = sorted(GOLDEN.glob("parse.*.json"))


def load(name: str) -> dict:
    return json.loads((GOLDEN / f"parse.{name}.json").read_text("utf-8"))


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem)
def test_expected_scores_itself(path):
    g = json.loads(path.read_text("utf-8"))
    actual = copy.deepcopy(g["expected"])
    if (g.get("liveMatch") or {}).get("followUpQuestion") == "present" and not actual["followUpQuestion"]:
        actual["followUpQuestion"] = "?"
    assert score(g["expected"], actual, g.get("liveMatch")) == []


def test_date_same_instant_other_offset_passes_wrong_hour_fails():
    g = load("E1")
    a = copy.deepcopy(g["expected"])
    f = next(f for f in a["steps"][0]["fields"] if f["id"] == "startDate")
    f["value"] = "2026-11-09T02:00:00+00:00"
    assert score(g["expected"], a) == []
    f["value"] = "2026-11-09T10:00:00+07:00"
    assert score(g["expected"], a) == ["step0.startDate: mismatch"]


def test_text_is_fuzzy():
    assert fuzzy_equal("Khám răng", "khám răng ở nha khoa")
    assert fuzzy_equal("Nha khoa An Bình", "nha khoa An Binh")
    assert not fuzzy_equal("Uống thuốc", "Gọi mẹ")


def test_wrong_kind_extra_step_missing_field_invented_value():
    g = load("E1")
    a = copy.deepcopy(g["expected"])
    a["steps"][0]["kind"] = "reminder"
    assert score(g["expected"], a) == ["step0: kind/operation"]
    a = copy.deepcopy(g["expected"])
    a["steps"].append(copy.deepcopy(a["steps"][0]))
    assert score(g["expected"], a) == ["steps: count 2 ≠ 1"]
    a = copy.deepcopy(g["expected"])
    a["steps"][0]["fields"] = [f for f in a["steps"][0]["fields"] if f["id"] != "location"]
    assert score(g["expected"], a) == ["step0.location: missing"]
    nulls = [(p, s, f) for p in FILES for s in json.loads(p.read_text("utf-8"))["expected"]["steps"]
             for f in s["fields"] if f["value"] is None]
    path, _, field = nulls[0]
    g = json.loads(path.read_text("utf-8"))
    a = copy.deepcopy(g["expected"])
    for s in a["steps"]:
        for f in s["fields"]:
            if f["id"] == field["id"] and f["value"] is None:
                f["value"], f["confidence"] = "x", 0.5
    assert any(x.endswith(": invented value") for x in score(g["expected"], a))


def test_unsupported_needs_message_and_no_steps():
    g = load("booking")
    assert g["expected"]["unsupported"] is not None
    a = copy.deepcopy(g["expected"])
    a["unsupported"]["message"] = "Không được"
    assert score(g["expected"], a) == ["unsupported: missing or message"]
    a = copy.deepcopy(g["expected"])
    a["unsupported"]["reason"] = "other"
    assert score(g["expected"], a) == ["unsupported: reason"]
    assert score(load("E1")["expected"], g["expected"]) == ["unexpected unsupported"]


def test_every_case_has_a_group():
    from tests.live_eval import group_of
    for p in FILES:
        assert group_of(p.stem.split(".", 1)[1])


def test_report_has_no_user_content():
    g = load("E1")
    run = ModelRun("m", 1, "2026-11-10", [
        CaseResult("E1", "examples E1–E8", False, ["step0.title: mismatch"], None, 900, 10, 5, 0.001),
        CaseResult("E2", "examples E1–E8", True, [], None, 1100, 10, 5, 0.001),
    ])
    text = report(run) + summary([run, ModelRun.from_json(run.to_json())])
    assert "1/2" in text and "p50 1100 ms" in text
    assert g["request"]["text"] not in text
    for f in g["expected"]["steps"][0]["fields"]:
        assert str(f["value"]) not in text
