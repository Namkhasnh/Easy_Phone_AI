"""Per-request phase timings → `Server-Timing` response header + one log line (latency work, D-319).

Only names and milliseconds, never content (D-059). Phases are added with `span("llm")` anywhere inside a request;
the middleware owns the per-request dict (a ContextVar, shared by reference with dependencies and threadpool calls).
"""

import logging
import time
from collections.abc import Iterator
from contextlib import contextmanager
from contextvars import ContextVar

from starlette.types import ASGIApp, Message, Receive, Scope, Send

logger = logging.getLogger("easyphone.timing")
HEADER = b"server-timing"
_phases: ContextVar[dict[str, float] | None] = ContextVar("phases", default=None)


def add(name: str, seconds: float) -> None:
    phases = _phases.get()
    if phases is not None:
        phases[name] = phases.get(name, 0.0) + seconds


@contextmanager
def span(name: str) -> Iterator[None]:
    start = time.perf_counter()
    try:
        yield
    finally:
        add(name, time.perf_counter() - start)


def header_value(phases: dict[str, float], total: float) -> str:
    """RFC `Server-Timing`: `auth;dur=12.3, llm;dur=1840.0, total;dur=1903.1` (ms, 1 decimal)."""
    parts = [f"{name};dur={seconds * 1000:.1f}" for name, seconds in phases.items()]
    parts.append(f"total;dur={total * 1000:.1f}")
    return ", ".join(parts)


class TimingMiddleware:
    """Pure ASGI: starts the clock, adds `Server-Timing` at response start, logs the phases of `/v1/*` calls."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        start = time.perf_counter()
        phases: dict[str, float] = {}
        token = _phases.set(phases)

        async def send_with_timing(message: Message) -> None:
            if message["type"] == "http.response.start":
                total = time.perf_counter() - start
                value = header_value(phases, total)
                message["headers"] = [*message.get("headers", []), (HEADER, value.encode())]
                path = scope.get("path", "")
                if path.startswith("/v1/") and path != "/v1/health":
                    logger.info("timing %s %s status=%s %s", scope.get("method"), path, message.get("status"), value)
            await send(message)

        try:
            await self.app(scope, receive, send_with_timing)
        finally:
            _phases.reset(token)
