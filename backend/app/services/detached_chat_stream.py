"""Chat stream producer whose lifetime is independent of the HTTP client."""

import asyncio
import logging
from collections.abc import AsyncIterator, Awaitable, Callable
from typing import Final

from app.db import session as db_session
from app.services.chat_service import ChatService
from app.services.llm_provider import ChatChunk

logger = logging.getLogger(__name__)

ChatOperation = Callable[[ChatService], AsyncIterator[ChatChunk]]
DisconnectCallback = Callable[[str], Awaitable[None]]

_DONE: Final = object()


class DetachedChatStream:
    """Relay a chat turn through a queue while it runs in its own DB session.

    Starlette cancels a ``StreamingResponse`` iterator as soon as Android loses
    its socket. The producer task deliberately does not share that iterator's
    cancellation scope, so generation can finish and persist for later sync.
    """

    def __init__(
        self,
        operation: ChatOperation,
        *,
        provider_name: str,
        on_disconnected: DisconnectCallback | None = None,
    ) -> None:
        self._operation = operation
        self._provider_name = provider_name
        self._on_disconnected = on_disconnected
        self._queue: asyncio.Queue[ChatChunk | BaseException | object] = asyncio.Queue()
        self._disconnected = False
        self._task = asyncio.create_task(self._produce())

    def __aiter__(self) -> "DetachedChatStream":
        return self

    async def __anext__(self) -> ChatChunk:
        item = await self._queue.get()
        if item is _DONE:
            raise StopAsyncIteration
        if isinstance(item, BaseException):
            raise item
        return item

    def mark_disconnected(self) -> None:
        """Record that the consumer vanished without cancelling production."""
        self._disconnected = True
        while not self._queue.empty():
            self._queue.get_nowait()

    async def wait_finished(self) -> None:
        """Wait for persistence and any disconnect notification to finish."""
        await self._task

    async def _produce(self) -> None:
        # Keep the module (not the maker) imported: tests replace its maker
        # attribute per test, and production needs a session that outlives the
        # request dependency.
        accumulated = ""
        failed = False
        try:
            async with db_session.async_session_maker() as db:
                service = ChatService(db, provider_name=self._provider_name)
                try:
                    async for chunk in self._operation(service):
                        if chunk.metadata and chunk.metadata.get("error"):
                            failed = True
                        if (
                            chunk.content
                            and not chunk.is_finished
                            and not chunk.is_thinking
                            and not chunk.tool_calls
                            and not (chunk.metadata and chunk.metadata.get("error"))
                        ):
                            accumulated += chunk.content
                        if not self._disconnected:
                            await self._queue.put(chunk)
                    await db.commit()
                except BaseException:
                    await db.rollback()
                    raise
        except asyncio.CancelledError:
            raise
        except BaseException as error:
            failed = True
            logger.exception("Detached chat turn failed")
            if not self._disconnected:
                await self._queue.put(error)
        finally:
            if not self._disconnected:
                await self._queue.put(_DONE)

        if self._disconnected and not failed and self._on_disconnected is not None:
            try:
                await self._on_disconnected(accumulated)
            except Exception:
                logger.exception("Detached chat completion callback failed")
