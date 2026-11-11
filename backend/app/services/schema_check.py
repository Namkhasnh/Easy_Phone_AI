"""Tiny JSON Schema checker for the subset our strict schemas use (`task_draft_schema.ALLOWED` keywords):
`type`, `properties`, `required`, `additionalProperties: false`, `items`, `enum`, `anyOf`.

Returns error lines with **paths only** (AI_PROMPTS §6), e.g. `steps[0].fields[1].id: not in enum`, never values,
so the lines are safe to count in logs (D-059). An `anyOf` reports the branch with the fewest errors.
"""

from typing import Any

_TYPES: dict[str, tuple[type, ...]] = {
    "object": (dict,), "array": (list,), "string": (str,), "boolean": (bool,), "null": (type(None),),
    "number": (int, float), "integer": (int,),
}


def _type_ok(value: Any, expected: str | list[str]) -> bool:
    names = [expected] if isinstance(expected, str) else expected
    for name in names:
        if isinstance(value, bool) and name in ("number", "integer"):
            continue  # JSON true is not a number
        if isinstance(value, _TYPES[name]):
            return True
    return False


def check(value: Any, schema: dict[str, Any], path: str = "$") -> list[str]:
    if "anyOf" in schema:
        results = [check(value, branch, path) for branch in schema["anyOf"]]
        return [] if any(not r for r in results) else min(results, key=len)
    if "type" in schema and not _type_ok(value, schema["type"]):
        return [f"{path}: wrong type, expected {schema['type']}"]
    if "enum" in schema and value not in schema["enum"]:
        return [f"{path}: not in enum"]
    errors: list[str] = []
    if isinstance(value, dict) and "properties" in schema:
        props = schema["properties"]
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}.{key}: missing")
        if schema.get("additionalProperties") is False:
            errors += [f"{path}: unexpected key" for key in value if key not in props]
        for key, sub in props.items():
            if key in value:
                errors += check(value[key], sub, f"{path}.{key}")
    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            errors += check(item, schema["items"], f"{path}[{i}]")
    return errors
