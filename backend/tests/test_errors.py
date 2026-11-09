"""0.11: request id + error envelope (API_CONTRACT §1, §3; ARCHITECTURE §9.3)."""

import logging
import re

from tests.conftest import SECRET_TEXT

REQ_ID = re.compile(r"^req_[0-9A-HJKMNP-TV-Z]{26}$")


def assert_envelope(resp, status: int, code: str, retryable: bool) -> dict:
    assert resp.status_code == status
    err = resp.json()["error"]
    assert err["code"] == code
    assert err["retryable"] is retryable
    assert isinstance(err["message"], str) and err["message"]
    assert REQ_ID.match(err["requestId"])
    assert resp.headers["X-Request-Id"] == err["requestId"]
    return err


def test_unknown_route_is_not_found_envelope(client):
    err = assert_envelope(client.get("/v1/nope"), 404, "not_found", False)
    assert "details" not in err


def test_wrong_method_is_not_found(client):
    assert_envelope(client.delete("/_test/app-error"), 404, "not_found", False)


def test_app_error_renders_code_status_details(client):
    err = assert_envelope(client.get("/_test/app-error"), 402, "quota_exceeded", False)
    assert err["details"] == {"plan": "free"}
    assert set(err) == {"code", "message", "retryable", "requestId", "details"}


def test_message_language_follows_accept_language(client):
    vi = client.get("/_test/app-error").json()["error"]["message"]
    en = client.get("/_test/app-error", headers={"Accept-Language": "en-US,en;q=0.9"}).json()["error"]["message"]
    vi2 = client.get("/_test/app-error", headers={"Accept-Language": "vi"}).json()["error"]["message"]
    assert vi == vi2 == "Bạn đã dùng hết lượt hôm nay."
    assert en == "You have used all of today's requests."


def test_validation_error_is_invalid_input_without_values(client):
    resp = client.post("/_test/echo", json={"schemaVersion": 1, "text": SECRET_TEXT, "extra": SECRET_TEXT})
    err = assert_envelope(resp, 422, "invalid_input", False)
    assert err["details"] == {"field": "extra", "reason": "extra_forbidden"}
    assert SECRET_TEXT not in resp.text


def test_missing_field_reports_field_name(client):
    err = assert_envelope(client.post("/_test/echo", json={"schemaVersion": 1}), 422, "invalid_input", False)
    assert err["details"]["field"] == "text"


def test_unhandled_exception_is_internal_and_logs_no_content(client, caplog):
    with caplog.at_level(logging.DEBUG):
        resp = client.get("/_test/crash")
    err = assert_envelope(resp, 500, "internal", True)
    assert SECRET_TEXT not in resp.text
    assert SECRET_TEXT not in caplog.text
    assert "ValueError" in caplog.text and err["requestId"] in caplog.text


def test_success_response_has_request_id_and_ids_differ(client):
    a = client.post("/_test/echo", json={"schemaVersion": 1, "text": "x"})
    b = client.post("/_test/echo", json={"schemaVersion": 1, "text": "x"})
    assert a.status_code == 200
    assert REQ_ID.match(a.headers["X-Request-Id"])
    assert a.headers["X-Request-Id"] != b.headers["X-Request-Id"]


def test_every_contract_code_has_vi_and_en_message():
    from app.errors import MESSAGES

    codes = {
        "billing_invalid", "unauthorized", "quota_exceeded", "billing_account_mismatch", "not_found",
        "payload_too_large", "invalid_input", "client_outdated", "rate_limited", "internal",
        "llm_invalid_output", "upstream_error", "spend_cap",
    }
    assert set(MESSAGES) == codes
    assert all(m["vi"] and m["en"] for m in MESSAGES.values())
