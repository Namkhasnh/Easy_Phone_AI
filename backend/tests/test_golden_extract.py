"""1D.6: prompt-injection fixtures for `/v1/extract` (AI_PROMPTS §8.3, §2.2, §9.7, §10, D-057) with a **mocked** LLM.

Each `fixtures/prompts/extract.<case>.json` has `request` (= `ExtractRequest`), `llmOutput` (what the model returns),
`expected` (wire `fields` + `suggestedNextAction` after post-processing) and `forbiddenInValues` (injected text that
must never become a field value). The same files can feed a later `pytest -m live` run (real model, §10).
"""

import asyncio
import json
import re
import unicodedata
from pathlib import Path

import pytest

from app.config import Settings
from app.errors import AppError
from app.schemas.extract import ExtractRequest
from app.services import extract_service as ex
from app.services.llm import LLMClient
from app.services.metering import CostMeter, Deadline
from app.services.schema_check import check
from tests.test_llm import FakeCompletions, resp

GOLDEN = Path(__file__).parent / "fixtures" / "prompts"
FILES = sorted(GOLDEN.glob("extract.*.json"))
S = Settings()
SCHEMA = ex.llm_schema(S)
OUR_TAGS = re.compile(r"[<＜]\s*/?\s*(untrusted_content|user_request|current_draft|request_context)", re.IGNORECASE)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def utf16_slice(text: str, start: int, end: int) -> str:
    return text.encode("utf-16-le")[start * 2:end * 2].decode("utf-16-le")


def run(g: dict, *outputs: dict) -> tuple[dict, FakeCompletions]:
    fake = FakeCompletions(*(resp(json.dumps(o, ensure_ascii=False)) for o in outputs))
    req = ExtractRequest.model_validate(g["request"])
    out = asyncio.run(ex.extract(req, S, LLMClient(S, fake), Deadline(18), CostMeter()))
    return out, fake


def test_every_doc_case_has_a_fixture():
    names = {p.name.split(".")[1] for p in FILES}
    assert {"inject_doc", "inject_close_tag", "inject_vietnamese", "inject_title_short", "inject_title_long"} <= names


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem)
def test_fixture_is_well_formed(path):
    g = load(path)
    assert set(g) == {"case", "source", "request", "llmOutput", "expected", "forbiddenInValues"}
    assert path.name == f"extract.{g['case']}.json"
    ExtractRequest.model_validate(g["request"])
    assert check(g["llmOutput"], SCHEMA) == []  # a valid strict-mode output
    assert set(g["expected"]) == {"fields", "suggestedNextAction"}
    text = g["request"]["ocrText"]
    for f in g["expected"]["fields"]:
        assert f["span"] is not None, f["id"]  # every field in these cases comes from the text
        quote = next(o["quote"] for o in g["llmOutput"]["fields"] if o["id"] == f["id"])
        found = utf16_slice(text, f["span"]["start"], f["span"]["end"])
        assert unicodedata.normalize("NFC", found).casefold() == unicodedata.normalize("NFC", quote).casefold()


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem)
def test_full_service_with_mocked_llm(path):
    g = load(path)
    out, fake = run(g, g["llmOutput"])
    assert out == g["expected"]
    assert len(fake.calls) == 1  # valid output → no repair


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem)
def test_injected_text_stays_inside_one_untrusted_block(path):
    g = load(path)
    msgs = ex.build_messages(ExtractRequest.model_validate(g["request"]), S)
    user = msgs[2]["content"]
    assert user.startswith('<untrusted_content source="ocr">\n') and user.endswith("\n</untrusted_content>")
    assert OUR_TAGS.findall(user) == ["untrusted_content", "untrusted_content"]  # only our own open + close
    assert g["request"]["ocrText"] not in msgs[0]["content"] + msgs[1]["content"]  # never in trusted roles


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem)
def test_injected_values_never_reach_the_output(path):
    g = load(path)
    values = " ".join(f["value"] for f in g["expected"]["fields"])
    for bad in g["forbiddenInValues"]:
        assert bad.casefold() not in values.casefold(), bad


def test_instruction_title_stays_plain_data_and_long_one_is_dropped():
    short = load(GOLDEN / "extract.inject_title_short.json")["expected"]
    assert short["fields"][0]["id"] == "title" and len(short["fields"][0]["value"]) <= ex.TITLE_MAX
    assert short["suggestedNextAction"] in ex.ACTIONS  # only the closed enum; nothing can carry "delete"
    long = load(GOLDEN / "extract.inject_title_long.json")
    assert [f["id"] for f in long["expected"]["fields"]] == ["dateTime"]


def test_output_with_an_action_key_is_rejected_by_the_schema_then_repaired():
    """§8.3: the schema itself blocks an action. A model that adds one is invalid → one repair (D-054)."""
    g = load(GOLDEN / "extract.inject_doc.json")
    obeyed = {**g["llmOutput"], "action": {"kind": "sms", "to": "0988 000 111", "body": "OK"}}
    assert check(obeyed, SCHEMA) != []
    out, fake = run(g, obeyed, g["llmOutput"])
    assert out == g["expected"] and len(fake.calls) == 2
    assert "0988 000 111" not in json.dumps(out, ensure_ascii=False)


def test_unknown_field_id_or_action_is_rejected_and_twice_bad_is_502():
    g = load(GOLDEN / "extract.inject_doc.json")
    bad_id = {"fields": [{"id": "deleteAll", "value": "x", "confidence": 1, "quote": None}], "suggestedNextAction": None}
    bad_action = {"fields": [], "suggestedNextAction": "deleteEvents"}
    assert check(bad_id, SCHEMA) != [] and check(bad_action, SCHEMA) != []
    with pytest.raises(AppError) as e:
        run(g, bad_id, bad_action)
    assert e.value.http_status == 502 and e.value.code == "llm_invalid_output"
