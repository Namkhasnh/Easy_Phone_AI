"""Versioned prompt files `app/prompts/<name>.v<N>.md` (AI_PROMPTS §0.1). Never inline prompt text in Python."""

import re
from functools import lru_cache
from pathlib import Path

PROMPTS_DIR = Path(__file__).resolve().parent.parent / "prompts"
_PLACEHOLDER = re.compile(r"\{\{(\w+)\}\}")


@lru_cache
def load(name: str, version: int) -> str:
    """File text, cached. A missing file raises `FileNotFoundError` (a deploy bug, rendered as 500)."""
    return (PROMPTS_DIR / f"{name}.v{version}.md").read_text(encoding="utf-8")


def placeholders(template: str) -> set[str]:
    return set(_PLACEHOLDER.findall(template))


def render(template: str, **values: str) -> str:
    """Fill every `{{key}}`. A missing or an extra value raises `KeyError` (AI_PROMPTS §10: placeholders all filled)."""
    needed = placeholders(template)
    if needed != set(values):
        raise KeyError(f"placeholders {sorted(needed)} vs values {sorted(values)}")
    return _PLACEHOLDER.sub(lambda m: values[m.group(1)], template)
