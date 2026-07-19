"""In-process bridge for client-served tools (idea 17: on-demand folder reads).

The "include a folder" feature keeps the attached folder **only** on the desktop
client. When the model calls ``read_file``/``list_files``, the backend can't read
it — instead it:

1. emits a ``client_tool_request`` chunk on the turn's SSE stream, and
2. parks the tool execution on an :class:`asyncio.Future` keyed by
   ``(conversation_id, tool_call_id)``.

The desktop client, still consuming that stream, reads the file locally and
POSTs the result to ``/chat/conversations/{id}/client-tool-result``, which calls
:meth:`ClientToolBridge.resolve` to complete the future — the turn then resumes
with the client-provided content.

This is a single-process, in-memory bridge (the SSE stream and the result POST
share the backend process, like the existing streaming/micro-app in-memory
state). If the client never answers, the request times out into a clean error.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable
from typing import Any

logger = logging.getLogger(__name__)

# How long to wait for the desktop client to serve a read before giving up.
DEFAULT_TIMEOUT_SECONDS = 60.0


class ClientToolBridge:
    """Bridges a parked tool execution to the client's out-of-band result POST."""

    def __init__(self) -> None:
        self._pending: dict[str, asyncio.Future[dict[str, Any]]] = {}

    @staticmethod
    def _key(conversation_id: str, tool_call_id: str) -> str:
        return f"{conversation_id}:{tool_call_id}"

    async def request(
        self,
        *,
        conversation_id: str,
        tool_call_id: str,
        on_registered: Callable[[], Awaitable[None]],
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
    ) -> dict[str, Any]:
        """Register a pending request, emit the ask, and await the client's result.

        ``on_registered`` (the caller's ``emit`` of the ``client_tool_request``
        chunk) runs *after* the future is registered, so a fast client POST can
        never race ahead of registration. Returns the payload the client POSTed,
        or an error dict on timeout.
        """
        key = self._key(conversation_id, tool_call_id)
        loop = asyncio.get_running_loop()
        future: asyncio.Future[dict[str, Any]] = loop.create_future()
        self._pending[key] = future
        try:
            await on_registered()
            async with asyncio.timeout(timeout_seconds):
                return await future
        except TimeoutError:
            return {
                "ok": False,
                "error": (
                    "The app didn't return the file in time. The folder is only "
                    "readable from the desktop app that attached it."
                ),
            }
        finally:
            self._pending.pop(key, None)

    def resolve(self, conversation_id: str, tool_call_id: str, payload: dict[str, Any]) -> bool:
        """Complete a pending request with the client's ``payload``.

        Returns ``False`` when no matching request is waiting (already resolved,
        timed out, or unknown id).
        """
        future = self._pending.get(self._key(conversation_id, tool_call_id))
        if future is None or future.done():
            return False
        future.set_result(payload)
        return True


# Module-level singleton — the SSE stream and the result POST share it in-process.
client_tool_bridge = ClientToolBridge()
