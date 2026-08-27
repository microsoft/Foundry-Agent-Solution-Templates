"""Propagate a trusted end-user identity to direct APIM model requests."""

import asyncio
import hashlib
import logging
from collections.abc import AsyncIterator, Awaitable, Callable
from contextvars import ContextVar
from typing import Any

from agent_framework import ChatContext, ChatMiddleware
from agent_framework_foundry_hosting import ResponsesHostServer

END_USER_IDENTITY_HEADER = "x-client-end-user-key"
logger = logging.getLogger(__name__)

_current_end_user_identity: ContextVar[str | None] = ContextVar(
    "current_end_user_identity",
    default=None,
)


class EndUserIdentityForwardingMiddleware(ChatMiddleware):
    """Add the current trusted end-user key to each model request."""

    async def process(self, context: ChatContext, call_next: Callable[[], Awaitable[None]]) -> None:
        end_user_identity = _current_end_user_identity.get()
        if not end_user_identity:
            raise RuntimeError("A trusted end-user identity is required for model calls.")

        options = dict(context.options or {})
        headers = dict(options.get("extra_headers") or {})
        headers[END_USER_IDENTITY_HEADER] = end_user_identity
        options["extra_headers"] = headers
        context.options = options
        await call_next()


class EndUserIdentityScopedResponsesHostServer(ResponsesHostServer):
    """Scope the Foundry platform user identity to the response stream."""

    async def _handle_response(
        self,
        request: Any,
        context: Any,
        cancellation_signal: asyncio.Event,
    ) -> AsyncIterator[Any]:
        platform_context = getattr(context, "platform_context", None)
        platform_user_id = getattr(platform_context, "user_id_key", None)
        if not isinstance(platform_user_id, str) or not platform_user_id:
            raise RuntimeError("Foundry did not provide a platform user identity.")

        platform_user_id_digest = hashlib.sha256(platform_user_id.encode("utf-8")).hexdigest()
        end_user_identity = f"platform/{platform_user_id_digest}"

        logger.info(
            "Hosted request user identity source=platform-context "
            "platform_user_id_length=%d platform_user_id_fingerprint=%s",
            len(platform_user_id),
            platform_user_id_digest[:12],
        )

        token = _current_end_user_identity.set(end_user_identity)
        try:
            async for event in super()._handle_response(request, context, cancellation_signal):
                yield event
        finally:
            _current_end_user_identity.reset(token)
