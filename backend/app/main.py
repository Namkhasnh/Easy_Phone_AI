"""FastAPI app (ARCHITECTURE §7). Routers are added by their items (0.12 health, 0.15 me, …)."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import APIRouter, FastAPI

from app import errors
from app.config import get_settings
from app.db import Database
from app.routers import health, me, parse
from app.request_id import RequestIdMiddleware

ROUTERS: list[APIRouter] = [health.router, me.router, parse.router]


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    yield
    await app.state.db.close()


def create_app(extra_routers: list[APIRouter] | None = None) -> FastAPI:
    settings = get_settings()
    app = FastAPI(title="EasyPhone AI", version=settings.APP_VERSION, lifespan=lifespan)  # CORS off: native app only
    app.state.db = Database()  # pool opens on first use (health never needs it)
    app.add_middleware(RequestIdMiddleware)
    errors.install(app)
    for router in [*ROUTERS, *(extra_routers or [])]:
        app.include_router(router)
    return app


app = create_app()
