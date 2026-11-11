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

    # Models (D-278), values locked by D-052 (1B.15 live eval, `evals/2026-11-10-parse-summary.md`).
    MODEL_PARSE: str = "gpt-6-luna"  # D-052
    MODEL_EXTRACT: str = "gpt-6-luna"  # D-052
    MODEL_VISION: str = "gpt-6-luna"  # D-052
    MODEL_TRANSCRIBE: str = "gpt-4o-mini-transcribe"  # D-052
    MODEL_SUMMARIZE: str = "gpt-6-luna"  # Phase 2 only (D-052)
    PROMPT_VERSION_PARSE: int = 2  # v2: viewCalendar (D-294)
    PROMPT_VERSION_EXTRACT: int = 1
    PROMPT_VERSION_REPAIR: int = 1
    LLM_TEMPERATURE: float | None = None  # AI_PROMPTS §0.2: sent only when set (some models reject it)
    # USD per 1M tokens [input, output], for `usage_events.cost_usd` + the spend cap (D-087).
    # Values = OpenAI list prices read 2026-11-10 at D-052 (developers.openai.com/api/docs/pricing); cached input
    # is not modelled, so the recorded cost can only be a little high (spend cap trips early, never late).
    MODEL_PRICES_USD_PER_1M: dict[str, list[float]] = {
        "gpt-4o-mini": [0.15, 0.60],
        "gpt-4o": [2.50, 10.00],
        "gpt-4o-mini-transcribe": [1.25, 5.00],  # audio input / text output tokens
        # D-052 eval candidates (1B.15)
        "gpt-6-luna": [0.10, 0.50],
        "gpt-5-nano": [0.05, 0.40],
    }
    # Transcription billed by duration (no token usage in the response): USD per audio minute.
    TRANSCRIBE_USD_PER_MINUTE: float = 0.006  # fallback only; 2× the 2026-11-10 list estimate ($0.003), spend cap trips early
    TRANSCRIBE_MAX_BYTES: int = 2 * 1024 * 1024  # API_CONTRACT §7.4: ≤ 2 MB
    TRANSCRIBE_MAX_SECONDS: int = 60  # ≤ 60 s; also the cost estimate when the response has no usage
    # A model without a price is charged at this (high) rate, so the spend cap can only trip early, never late.
    UNKNOWN_MODEL_PRICE_USD_PER_1M: list[float] = [10.0, 40.0]

    # Quota (D-091, D-232, D-224) and units (API_CONTRACT §4.1)
    FREE_DAILY_QUOTA: int = 10
    PREMIUM_DAILY_QUOTA: int = 200
    QUOTA_DAY_TZ: str = "Asia/Ho_Chi_Minh"
    UNITS_PARSE: int = 1
    UNITS_EXTRACT: int = 1
    UNITS_OCR: int = 1
    UNITS_TRANSCRIBE: int = 0
    TRANSCRIBE_PER_HOUR: int = 30  # D-237
    PARSE_TEXT_MAX_CHARS: int = 2000  # D-238
    OCR_TEXT_MAX_CHARS: int = 10_000  # D-238

    # Cost + time (D-285, D-246, D-262)
    MONTHLY_SPEND_CAP_USD: float = 5.0
    REQUEST_BUDGET_SECONDS: float = 18.0
    LLM_TIMEOUT_SECONDS: float = 12.0
    REPAIR_MIN_SECONDS: float = 5.0  # repair call only if this much budget remains (D-246)
    IDEMPOTENCY_WINDOW_HOURS: int = 24  # same key later → 422 idempotencyKeyExpired (API_CONTRACT §4.4)

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
    DATABASE_URL: SecretStr | None = None  # Supabase → Connect → Session pooler URI (D-261)
    DB_POOL_MAX_SIZE: int = 5
    DB_CONNECT_TIMEOUT_SECONDS: float = 5.0

    # Auth (API_CONTRACT §2): JWKS at {SUPABASE_URL}/auth/v1/.well-known/jwks.json; HS256 secret only as fallback
    JWT_AUDIENCE: str = "authenticated"


@lru_cache
def get_settings() -> Settings:
    return Settings()
