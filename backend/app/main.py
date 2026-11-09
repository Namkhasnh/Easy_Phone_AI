"""FastAPI app (ARCHITECTURE §7). Routers are added by their items (0.12 health, 0.15 me, …)."""

from fastapi import APIRouter, FastAPI

from app import errors
from app.config import get_settings
from app.routers import health
from app.request_id import RequestIdMiddleware

ROUTERS: list[APIRouter] = [health.router]


def create_app(extra_routers: list[APIRouter] | None = None) -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="EasyPhone AI", version=settings.APP_VERSION)  # CORS off: native app only
    app.add_middleware(RequestIdMiddleware)
    errors.install(app)
    for router in [*ROUTERS, *(extra_routers or [])]:
        app.include_router(router)
    return app


app = create_app()
