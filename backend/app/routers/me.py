"""`GET /v1/me` — profile, plan, quota (API_CONTRACT §6.2). 0 units."""

from datetime import datetime
from zoneinfo import ZoneInfo

import asyncpg
from fastapi import APIRouter, Depends, Response

from app.deps import AuthedUser, Settings, authed_user, clock, db, get_settings
from app.schemas.me import MeResponse, Quota, Subscription
from app.services import quota

router = APIRouter(prefix="/v1")


@router.get("/me", response_model=MeResponse)
async def me(
    response: Response,
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),  # same connection as `authed_user` (cached per request)
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
) -> MeResponse:
    ent = await quota.entitlement(conn, user.id, settings, now)
    q, sub = ent.quota, ent.subscription
    response.headers.update(quota.quota_headers(q))
    tz = ZoneInfo(settings.QUOTA_DAY_TZ)
    return MeResponse(
        schemaVersion=settings.SCHEMA_VERSION,
        userId=user.id,
        locale=user.locale,
        plan=ent.plan,
        quota=Quota(limit=q.limit, used=q.used, remaining=q.remaining, resetsAt=q.resets_at),
        subscription=Subscription(
            productId=sub.product_id,
            status=sub.status,
            expiresAt=sub.expires_at.astimezone(tz) if sub.expires_at else None,
            environment=sub.environment,
        )
        if sub
        else None,
    )
