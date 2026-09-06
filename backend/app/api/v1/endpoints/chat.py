"""Chat API endpoints for conversations and messaging."""

import asyncio
import logging
from collections.abc import AsyncIterator, Awaitable, Callable
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.rate_limit import rate_limit
from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.chat import (
    ChatRequest,
    ChatResponseChunk,
    ClientToolResult,
    ConversationCreate,
    ConversationDetailOut,
    ConversationList,
    ConversationOut,
    ConversationSearchResponse,
    ConversationSearchResult,
    ConversationUpdate,
    EditMessageRequest,
    MatchedMessage,
    MessagePage,
    ModelList,
    RegenerateRequest,
    message_out,
)
from app.schemas.mute import MuteUpdate
from app.services.chat_service import ChatService
from app.services.client_tool_bridge import client_tool_bridge
from app.services.conversation_service import _build_snippet
from app.services.detached_chat_stream import DetachedChatStream

logger = logging.getLogger(__name__)

router = APIRouter()


def get_chat_service(
    db: Annotated[AsyncSession, Depends(get_db)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> ChatService:
    return ChatService(db, provider_name=settings.llm_provider)


# =============================================================================
# Conversation CRUD  (delegates to ChatService.conversations)
# =============================================================================


@router.post(
    "/conversations",
    response_model=ConversationOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new conversation",
)
async def create_conversation(
    data: ConversationCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> ConversationOut:
    conversation = await service.conversations.create(
        user_id=current_user["email"],
        title=data.title,
        model=data.model,
        initial_message=data.initial_message,
        system_prompt=data.system_prompt,
        thinking_level=data.thinking_level,
        active_topic_id=data.active_topic_id,
    )
    return ConversationOut.from_model(conversation)


@router.post(
    "/conversations/primary",
    response_model=ConversationOut,
    summary="Ensure the user's unified primary conversation",
)
async def ensure_primary_conversation(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
    data: ConversationCreate | None = None,
) -> ConversationOut:
    """Return the existing primary chat or create it exactly once."""
    conversation = await service.conversations.get_or_create_primary(
        user_id=current_user["email"],
        model=data.model if data else None,
        system_prompt=data.system_prompt if data else None,
        thinking_level=data.thinking_level if data else None,
    )
    return ConversationOut.from_model(conversation)


@router.get(
    "/conversations",
    response_model=ConversationList,
    summary="List user's conversations",
)
async def list_conversations(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    kind: Literal["all", "primary", "thread"] = Query(
        "all", description="Filter the unified primary chat from legacy threads"
    ),
) -> ConversationList:
    conversations, total = await service.conversations.list(
        user_id=current_user["email"],
        page=page,
        page_size=page_size,
        kind=kind,
    )

    return ConversationList(
        items=[ConversationOut.from_model(c) for c in conversations],
        total=total,
        page=page,
        page_size=page_size,
    )


@router.get(
    "/conversations/search",
    response_model=ConversationSearchResponse,
    summary="Search conversations by title or message content",
)
async def search_conversations(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
    q: str = Query(..., min_length=1, description="Search query (case-insensitive)"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
) -> ConversationSearchResponse:
    """Return conversations whose title or any message content matches ``q``.

    Results are restricted to the authenticated user's own, non-deleted
    conversations. Each result includes a snippet of every matched message
    for quick in-UI preview.
    """
    query = q.strip()
    if not query:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Query must not be empty",
        )

    hits, total = await service.conversations.search(
        user_id=current_user["email"],
        query=query,
        page=page,
        page_size=page_size,
    )

    items = [
        ConversationSearchResult(
            conversation=ConversationOut.from_model(hit.conversation),
            matched_messages=[
                MatchedMessage(
                    id=m.id,
                    role=m.role,  # type: ignore[arg-type]
                    content=m.content,
                    snippet=_build_snippet(m.content, query),
                    created_at=m.created_at,
                )
                for m in hit.matched_messages
            ],
        )
        for hit in hits
    ]

    return ConversationSearchResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        query=query,
    )


@router.get(
    "/conversations/{conversation_id}",
    response_model=ConversationDetailOut,
    summary="Get conversation details",
)
async def get_conversation(
    conversation_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
    message_limit: Annotated[
        int | None,
        Query(
            ge=1,
            le=500,
            description=(
                "Return only the most recent N messages (chronological "
                "order) instead of the full history — much faster for long "
                "conversations (B-03). Page older ones in via "
                "GET .../messages?before=<oldest loaded message id>. "
                "Omit for the full, unpaginated history (unchanged default)."
            ),
        ),
    ] = None,
) -> ConversationDetailOut:
    conversation = await service.conversations.get(
        conversation_id=conversation_id,
        user_id=current_user["email"],
        include_messages=message_limit is None,
    )

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    epoch = conversation.session_epoch if conversation.is_primary else None
    if message_limit is None:
        messages = list(conversation.messages or [])
        if epoch is not None:
            messages = [m for m in messages if m.session_epoch == epoch]
        return ConversationDetailOut.from_model_page(
            conversation,
            messages,
            total_message_count=len(messages),
            has_more_messages=False,
        )

    messages, total, has_more = await service.conversations.get_recent_messages(
        conversation_id, limit=message_limit, session_epoch=epoch
    )
    return ConversationDetailOut.from_model_page(
        conversation,
        messages,
        total_message_count=total,
        has_more_messages=has_more,
    )


@router.get(
    "/conversations/{conversation_id}/messages",
    response_model=MessagePage,
    summary="Page in older messages",
)
async def get_conversation_messages(
    conversation_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
    before: Annotated[str, Query(description="Return messages older than this message id")],
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> MessagePage:
    """Page in messages older than ``before`` (B-03: scroll-to-top paging).

    Pairs with ``GET /conversations/{id}?message_limit=N``, which returns the
    most recent window plus ``has_more_messages`` — the client passes the
    oldest loaded message's id as ``before`` to fetch the next page up.
    """
    conversation = await service.conversations.get(
        conversation_id=conversation_id,
        user_id=current_user["email"],
        include_messages=False,
    )
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    epoch = conversation.session_epoch if conversation.is_primary else None
    messages, has_more = await service.conversations.get_messages_before(
        conversation_id, before, limit=limit, session_epoch=epoch
    )
    return MessagePage(
        messages=[message_out(m) for m in messages],
        has_more=has_more,
    )


@router.patch(
    "/conversations/{conversation_id}",
    response_model=ConversationOut,
    summary="Update conversation",
)
async def update_conversation(
    conversation_id: str,
    data: ConversationUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> ConversationOut:
    # Detect explicit clear: caller sent system_prompt="" (empty) → reset to None
    clear_prompt = data.system_prompt == ""
    # enabled_tools three-way semantics at the service layer:
    #   not provided in payload → don't change
    #   provided as null         → clear (all tools)
    #   provided as list (incl. []) → set verbatim
    payload_set = data.model_fields_set
    set_enabled = "enabled_tools" in payload_set and data.enabled_tools is not None
    clear_enabled = "enabled_tools" in payload_set and data.enabled_tools is None
    # thinking_level: null is itself a meaningful value ("reset to provider
    # default"), so we only touch the column when the key was actually
    # present in the request payload.
    set_thinking_level = "thinking_level" in payload_set
    conversation = await service.conversations.update(
        conversation_id=conversation_id,
        user_id=current_user["email"],
        title=data.title,
        model=data.model,
        use_memory=data.use_memory,
        use_knowledge_base=data.use_knowledge_base,
        system_prompt=None if clear_prompt else data.system_prompt,
        clear_system_prompt=clear_prompt,
        enabled_tools=data.enabled_tools if set_enabled else None,
        set_enabled_tools=set_enabled,
        clear_enabled_tools=clear_enabled,
        is_pinned=data.is_pinned,
        thinking_level=data.thinking_level,
        set_thinking_level=set_thinking_level,
    )

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    return ConversationOut.from_model(conversation)


@router.patch(
    "/conversations/{conversation_id}/mute",
    response_model=ConversationOut,
    summary="Mute or unmute notifications for a conversation",
)
async def mute_conversation(
    conversation_id: str,
    data: MuteUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> ConversationOut:
    conversation = await service.conversations.set_mute(
        conversation_id=conversation_id,
        user_id=current_user["email"],
        duration=data.duration,
    )

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    return ConversationOut.from_model(conversation)


@router.delete(
    "/conversations/{conversation_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete conversation",
)
async def delete_conversation(
    conversation_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> None:
    conversation = await service.conversations.get(
        conversation_id, current_user["email"], include_messages=False
    )
    if conversation is not None and conversation.is_primary:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Primary chat cannot be deleted; use Fresh start to clear context",
        )
    deleted = await service.conversations.delete(
        conversation_id=conversation_id,
        user_id=current_user["email"],
        soft_delete=True,
    )

    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )


# =============================================================================
# Chat streaming
# =============================================================================


async def _sse_stream(
    chunks: AsyncIterator[Any],
    *,
    on_client_disconnect: Callable[[str], Awaitable[None]] | None = None,
) -> AsyncIterator[str]:
    """Serialize provider chunks into SSE `data: ...\\n\\n` frames.

    If the client disconnects mid-stream (yield raises ``CancelledError``), a
    ``DetachedChatStream`` is only marked disconnected; its producer keeps
    running and owns the eventual completion notification. Plain iterators use
    ``on_client_disconnect`` immediately with content accumulated so far.
    """
    accumulated = ""
    try:
        async for chunk in chunks:
            if (
                chunk.content
                and not chunk.is_finished
                and not chunk.is_thinking
                and not chunk.tool_calls
                and not (chunk.metadata and chunk.metadata.get("error"))
            ):
                accumulated += chunk.content

            if chunk.metadata and chunk.metadata.get("error"):
                # Checked BEFORE is_finished: error chunks also carry
                # is_finished=True, and serializing them as a bare `done`
                # would silently swallow the failure (the client ignores
                # done chunks with no accumulated content).
                response = ChatResponseChunk(
                    type="error",
                    error=chunk.content,
                    metadata=chunk.metadata,
                )
            elif chunk.metadata and any(
                event_type in chunk.metadata
                for event_type in ("topic_update", "context_preparing", "context_update")
            ):
                # Topic/context events intentionally keep one envelope shape:
                # metadata contains exactly one event key whose value is the
                # versioned payload.  Flutter can route the event without
                # guessing from content or done/chunk flags.
                event_type = next(
                    event_type
                    for event_type in ("topic_update", "context_preparing", "context_update")
                    if event_type in chunk.metadata
                )
                response = ChatResponseChunk(
                    type=event_type,
                    content="",
                    metadata={event_type: chunk.metadata[event_type]},
                )
            elif chunk.is_finished:
                response = ChatResponseChunk(type="done", metadata=chunk.metadata)
            elif chunk.tool_calls:
                response = ChatResponseChunk(
                    type="tool_call",
                    tool_calls=chunk.tool_calls,
                )
            elif chunk.metadata and chunk.metadata.get("tool_result"):
                response = ChatResponseChunk(
                    type="tool_result",
                    tool_result=chunk.metadata["tool_result"],
                )
            elif chunk.metadata and chunk.metadata.get("tool_execution"):
                # Live tool-progress marker (started / finished + duration).
                response = ChatResponseChunk(
                    type="tool_execution",
                    metadata=chunk.metadata,
                )
            elif chunk.metadata and chunk.metadata.get("action_proposal"):
                # A proposal tool's structured proposal — the client renders
                # a Confirm/Cancel card from it.
                response = ChatResponseChunk(
                    type="action_proposal",
                    metadata=chunk.metadata,
                )
            elif chunk.metadata and chunk.metadata.get("client_tool_request"):
                # A client-served folder tool (read_file/list_files): the desktop
                # client reads it locally and POSTs the result back (idea 17).
                response = ChatResponseChunk(
                    type="client_tool_request",
                    metadata=chunk.metadata,
                )
            elif chunk.is_thinking:
                response = ChatResponseChunk(type="thinking", content=chunk.content)
            else:
                response = ChatResponseChunk(type="chunk", content=chunk.content)

            yield f"data: {response.model_dump_json()}\n\n"
    except asyncio.CancelledError:
        if isinstance(chunks, DetachedChatStream):
            chunks.mark_disconnected()
        elif on_client_disconnect is not None:
            asyncio.create_task(on_client_disconnect(accumulated))
        raise
    except Exception as e:
        error_response = ChatResponseChunk(
            type="error",
            error=str(e),
            metadata={"error": True},
        )
        yield f"data: {error_response.model_dump_json()}\n\n"


def _make_push_callback(user_id: str, conversation_id: str) -> Callable[[str], Awaitable[None]]:
    """Build a callback that sends an FCM push with the accumulated response.

    Respects the conversation's own mute state (``Conversation.muted_until``,
    Idea 8 — mirrors ``RoomMember.muted_until``/Idea 7): the assistant reply is
    already persisted independently of this callback, so muting only
    suppresses the push + in-app notification, never the message itself.
    """

    async def _push(accumulated: str) -> None:
        if not accumulated.strip():
            return
        try:
            from datetime import UTC, datetime

            from app.db.session import async_session_maker
            from app.services.conversation_service import ConversationService
            from app.services.fcm_service import send_to_user
            from app.services.mute_util import is_muted

            body = accumulated.strip()
            if len(body) > 160:
                body = body[:157] + "..."

            async with async_session_maker() as session:
                conversation = await ConversationService(session).get(
                    conversation_id, user_id, include_messages=False
                )
                if conversation is not None and is_muted(
                    conversation.muted_until, datetime.now(UTC)
                ):
                    return
                await send_to_user(
                    session,
                    user_id,
                    title="Response ready",
                    body=body,
                    channel="chat_responses",
                    data={"conversation_id": conversation_id},
                )
        except Exception:
            logger.exception("Failed to send push notification on disconnect")

    return _push


_SSE_HEADERS = {
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no",
}


@router.post(
    "/conversations/{conversation_id}/chat",
    summary="Send a message and stream response",
    response_class=StreamingResponse,
    dependencies=[Depends(rate_limit("chat"))],
)
async def chat_stream(
    conversation_id: str,
    data: ChatRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> StreamingResponse:
    """Stream AI response as Server-Sent Events."""

    chunks = DetachedChatStream(
        lambda detached: detached.send_message(
            conversation_id=conversation_id,
            user_id=current_user["email"],
            content=data.message,
            options=data.options,
            attachments=data.attachments or None,
            has_client_folder=data.has_client_folder,
            client_folder_label=data.client_folder_label,
            talk_mode_instruction=data.talk_mode_instruction,
        ),
        provider_name=service.provider_name,
        on_disconnected=_make_push_callback(current_user["email"], conversation_id),
    )
    return StreamingResponse(
        _sse_stream(chunks),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )


@router.post(
    "/conversations/{conversation_id}/client-tool-result",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Return a client-served folder read to an in-flight turn",
)
async def client_tool_result(
    conversation_id: str,
    data: ClientToolResult,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> None:
    """Complete a parked ``read_file``/``list_files`` call (idea 17).

    The desktop client posts here after reading a file locally in response to a
    ``client_tool_request`` chunk. Ownership is enforced so only the
    conversation's owner can feed its turns.
    """
    conversation = await service.conversations.get(
        conversation_id, current_user["email"], include_messages=False
    )
    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )
    resolved = client_tool_bridge.resolve(
        conversation_id, data.tool_call_id, data.model_dump(exclude_none=True)
    )
    if not resolved:
        # No turn is waiting on this id — it already timed out or completed.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No pending tool request for that id",
        )


@router.post(
    "/conversations/{conversation_id}/messages/{message_id}/regenerate",
    summary="Regenerate an assistant message",
    response_class=StreamingResponse,
    dependencies=[Depends(rate_limit("chat"))],
)
async def regenerate_message(
    conversation_id: str,
    message_id: str,
    data: RegenerateRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> StreamingResponse:
    """Delete the given assistant message and re-stream a new response."""

    chunks = DetachedChatStream(
        lambda detached: detached.regenerate_message(
            conversation_id=conversation_id,
            user_id=current_user["email"],
            message_id=message_id,
            options=data.options,
        ),
        provider_name=service.provider_name,
        on_disconnected=_make_push_callback(current_user["email"], conversation_id),
    )
    return StreamingResponse(
        _sse_stream(chunks),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )


@router.post(
    "/conversations/{conversation_id}/messages/{message_id}/edit",
    summary="Edit a user message and re-run the conversation",
    response_class=StreamingResponse,
    dependencies=[Depends(rate_limit("chat"))],
)
async def edit_message(
    conversation_id: str,
    message_id: str,
    data: EditMessageRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> StreamingResponse:
    """Update a user message's content, drop every later message, and re-stream."""

    chunks = DetachedChatStream(
        lambda detached: detached.edit_and_resend(
            conversation_id=conversation_id,
            user_id=current_user["email"],
            message_id=message_id,
            new_content=data.content,
            options=data.options,
        ),
        provider_name=service.provider_name,
        on_disconnected=_make_push_callback(current_user["email"], conversation_id),
    )
    return StreamingResponse(
        _sse_stream(chunks),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )


@router.post(
    "/conversations/{conversation_id}/messages/{message_id}/branch",
    response_model=ConversationOut,
    status_code=status.HTTP_201_CREATED,
    summary="Branch conversation from a message",
)
async def branch_conversation(
    conversation_id: str,
    message_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> ConversationOut:
    result = await service.conversations.branch_from_message(
        conversation_id, message_id, current_user["email"]
    )
    if result is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="not_found",
        )
    return ConversationOut.from_model(result)


@router.delete(
    "/conversations/{conversation_id}/chat",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Stop an active streaming response",
)
async def stop_chat_stream(
    conversation_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
) -> None:
    ChatService.cancel_stream(conversation_id)


# =============================================================================
# Models & Health
# =============================================================================


@router.get(
    "/models",
    response_model=ModelList,
    summary="List available models",
)
async def list_models(
    service: Annotated[ChatService, Depends(get_chat_service)],
    settings: Annotated[Settings, Depends(get_settings)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ModelList:
    models = await service.list_available_models()
    # Filter out models explicitly disabled by an admin.
    from app.services.model_management_service import ModelManagementService

    mgmt = ModelManagementService(db)
    disabled = await mgmt.get_disabled_ids()
    if disabled:
        models = [m for m in models if m.id not in disabled]
    return ModelList(models=models, default_model=settings.default_model)


@router.get(
    "/health/llm",
    summary="Check LLM provider health",
)
async def health_check(
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> dict[str, bool]:
    return await service.health_check()
