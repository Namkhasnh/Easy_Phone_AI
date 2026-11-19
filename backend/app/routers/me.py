"""`GET /v1/me` — profile, plan, quota (API_CONTRACT §6.2). 0 units."""

from datetime import datetime
from zoneinfo import ZoneInfo

import asyncpg
from fastapi import APIRouter, Depends, Request, Response

from app.deps import AuthedUser, CurrentUser, Settings, authed_user, clock, current_user, db, get_settings
from app.schemas.me import MeResponse, Quota, Subscription
from app.routers.gmail import google_oauth
from app.services import accounts, quota

router = APIRouter(prefix="/v1")


def supabase_admin(request: Request, settings: Settings = Depends(get_settings)):
    """Overridden in tests."""
    from app.routers.gmail import _http
    from app.services.supabase_admin import SupabaseAdmin
    return SupabaseAdmin(settings, _http(request))


@router.delete("/me", status_code=204, response_class=Response)
async def delete_me(
    user: CurrentUser = Depends(current_user),          # no profile upsert (API_CONTRACT §2); no client-version gate
    conn: asyncpg.Connection = Depends(db),
    settings: Settings = Depends(get_settings),
    admin=Depends(supabase_admin),
    oauth=Depends(google_oauth),
) -> Response:
    """API_CONTRACT §6.3 (D-073): all server data of the user is deleted; `204`, also when already deleted."""
    await accounts.delete_account(conn, user.id, admin, oauth, settings)
    return Response(status_code=204)


@router.get("/me", response_model=MeResponse)
async def me(
    response: Response,
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),  # same connection as `authed_user` (cached per request)
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
) -> MeResponse:
    return await me_response(conn, user, settings, now, response)


async def me_response(conn: asyncpg.Connection, user: AuthedUser, settings: Settings, now: datetime,
                      response: Response) -> MeResponse:
    """`MeResponse` + `X-Quota-*` headers; also the answer of `POST /v1/billing/verify` (API_CONTRACT §8.1 step 5)."""
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
