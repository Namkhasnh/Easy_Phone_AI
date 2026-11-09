"""Request id (`req_<ulid>`, API_CONTRACT §1, D-234) on every request and response."""

import os
import time

from starlette.types import ASGIApp, Message, Receive, Scope, Send

_CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
HEADER = "X-Request-Id"


def new_ulid() -> str:
    """26-char ULID: 48-bit ms timestamp + 80 random bits, Crockford base32."""
    value = (int(time.time() * 1000) << 80) | int.from_bytes(os.urandom(10), "big")
    chars = []
    for _ in range(26):
        chars.append(_CROCKFORD[value & 31])
        value >>= 5
    return "".join(reversed(chars))


def new_request_id() -> str:
    return f"req_{new_ulid()}"


class RequestIdMiddleware:
    """Pure ASGI middleware: sets `request.state.request_id` and the `X-Request-Id` response header."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        request_id = new_request_id()
        scope.setdefault("state", {})["request_id"] = request_id

        async def send_with_id(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = [(k, v) for k, v in message.get("headers", []) if k.lower() != b"x-request-id"]
                headers.append((b"x-request-id", request_id.encode()))
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, send_with_id)
