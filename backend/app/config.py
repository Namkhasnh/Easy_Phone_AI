"""All backend configuration (D-038). Never hard-code a model, quota or price elsewhere."""

from functools import lru_cache

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    ENV: str = "dev"
    APP_VERSION: str = "0.1.0"
    SCHEMA_VERSION: int = 1
    MIN_CLIENT_VERSION: str = "1.0.0"  # API_CONTRACT §3.2 `client_outdated`

    # Models (D-278). D-052 is OPEN: placeholders until the 1B live evals lock them.
    MODEL_PARSE: str = "gpt-4o-mini"
    MODEL_EXTRACT: str = "gpt-4o-mini"
    MODEL_VISION: str = "gpt-4o-mini"
    MODEL_TRANSCRIBE: str = "gpt-4o-mini-transcribe"
    MODEL_SUMMARIZE: str = "gpt-4o-mini"  # Phase 2 only
    PROMPT_VERSION_PARSE: int = 1
    PROMPT_VERSION_EXTRACT: int = 1

    # Quota (D-091, D-232, D-224) and units (API_CONTRACT §4.1)
    FREE_DAILY_QUOTA: int = 10
    PREMIUM_DAILY_QUOTA: int = 200
    QUOTA_DAY_TZ: str = "Asia/Ho_Chi_Minh"
    UNITS_PARSE: int = 1
    UNITS_EXTRACT: int = 1
    UNITS_OCR: int = 1
    UNITS_TRANSCRIBE: int = 0
    TRANSCRIBE_PER_HOUR: int = 30  # D-237

    # Cost + time (D-285, D-246, D-262)
    MONTHLY_SPEND_CAP_USD: float = 5.0
    REQUEST_BUDGET_SECONDS: float = 18.0
    LLM_TIMEOUT_SECONDS: float = 12.0

    # Kinds the LLM may produce (DATA_MODEL §1.1). MVP kinds only; Phase 2/3 kinds stay off (D-150).
    ENABLED_KINDS: list[str] = ["calendarEvent", "reminder", "call", "sms", "place", "ocr"]

    # Billing (D-091, D-240, D-284)
    APP_BUNDLE_ID: str = "vn.namkhanh.easyphone"
    PRODUCT_IDS: list[str] = ["easyphone.premium.monthly", "easyphone.premium.yearly"]
    ALLOW_XCODE_STOREKIT: bool = False

    # Secrets: only from env / .env, never committed (D-051, D-207)
    OPENAI_API_KEY: SecretStr | None = None
    SUPABASE_URL: str | None = None
    SUPABASE_JWT_SECRET: SecretStr | None = None
    SUPABASE_SERVICE_ROLE_KEY: SecretStr | None = None
    DATABASE_URL: SecretStr | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
