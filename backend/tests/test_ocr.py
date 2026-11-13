"""1D.4a: `POST /v1/ocr` (API_CONTRACT §7.3, 1 unit, D-061). Route wiring with `metered` faked (like test_parse_route)."""

import json
from datetime import UTC, datetime
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import deps
from app.config import Settings
from app.errors import AppError
from app.main import create_app
from app.routers import media as media_router
from app.services import ocr_service
from app.services.llm import LLMClient
from app.services.metering import CostMeter, Deadline, Metered
from app.services.quota import QuotaInfo
from tests.test_llm import FakeCompletions, resp

APP_HEADERS = {"X-Client-Version": "1.0(1)"}
FIXTURES = Path(__file__).parent / "fixtures" / "contract"
KEY = "6f1c2b7e-1d0a-4c55-9a51-2f6c1c0f9e11"
META = json.dumps({"schemaVersion": 1, "locale": "vi-VN"})
SECRET = "Lịch hẹn: 09:30 ngày 14/11/2026"
LLM_LINES = {"lines": [
    {"text": "PHÒNG KHÁM NHA KHOA AN BÌNH", "box": {"x": 0.08, "y": 0.86, "width": 0.84, "height": 0.05}},
    {"text": "  ", "box": {"x": 0, "y": 0, "width": 0, "height": 0}},
    {"text": SECRET, "box": {"x": 0.08, "y": 0.78, "width": 0.70, "height": 0.04}},
]}


def fake_jpeg(width: int, height: int, pad: int = 0) -> bytes:
    """SOI + APP0 + SOF0 (dimensions) + EOI — enough for `jpeg_size`."""
    app0 = b"\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    sof = b"\xff\xc0\x00\x11\x08" + height.to_bytes(2, "big") + width.to_bytes(2, "big") + b"\x03" + b"\x00" * 9
    return b"\xff\xd8" + app0 + sof + b"\x00" * pad + b"\xff\xd9"


@pytest.fixture
def setup(monkeypatch):
    fake = FakeCompletions(resp(json.dumps(LLM_LINES, ensure_ascii=False)))
    calls = []

    async def fake_metered(conn, settings, *, endpoint, units, user_id, key, now, run, deadline=None):
        calls.append({"endpoint": endpoint, "units": units, "key": key})
        return Metered(await run(Deadline(18), CostMeter()),
                       QuotaInfo(10, 5, 5, datetime.fromisoformat("2026-11-13T00:00:00+07:00")))

    monkeypatch.setattr(media_router, "metered", fake_metered)
    app = create_app()

    async def no_db():
        yield None

    app.dependency_overrides[deps.authed_user] = lambda: deps.AuthedUser(id="u1", locale="vi")
    app.dependency_overrides[deps.db] = no_db
    app.dependency_overrides[deps.llm] = lambda: LLMClient(Settings(), fake)
    app.dependency_overrides[deps.clock] = lambda: datetime(2026, 11, 12, 8, 0, tzinfo=UTC)
    return TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS), fake, calls


def post(client, data=None, *, key=KEY, meta=META):
    headers = {"Idempotency-Key": key} if key else {}
    return client.post("/v1/ocr", files={"image": ("photo.jpg", data or fake_jpeg(1500, 2000), "image/jpeg")},
                       data={"meta": meta}, headers=headers)


def test_ok_matches_fixture_and_charges_one_unit(setup, caplog):
    client, fake, calls = setup
    caplog.set_level("DEBUG")
    r = post(client)
    assert r.status_code == 200
    expected = json.loads((FIXTURES / "ocr.ok.response.json").read_text(encoding="utf-8"))
    got = r.json()
    assert {k: v for k, v in got.items() if k != "requestId"} == {k: v for k, v in expected.items() if k != "requestId"}
    assert calls == [{"endpoint": "/v1/ocr", "units": 1, "key": KEY}]
    assert r.headers["X-Quota-Remaining"] == "5"
    call = fake.calls[0]
    assert call["model"] == Settings().MODEL_VISION and call["store"] is False         # D-052, D-059
    image_part = call["messages"][1]["content"][0]
    assert image_part["type"] == "image_url" and image_part["image_url"]["url"].startswith("data:image/jpeg;base64,")
    assert "untrusted" in call["messages"][0]["content"]                               # the photo is untrusted data
    assert SECRET not in caplog.text and "NHA KHOA" not in caplog.text                 # D-059: no OCR text in logs


def test_missing_key_is_422_and_nothing_called(setup):
    client, fake, calls = setup
    r = post(client, key=None)
    assert r.status_code == 422 and fake.calls == [] and calls == []


@pytest.mark.parametrize("data,status,detail", [
    (fake_jpeg(1000, 1000, pad=4 * 1024 * 1024), 413, "maxBytes"),
    (fake_jpeg(2049, 1000), 413, "maxPixels"),
    (b"\x89PNG\r\n\x1a\n" + b"\x00" * 50, 422, "notJpeg"),
])
def test_bad_images_rejected_before_any_unit(setup, data, status, detail):
    client, fake, calls = setup
    r = post(client, data)
    assert r.status_code == status and fake.calls == [] and calls == []
    assert detail in json.dumps(r.json()["error"]["details"])


def test_bad_meta_is_422(setup):
    client, fake, calls = setup
    r = post(client, meta='{"schemaVersion": 1, "locale": "fr-FR"}')
    assert r.status_code == 422 and calls == []


def test_jpeg_size_reads_sof_and_rejects_others():
    assert ocr_service.jpeg_size(fake_jpeg(2048, 1536)) == (2048, 1536)
    assert ocr_service.jpeg_size(b"") is None and ocr_service.jpeg_size(b"\xff\xd8\xff\xd9") is None


def test_post_process_clamps_boxes_drops_blank_lines_and_caps_text():
    s = Settings(OCR_TEXT_MAX_CHARS=12)
    out = ocr_service.post_process({"lines": [
        {"text": "Dòng một", "box": {"x": 0.9, "y": -0.2, "width": 0.5, "height": 2}},
        {"text": "", "box": {"x": 0, "y": 0, "width": 0, "height": 0}},
        {"text": "Dòng hai quá dài", "box": {"x": 0, "y": 0, "width": 1, "height": 1}},
    ]}, s)
    assert [l["text"] for l in out] == ["Dòng một"]
    b = out[0]["box"]
    assert b["x"] == 0.9 and b["y"] == 0.0 and abs(b["width"] - 0.1) < 1e-9 and b["height"] == 1.0


def test_empty_photo_gives_no_lines(setup):
    client, fake, _ = setup
    fake.outputs = [resp(json.dumps({"lines": []}))]
    r = post(client)
    assert r.status_code == 200 and r.json()["lines"] == [] and r.json()["text"] == ""


def test_check_image_is_app_error():
    with pytest.raises(AppError):
        ocr_service.check_image(b"", Settings())
