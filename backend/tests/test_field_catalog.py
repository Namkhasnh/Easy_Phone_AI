"""`app/schemas/field_catalog.json` (DATA_MODEL §4, §4.1). The iOS `FieldCatalogTests` asserts the same file equals
Swift `FieldCatalog.mvp`; this suite checks the file is internally consistent for the backend's own use (1B.9)."""

import json
from pathlib import Path

CATALOG_PATH = Path(__file__).parents[1] / "app" / "schemas" / "field_catalog.json"
CATALOG = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))

# DATA_MODEL §1.2 valid pairs for MVP kinds; Phase 2/3 kinds are not in the catalog yet (D-150).
ALLOWED_OPERATIONS = {
    "calendarEvent": {"create", "update", "delete"},
    "reminder": {"create", "update", "delete", "complete", "snooze"},
    "call": {"open"},
    "sms": {"open"},
    "place": {"create", "open"},
    "ocr": {"create"},
}
FIELD_TYPES = {
    "text", "longText", "dateTime", "date", "durationMinutes", "bool", "phone",
    "contactRef", "placeRef", "address", "coordinate", "enumChoice",
}
FIELD_KEYS = {"id", "type", "deviceOnly", "appBuilt"}
OPTIONAL_FIELD_KEYS = {"options", "operations"}


def _kinds() -> dict[str, dict]:
    return {k["kind"]: k for k in CATALOG["kinds"]}


def test_root_shape() -> None:
    assert set(CATALOG) == {"schemaVersion", "kinds"}
    assert CATALOG["schemaVersion"] == 1
    assert [k["kind"] for k in CATALOG["kinds"]] == list(ALLOWED_OPERATIONS)


def test_fields_are_well_formed() -> None:
    for kind in CATALOG["kinds"]:
        ids = [f["id"] for f in kind["fields"]]
        assert len(ids) == len(set(ids)), kind["kind"]
        for f in kind["fields"]:
            assert FIELD_KEYS <= set(f) <= FIELD_KEYS | OPTIONAL_FIELD_KEYS, f
            assert f["type"] in FIELD_TYPES, f
            assert (f["type"] == "enumChoice") == ("options" in f), f
            assert set(f.get("operations", [])) <= ALLOWED_OPERATIONS[kind["kind"]], f


def test_one_rule_per_allowed_operation_and_ids_exist() -> None:
    for name, kind in _kinds().items():
        ops = [r["operation"] for r in kind["required"]]
        assert sorted(ops) == sorted(ALLOWED_OPERATIONS[name]), name
        for rule in kind["required"]:
            in_op = {f["id"] for f in kind["fields"] if rule["operation"] in f.get("operations", [rule["operation"]])}
            needed = rule["fields"] + [i for c in rule["conditional"] for i in c["fields"]]
            assert set(needed) <= in_op, (name, rule["operation"])
            for cond in rule["conditional"]:
                for w in cond["when"]:
                    assert w["type"] in {"equals", "notPhoneNumber"}
                    assert w["field"] in in_op


def test_locked_fields_match_d056() -> None:
    locked = {f"{k['kind']}.{f['id']}" for k in CATALOG["kinds"] for f in k["fields"] if f["deviceOnly"]}
    assert locked == {
        "calendarEvent.calendarId", "call.contactId", "call.phoneNumber", "sms.contactId", "sms.phoneNumber",
    }
    built = {f"{k['kind']}.{f['id']}" for k in CATALOG["kinds"] for f in k["fields"] if f["appBuilt"]}
    assert built == {"reminder.completed"}
