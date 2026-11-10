"""1B.9: `task_draft.json` (= `ParsedDraftLLM`, DATA_MODEL §6.3) + `prompts/parse.v1.md` (AI_PROMPTS §3, §10)."""

import json
from pathlib import Path

from app.config import Settings
from app.services import prompts
from app.services.prompt_context import load_catalog
from app.services.task_draft_schema import SCHEMA_PATH, UNSUPPORTED_REASONS, build, dumps

DOCS = Path(__file__).resolve().parents[2] / "docs"
KINDS = Settings().ENABLED_KINDS
# Keywords OpenAI strict mode is known to accept; anything else is a risk of a 400 at request time.
ALLOWED_KEYS = {"type", "properties", "required", "additionalProperties", "items", "enum", "anyOf", "description"}


def walk(node, path="$"):
    yield path, node
    if isinstance(node, dict):
        for key, value in node.items():
            yield from walk(value, f"{path}.{key}")
    elif isinstance(node, list):
        for i, value in enumerate(node):
            yield from walk(value, f"{path}[{i}]")


def branches(schema):
    return {b["properties"]["kind"]["enum"][0]: b for b in schema["properties"]["steps"]["items"]["anyOf"]}


def test_snapshot_equals_generator():
    assert SCHEMA_PATH.read_text(encoding="utf-8") == dumps(build(KINDS)), "run: uv run python -m app.services.task_draft_schema"


def test_strict_mode_rules():
    schema = build(KINDS)
    assert schema["type"] == "object"  # root must be an object, not anyOf
    for path, node in walk(schema):
        if not isinstance(node, dict) or path.endswith(".properties"):
            continue
        if node.get("type") == "object":
            assert node["additionalProperties"] is False, path
            assert node["required"] == list(node["properties"]), path
        for key in node:
            if not path.endswith(".properties"):
                assert key in ALLOWED_KEYS, f"{path}.{key}"
        if "enum" in node:
            assert node["enum"], path


def test_root_is_parsed_draft_llm_only():
    schema = build(KINDS)
    assert list(schema["properties"]) == ["steps", "followUpQuestion", "unsupported"]  # no schemaVersion / requestId (D-277)
    reasons = schema["properties"]["unsupported"]["anyOf"][0]["properties"]["reason"]["enum"]
    assert reasons == UNSUPPORTED_REASONS and "bulkAction" in reasons  # D-280


def test_one_branch_per_enabled_kind_with_catalog_operations():
    b = branches(build(KINDS))
    assert list(b) == KINDS
    catalog = {k["kind"]: k for k in load_catalog()["kinds"]}
    for kind, branch in b.items():
        assert branch["properties"]["operation"]["enum"] == [r["operation"] for r in catalog[kind]["required"]]


def test_locked_and_app_built_ids_never_in_schema_for_their_kind():
    b = branches(build(KINDS))
    ids = {k: v["properties"]["fields"]["items"]["properties"]["id"]["enum"] for k, v in b.items()}
    for kind in load_catalog()["kinds"]:
        for f in kind["fields"]:
            if f["deviceOnly"] or f["appBuilt"]:
                assert f["id"] not in ids[kind["kind"]], (kind["kind"], f["id"])  # D-056
    assert "phoneNumber" not in ids["call"] and "phoneNumber" not in ids["sms"]
    assert "phoneNumber" in ids["ocr"]  # read from the photo, not 🔒
    assert "calendarId" not in json.dumps(build(KINDS)) and "contactId" not in json.dumps(build(KINDS))


def test_date_candidates_point_to_date_fields():
    b = branches(build(KINDS))
    fid = lambda k: b[k]["properties"]["dateCandidates"]["items"]["properties"]["fieldId"]
    assert fid("calendarEvent")["enum"] == ["startDate", "endDate"]
    assert fid("reminder")["enum"] == ["dueDate"]
    assert "enum" not in fid("call")


def test_enabled_kinds_filter():
    b = branches(build(["reminder", "call"]))
    assert list(b) == ["reminder", "call"]


def _doc_lines(start: str, end: str) -> list[str]:
    lines = (DOCS / "AI_PROMPTS.md").read_text(encoding="utf-8").split("\n")
    i = next(n for n, l in enumerate(lines) if l.startswith(start))
    j = next(n for n in range(i, len(lines)) if lines[n].startswith(end))
    return lines[i : j + 1]


def test_parse_prompt_is_the_doc_text_verbatim():
    text = prompts.load("parse", Settings().PROMPT_VERSION_PARSE)
    security = _doc_lines("SECURITY RULES", "- Output must match the JSON schema exactly.")
    body = _doc_lines("You are the intent parser", "  Keep all other values unchanged")
    expected = "\n".join(body).replace("{{SECURITY RULES block, §2.3}}", "\n".join(security)) + "\n"
    assert text == expected
    assert not prompts.placeholders(text)  # static, byte-identical across requests (cacheable prefix, §1)


def test_parse_prompt_size_budget():
    text = prompts.load("parse", Settings().PROMPT_VERSION_PARSE)
    # TODO(spec): no tokenizer in the backend; ≈ 3 UTF-8 bytes per token is a conservative bound for this English text.
    assert len(text.encode("utf-8")) / 3 <= 2500
