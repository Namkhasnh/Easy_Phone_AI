"""`GET /v1/health` response (API_CONTRACT §6.1, D-235)."""

from typing import Literal

from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: Literal["ok"]
    version: str
    schemaVersion: int
