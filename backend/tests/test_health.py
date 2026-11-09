"""0.12: `GET /v1/health` (API_CONTRACT §6.1, D-235)."""

import re

from fastapi.testclient import TestClient

from app.config import Settings, get_settings
from app.main import create_app

REQ_ID = re.compile(r"^req_[0-9A-HJKMNP-TV-Z]{26}$")


def test_health_ok_without_auth_or_client_version(client):
    resp = client.get("/v1/health")
    assert resp.status_code == 200
    s = get_settings()
    assert resp.json() == {"status": "ok", "version": s.APP_VERSION, "schemaVersion": s.SCHEMA_VERSION}
    assert REQ_ID.match(resp.headers["X-Request-Id"])


def test_health_reads_version_from_config():
    app = create_app()
    app.dependency_overrides[get_settings] = lambda: Settings(APP_VERSION="9.9.9", SCHEMA_VERSION=1)
    body = TestClient(app).get("/v1/health").json()
    assert body["version"] == "9.9.9"
    assert body["schemaVersion"] == 1


def test_health_wrong_method_is_not_found_envelope(client):
    resp = client.post("/v1/health")
    assert resp.status_code == 404
    assert resp.json()["error"]["code"] == "not_found"
