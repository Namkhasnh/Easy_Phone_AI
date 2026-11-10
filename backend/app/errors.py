"""`AppError` + the one error envelope (API_CONTRACT §3, ARCHITECTURE §9.3).

`message` is only a fallback; the app shows its own `error.<code>` string. Fallback texts (vi) mirror
UI_SCREENS §8 so a client that does not know a code still shows the same words.
"""

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.request_id import HEADER, new_request_id

logger = logging.getLogger("easyphone.errors")

# message_key -> {lang: text}. Keys are the §3.2 codes.
MESSAGES: dict[str, dict[str, str]] = {
    "billing_invalid": {"vi": "Không xác minh được giao dịch.", "en": "The purchase could not be verified."},
    "unauthorized": {
        "vi": "Phiên đăng nhập đã hết. Bạn đăng nhập lại nhé.",
        "en": "Your session has expired. Please sign in again.",
    },
    "quota_exceeded": {"vi": "Bạn đã dùng hết lượt hôm nay.", "en": "You have used all of today's requests."},
    "billing_account_mismatch": {
        "vi": "Giao dịch thuộc tài khoản khác.",
        "en": "This purchase belongs to another account.",
    },
    "not_found": {"vi": "Có lỗi, bản nháp đã được lưu.", "en": "Something went wrong. Your draft is saved."},
    "payload_too_large": {
        "vi": "Ảnh hoặc nội dung quá lớn. Bạn thử ảnh khác hoặc nội dung ngắn hơn nhé.",
        "en": "The image or text is too large. Try another image or shorter text.",
    },
    "invalid_input": {"vi": "Có lỗi, bản nháp đã được lưu.", "en": "Something went wrong. Your draft is saved."},
    "client_outdated": {"vi": "Cần cập nhật ứng dụng.", "en": "Please update the app."},
    "rate_limited": {
        "vi": "Giọng nói tạm thời chưa dùng được. Bạn gõ chữ nhé.",
        "en": "Voice is temporarily unavailable. Please type instead.",
    },
    "internal": {"vi": "Có lỗi, bản nháp đã được lưu.", "en": "Something went wrong. Your draft is saved."},
    "llm_invalid_output": {
        "vi": "Mình chưa hiểu yêu cầu. Bạn thử lại nhé.",
        "en": "I didn't understand the request. Please try again.",
    },
    "upstream_error": {"vi": "Có lỗi, bản nháp đã được lưu.", "en": "Something went wrong. Your draft is saved."},
    "spend_cap": {
        "vi": "Dịch vụ AI tạm dừng. Các tính năng khác vẫn dùng được.",
        "en": "The AI service is paused. Other features still work.",
    },
}


class AppError(Exception):
    """The only error type services raise. Rendered by `app_error_handler`."""

    def __init__(
        self,
        code: str,
        http_status: int,
        retryable: bool,
        message_key: str | None = None,
        details: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(code)
        self.code = code
        self.http_status = http_status
        self.retryable = retryable
        self.message_key = message_key or code
        self.details = details
        self.headers = headers or {}  # e.g. `Retry-After` on 429 (API_CONTRACT §1)


def _language(request: Request) -> str:
    header = request.headers.get("accept-language", "")
    first = header.split(",")[0].split(";")[0].strip().lower()
    return "en" if first.startswith("en") else "vi"


def _request_id(request: Request) -> str:
    rid = getattr(request.state, "request_id", None)
    return rid or new_request_id()


def render(request: Request, err: AppError) -> JSONResponse:
    texts = MESSAGES.get(err.message_key, MESSAGES["internal"])
    request_id = _request_id(request)
    body: dict[str, Any] = {
        "code": err.code,
        "message": texts[_language(request)],
        "retryable": err.retryable,
        "requestId": request_id,
    }
    if err.details is not None:
        body["details"] = err.details
    # Header set here too: the unhandled-exception handler runs outside RequestIdMiddleware.
    return JSONResponse(status_code=err.http_status, content={"error": body}, headers={**err.headers, HEADER: request_id})


async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return render(request, exc)


async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    # First error only, never the input value (D-059, ARCHITECTURE §9.3).
    errors = exc.errors()
    details: dict[str, Any] = {}
    if errors:
        first = errors[0]
        loc = [str(p) for p in first.get("loc", ()) if p not in ("body", "query", "path", "header")]
        details = {"field": loc[-1] if loc else None, "reason": first.get("type")}
    return render(request, AppError("invalid_input", 422, False, details=details))


async def http_error_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    if exc.status_code in (404, 405):
        return render(request, AppError("not_found", 404, False))
    # TODO(spec): API_CONTRACT §3.2 lists no code for other framework HTTP errors; render as internal.
    return render(request, AppError("internal", 500, True))


async def unhandled_error_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.error("unhandled %s requestId=%s", type(exc).__name__, _request_id(request))
    return render(request, AppError("internal", 500, True))


def install(app: FastAPI) -> None:
    app.add_exception_handler(AppError, app_error_handler)
    app.add_exception_handler(RequestValidationError, validation_error_handler)
    app.add_exception_handler(StarletteHTTPException, http_error_handler)
    app.add_exception_handler(Exception, unhandled_error_handler)
