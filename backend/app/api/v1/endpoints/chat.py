"""Chat API endpoints for conversations and messaging."""

import asyncio
import logging
from collections.abc import AsyncIterator, Awaitable, Callable
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.chat import (
    ChatRequest,
    ChatResponseChunk,
    ConversationCreate,
    ConversationDetailOut,
    ConversationList,
    ConversationOut,
    ConversationSearchResponse,
    ConversationSearchResult,
    ConversationUpdate,
    EditMessageRequest,
    MatchedMessage,
    ModelList,
    RegenerateRequest,
)
from app.services.chat_service import ChatService
from app.services.conversation_service import _build_snippet

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
) -> ConversationList:
    conversations, total = await service.conversations.list(
        user_id=current_user["email"],
        page=page,
        page_size=page_size,
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
) -> ConversationDetailOut:
    conversation = await service.conversations.get(
        conversation_id=conversation_id,
        user_id=current_user["email"],
        include_messages=True,
    )

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    return ConversationDetailOut.from_model(conversation)


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

    If the client disconnects mid-stream (yield raises CancelledError),
    ``on_client_disconnect`` is invoked with the assistant content accumulated
    so far. Used to trigger a push notification when the user backgrounds the
    app during generation.
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
            elif chunk.is_thinking:
                response = ChatResponseChunk(type="thinking", content=chunk.content)
            else:
                response = ChatResponseChunk(type="chunk", content=chunk.content)

            yield f"data: {response.model_dump_json()}\n\n"
    except asyncio.CancelledError:
        if on_client_disconnect is not None:
            asyncio.create_task(on_client_disconnect(accumulated))
        raise
    except Exception as e:
        error_response = ChatResponseChunk(
            type="error",
            error=str(e),
            metadata={"error": True},
        )
        yield f"data: {error_response.model_dump_json()}\n\n"


def _make_push_callback(
    user_id: str, conversation_id: str
) -> Callable[[str], Awaitable[None]]:
    """Build a callback that sends an FCM push with the accumulated response."""

    async def _push(accumulated: str) -> None:
        if not accumulated.strip():
            return
        try:
            from app.db.session import async_session_maker
            from app.services.fcm_service import send_to_user

            body = accumulated.strip()
            if len(body) > 160:
                body = body[:157] + "..."

            async with async_session_maker() as session:
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
)
async def chat_stream(
    conversation_id: str,
    data: ChatRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> StreamingResponse:
    """Stream AI response as Server-Sent Events."""

    return StreamingResponse(
        _sse_stream(
            service.send_message(
                conversation_id=conversation_id,
                user_id=current_user["email"],
                content=data.message,
                options=data.options,
                attachments=data.attachments or None,
            ),
            on_client_disconnect=_make_push_callback(current_user["email"], conversation_id),
        ),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )


@router.post(
    "/conversations/{conversation_id}/messages/{message_id}/regenerate",
    summary="Regenerate an assistant message",
    response_class=StreamingResponse,
)
async def regenerate_message(
    conversation_id: str,
    message_id: str,
    data: RegenerateRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> StreamingResponse:
    """Delete the given assistant message and re-stream a new response."""

    return StreamingResponse(
        _sse_stream(
            service.regenerate_message(
                conversation_id=conversation_id,
                user_id=current_user["email"],
                message_id=message_id,
                options=data.options,
            ),
            on_client_disconnect=_make_push_callback(current_user["email"], conversation_id),
        ),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )


@router.post(
    "/conversations/{conversation_id}/messages/{message_id}/edit",
    summary="Edit a user message and re-run the conversation",
    response_class=StreamingResponse,
)
async def edit_message(
    conversation_id: str,
    message_id: str,
    data: EditMessageRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> StreamingResponse:
    """Update a user message's content, drop every later message, and re-stream."""

    return StreamingResponse(
        _sse_stream(
            service.edit_and_resend(
                conversation_id=conversation_id,
                user_id=current_user["email"],
                message_id=message_id,
                new_content=data.content,
                options=data.options,
            ),
            on_client_disconnect=_make_push_callback(current_user["email"], conversation_id),
        ),
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
) -> ModelList:
    models = await service.list_available_models()
    return ModelList(models=models, default_model=settings.default_model)


@router.get(
    "/health/llm",
    summary="Check LLM provider health",
)
async def health_check(
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> dict[str, bool]:
    return await service.health_check()
