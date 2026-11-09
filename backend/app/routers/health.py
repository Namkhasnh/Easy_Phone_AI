"""`GET /v1/health` — no auth, 0 units, no DB / OpenAI (API_CONTRACT §6.1, D-235)."""

from fastapi import APIRouter, Depends

from app.config import Settings, get_settings
from app.schemas.health import HealthResponse

router = APIRouter(prefix="/v1")


@router.get("/health", response_model=HealthResponse)
def health(settings: Settings = Depends(get_settings)) -> HealthResponse:
    return HealthResponse(status="ok", version=settings.APP_VERSION, schemaVersion=settings.SCHEMA_VERSION)
