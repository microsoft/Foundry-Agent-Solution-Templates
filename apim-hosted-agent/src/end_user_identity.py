"""Propagate a trusted end-user identity from hosted requests to model calls."""

import asyncio
import logging
import re
from collections.abc import AsyncIterator, Awaitable, Callable
from contextvars import ContextVar
from typing import Any

from agent_framework import ChatContext, ChatMiddleware
from agent_framework_foundry_hosting import ResponsesHostServer

END_USER_IDENTITY_HEADER = "x-client-end-user-key"
DEFAULT_END_USER_IDENTITY = "default_user"
logger = logging.getLogger(__name__)
_END_USER_KEY_PATTERN = re.compile(r"^platform/[0-9a-f]{64}$")

# The response stream can outlive the initial request handler call. A ContextVar
# keeps the identity isolated across concurrent streams until each one finishes.

_current_end_user_identity: ContextVar[str | None] = ContextVar(
    "current_end_user_identity",
    default=None,
)


class EndUserIdentityForwardingMiddleware(ChatMiddleware):
    """Add the current trusted end-user key to each model call."""

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
    """Scope the APIM-derived key or direct-Foundry fallback to the stream."""

    async def _handle_response(
        self,
        request: Any,
        context: Any,
        cancellation_signal: asyncio.Event,
    ) -> AsyncIterator[Any]:
        request_end_user_identity = context.client_headers.get(END_USER_IDENTITY_HEADER)
        if request_end_user_identity:
            if not _END_USER_KEY_PATTERN.fullmatch(request_end_user_identity):
                raise RuntimeError("The trusted APIM end-user identity header is invalid.")
            end_user_identity = request_end_user_identity
            identity_source = "apim"
        else:
            end_user_identity = DEFAULT_END_USER_IDENTITY
            identity_source = "direct-foundry"

        logger.info(
            "Hosted request end-user key=%s source=%s",
            end_user_identity,
            identity_source,
        )

        events = await super()._handle_response(request, context, cancellation_signal)

        async def scoped_events() -> AsyncIterator[Any]:
            token = _current_end_user_identity.set(end_user_identity)
            try:
                async for event in events:
                    yield event
            finally:
                _current_end_user_identity.reset(token)

        return scoped_events()
