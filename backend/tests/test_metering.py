"""1B.5: metering pieces without a DB — `Deadline`, spend-cap month, `Idempotency-Key` header (API_CONTRACT §4.3–4.4)."""

from datetime import UTC, datetime

from fastapi import APIRouter, Depends
from fastapi.testclient import TestClient

from app.config import Settings
from app.deps import idempotency_key
from app.main import create_app
from app.services.metering import Deadline
from app.services.quota import month_utc


class FakeClock:
    def __init__(self) -> None:
        self.t = 100.0

    def __call__(self) -> float:
        return self.t


def test_deadline_llm_timeout_is_min_of_12s_and_remaining():
    clock, s = FakeClock(), Settings()
    d = Deadline(18, clock)
    assert d.llm_timeout(s) == 12
    clock.t += 10
    assert d.remaining() == 8 and d.llm_timeout(s) == 8
    clock.t += 20
    assert d.remaining() == 0


def test_deadline_repair_only_with_5s_left():
    clock, s = FakeClock(), Settings()
    d = Deadline(18, clock)
    clock.t += 13
    assert d.can_repair(s)  # exactly 5 s
    clock.t += 0.01
    assert not d.can_repair(s)


def test_month_utc_including_december():
    assert month_utc(datetime(2026, 11, 30, 23, 0, tzinfo=UTC)) == (
        datetime(2026, 11, 1, tzinfo=UTC), datetime(2026, 12, 1, tzinfo=UTC))
    assert month_utc(datetime(2026, 12, 5, tzinfo=UTC))[1] == datetime(2027, 1, 1, tzinfo=UTC)


router = APIRouter(prefix="/_test")


@router.post("/keyed")
def keyed(key: str = Depends(idempotency_key)) -> dict:
    return {"key": key}


def test_idempotency_key_header():
    client = TestClient(create_app(extra_routers=[router]), raise_server_exceptions=False)
    ok = "0b9a3c2e-5f4d-4e6a-9b1c-2d3e4f5a6b7c"
    assert client.post("/_test/keyed", headers={"Idempotency-Key": ok}).json() == {"key": ok}
    for headers in ({}, {"Idempotency-Key": ok.upper()}, {"Idempotency-Key": "abc"}):
        resp = client.post("/_test/keyed", headers=headers)
        assert resp.status_code == 422
        err = resp.json()["error"]
        assert err["code"] == "invalid_input" and err["details"]["field"] == "Idempotency-Key"


def test_quota_headers_and_json():
    from app.services.quota import QuotaInfo, quota_headers, quota_json

    q = QuotaInfo(10, 3, 7, datetime.fromisoformat("2026-11-10T00:00:00+07:00"))
    assert quota_headers(q) == {
        "X-Quota-Limit": "10", "X-Quota-Remaining": "7", "X-Quota-Resets-At": "2026-11-10T00:00:00+07:00"}
    assert quota_json(q) == {"limit": 10, "used": 3, "remaining": 7, "resetsAt": "2026-11-10T00:00:00+07:00"}
