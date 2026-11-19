"""D-319: `Server-Timing` header with phase durations, names only (D-059)."""

import asyncio

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app import timing
from app.timing import TimingMiddleware, header_value


def test_header_format():
    assert header_value({"auth": 0.0123, "llm": 1.84}, 1.9031) == "auth;dur=12.3, llm;dur=1840.0, total;dur=1903.1"


def test_middleware_adds_header_and_spans():
    app = FastAPI()
    app.add_middleware(TimingMiddleware)

    @app.get("/v1/x")
    async def x() -> dict:
        with timing.span("llm"):
            await asyncio.sleep(0.01)
        timing.add("llm", 0.005)
        return {}

    r = TestClient(app).get("/v1/x")
    parts = dict(p.split(";dur=") for p in r.headers["server-timing"].split(", "))
    assert set(parts) == {"llm", "total"}
    assert float(parts["llm"]) >= 15.0 and float(parts["total"]) >= 10.0  # llm includes the added 5 ms


def test_span_outside_a_request_is_a_no_op():
    with timing.span("x"):
        pass
    timing.add("y", 1.0)
