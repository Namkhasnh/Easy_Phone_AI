"""`POST /v1/billing/verify` (API_CONTRACT §8.1, D-083). 0 units. Thin: rules in `services/billing.py`."""

from datetime import datetime

import asyncpg
from fastapi import APIRouter, Depends, Response

from app.deps import AuthedUser, Settings, authed_user, clock, db, get_settings
from app.routers.me import me_response
from app.schemas.billing import BillingVerifyRequest
from app.schemas.me import MeResponse
from app.services import billing

router = APIRouter(prefix="/v1/billing")


@router.post("/verify", response_model=MeResponse)
async def verify(
    body: BillingVerifyRequest,
    response: Response,
    user: AuthedUser = Depends(authed_user),
    conn: asyncpg.Connection = Depends(db),
    settings: Settings = Depends(get_settings),
    now: datetime = Depends(clock),
) -> MeResponse:
    await billing.verify(conn, user.id, body.signedTransaction, settings, now)
    return await me_response(conn, user, settings, now, response)
