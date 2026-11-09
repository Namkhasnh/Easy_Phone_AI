import pytest
from fastapi import APIRouter, Depends
from fastapi.testclient import TestClient
from pydantic import BaseModel, ConfigDict

from app.deps import CurrentUser, current_user
from app.errors import AppError
from app.main import create_app

SECRET_TEXT = "Nhắc tôi gọi bà Lan lúc 8 giờ"

test_router = APIRouter(prefix="/_test")


class EchoRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schemaVersion: int
    text: str


@test_router.get("/app-error")
def raise_app_error() -> None:
    raise AppError("quota_exceeded", 402, False, details={"plan": "free"})


@test_router.get("/crash")
def crash() -> None:
    raise ValueError(SECRET_TEXT)


@test_router.post("/echo")
def echo(body: EchoRequest) -> dict:
    return {"schemaVersion": 1}


@test_router.get("/whoami")
def whoami(user: CurrentUser = Depends(current_user)) -> dict:
    return {"userId": user.id}


@pytest.fixture
def client() -> TestClient:
    return TestClient(create_app(extra_routers=[test_router]), raise_server_exceptions=False)
