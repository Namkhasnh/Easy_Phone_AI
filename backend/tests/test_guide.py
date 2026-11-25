"""4H.1: `POST /v1/guide` (API_CONTRACT §7.5, AI_PROMPTS §12, D-337 – D-340). `metered` faked."""

import json
from datetime import UTC, datetime
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app import deps
from app.config import Settings
from app.main import create_app
from app.routers import guide as guide_router
from app.services import guide_service as g
from app.services import prompts
from app.services.llm import LLMClient
from app.services.metering import CostMeter, Deadline, Metered
from app.services.quota import QuotaInfo
from tests.test_llm import FakeCompletions, resp

APP_HEADERS = {"X-Client-Version": "1.0(1)"}
FIXTURES = Path(__file__).parent / "fixtures" / "contract"
DOCS = Path(__file__).resolve().parents[2] / "docs"
KEY = "1a2b3c4d-4ab1-4c55-9a51-2f6c1c0f9e11"


def fixture(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


MONEY_REQ = fixture("guide.money.request.json")
MONEY_OUT = {"kind": "guide", "title": "Chuyển tiền qua app ngân hàng",
             "steps": [{"text": s["text"], "hint": s["hint"]} for s in fixture("guide.money.response.json")["steps"]],
             "isMoneyRelated": True, "scamWarnings": fixture("guide.money.response.json")["scamWarnings"]}
NOT_GUIDE_OUT = {"kind": "notAGuide", "title": "", "steps": [], "isMoneyRelated": False, "scamWarnings": []}


def setup_client(monkeypatch, *outputs):
    fake = FakeCompletions(*outputs)
    calls = []

    async def fake_metered(conn, settings, *, endpoint, units, user_id, key, now, run, deadline=None):
        calls.append({"endpoint": endpoint, "units": units, "key": key})
        return Metered(await run(Deadline(18), CostMeter()),
                       QuotaInfo(10, 6, 4, datetime.fromisoformat("2026-11-24T00:00:00+07:00")))

    monkeypatch.setattr(guide_router, "metered", fake_metered)
    app = create_app()

    async def no_db():
        yield None

    app.dependency_overrides[deps.authed_user] = lambda: deps.AuthedUser(id="u1", locale="vi")
    app.dependency_overrides[deps.db] = no_db
    app.dependency_overrides[deps.llm] = lambda: LLMClient(Settings(), fake)
    app.dependency_overrides[deps.clock] = lambda: datetime(2026, 11, 23, 3, 0, tzinfo=UTC)
    return TestClient(app, raise_server_exceptions=False, headers=APP_HEADERS), fake, calls


def without_id(d):
    return {k: v for k, v in d.items() if k != "requestId"}


def test_money_guide_matches_the_contract_fixture(monkeypatch, caplog):
    client, fake, calls = setup_client(monkeypatch, resp(json.dumps(MONEY_OUT, ensure_ascii=False)))
    caplog.set_level("DEBUG")
    r = client.post("/v1/guide", json=MONEY_REQ, headers={"Idempotency-Key": KEY})
    assert r.status_code == 200
    assert without_id(r.json()) == without_id(fixture("guide.money.response.json"))
    assert calls == [{"endpoint": "/v1/guide", "units": 1, "key": KEY}]
    msgs = fake.calls[0]["messages"]
    assert fake.calls[0]["model"] == Settings().MODEL_GUIDE and fake.calls[0]["store"] is False
    assert [m["role"] for m in msgs] == ["system", "user"]
    assert msgs[1]["content"].startswith("<user_request>")
    assert "tai nạn" not in caplog.text and "Mở app ngân hàng" not in caplog.text             # D-059


def test_not_a_guide_matches_the_fixture(monkeypatch):
    client, _, calls = setup_client(monkeypatch, resp(json.dumps(NOT_GUIDE_OUT)))
    r = client.post("/v1/guide", json=fixture("guide.not_a_guide.request.json"), headers={"Idempotency-Key": KEY})
    assert r.status_code == 200 and without_id(r.json()) == without_id(fixture("guide.not_a_guide.response.json"))
    assert calls[0]["units"] == 1                                                              # the LLM ran


def test_validation_before_any_unit(monkeypatch):
    client, fake, calls = setup_client(monkeypatch)
    assert client.post("/v1/guide", json=MONEY_REQ).status_code == 422                       # no Idempotency-Key
    assert client.post("/v1/guide", json={**MONEY_REQ, "question": "  "},
                       headers={"Idempotency-Key": KEY}).status_code == 422
    r = client.post("/v1/guide", json={**MONEY_REQ, "question": "a" * 501}, headers={"Idempotency-Key": KEY})
    assert r.status_code == 413 and r.json()["error"]["details"]["maxChars"] == 500
    assert fake.calls == [] and calls == []


def test_secrets_are_masked_before_the_llm(monkeypatch):
    client, fake, _ = setup_client(monkeypatch, resp(json.dumps(MONEY_OUT, ensure_ascii=False)))
    q = {**MONEY_REQ, "question": "Mã OTP 482913, số tài khoản 0123 4567 8901, mật khẩu là hoa123, chuyển 500.000 đồng"}
    client.post("/v1/guide", json=q, headers={"Idempotency-Key": KEY})
    sent = fake.calls[0]["messages"][1]["content"]
    for secret in ["482913", "0123 4567 8901", "hoa123"]:
        assert secret not in sent
    assert "500.000 đồng" in sent                                                              # an amount stays


@pytest.mark.parametrize("text", [
    "Mã OTP là 4829", "mã 482913 đọc cho ai", "thẻ 4111-1111-1111-1111", "stk 012345678901", "mật khẩu: abc!23", "pass la hoa123"])
def test_mask(text):
    assert g.MASK in g.mask_secrets(text)


def test_verdicts_and_secret_handover_are_dropped():
    raw = {**MONEY_OUT, "steps": [
        {"text": "Mở app ngân hàng.", "hint": "Người này đáng tin, bạn yên tâm."},
        {"text": "Đọc mã OTP cho người gọi để họ kiểm tra.", "hint": None},
        {"text": "Nhập mã OTP vào app.", "hint": "Đừng đọc mã OTP cho ai."}],
        "scamWarnings": ["Giao dịch này an toàn.", "Không phải lừa đảo đâu.", "Hãy gọi cho con trước."]}
    out = g.post_process(raw, "chuyển tiền")
    assert [s["text"] for s in out["steps"]] == ["Mở app ngân hàng.", "Nhập mã OTP vào app."]
    assert out["steps"][0]["hint"] is None and out["steps"][1]["hint"] == "Đừng đọc mã OTP cho ai."
    assert out["scamWarnings"] == ["Hãy gọi cho con trước."]


@pytest.mark.parametrize("text", ["Từ chối cung cấp mã OTP", "Không nên đọc mã OTP cho ai", "Đừng gửi mật khẩu cho người lạ", "Bảo vệ mã OTP"])
def test_negated_handover_is_a_warning(text):
    assert g._allowed(text)


def test_money_flag_from_keywords_and_limits():
    raw = {"kind": "guide", "title": "Mua hàng", "isMoneyRelated": False,
           "steps": [{"text": f"Bước {i}", "hint": None} for i in range(20)],
           "scamWarnings": ["a", "b", "c", "d"]}
    out = g.post_process(raw, "Mua hàng trên Shopee thế nào")
    assert out["isMoneyRelated"] and len(out["steps"]) == g.MAX_STEPS and out["scamWarnings"] == ["a", "b", "c"]
    plain = g.post_process({**raw, "scamWarnings": ["x"]}, "Gửi ảnh qua Zalo")
    assert not plain["isMoneyRelated"] and plain["scamWarnings"] == []                       # no money → no warnings


def test_all_steps_filtered_is_an_error():
    from app.errors import AppError
    with pytest.raises(AppError) as e:
        g.post_process({**MONEY_OUT, "steps": [{"text": "Bạn yên tâm, cứ chuyển.", "hint": None}]}, "chuyển tiền")
    assert e.value.code == "llm_invalid_output"


def test_empty_guide_is_repaired(monkeypatch):
    empty = {**MONEY_OUT, "steps": []}
    client, fake, _ = setup_client(monkeypatch, resp(json.dumps(empty)), resp(json.dumps(MONEY_OUT, ensure_ascii=False)))
    r = client.post("/v1/guide", json=MONEY_REQ, headers={"Idempotency-Key": KEY})
    assert r.status_code == 200 and len(fake.calls) == 2


@pytest.mark.skipif(not (DOCS / "AI_PROMPTS.md").exists(), reason="docs/ is local only")
def test_guide_prompt_is_the_doc_text_verbatim():
    doc = (DOCS / "AI_PROMPTS.md").read_text(encoding="utf-8")
    section = doc[doc.index("## 12. Guide prompt"):]
    body = section[section.index("```text\n") + len("```text\n"):section.index("```\n", section.index("```text\n") + 8)]
    assert prompts.load("guide", Settings().PROMPT_VERSION_GUIDE) == body
    security = doc[doc.index("SECURITY RULES (highest"):doc.index("No prose outside JSON.") + len("No prose outside JSON.")]
    assert security in body                                                                    # §2.3 block verbatim
