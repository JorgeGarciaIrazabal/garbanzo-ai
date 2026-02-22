"""Chat API endpoints for conversations and messaging."""

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
    ConversationUpdate,
    ModelList,
)
from app.services.chat_service import ChatService

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
    conversation = await service.conversations.update(
        conversation_id=conversation_id,
        user_id=current_user["email"],
        title=data.title,
        model=data.model,
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

    async def event_generator():
        try:
            async for chunk in service.send_message(
                conversation_id=conversation_id,
                user_id=current_user["email"],
                content=data.message,
                options=data.options,
            ):
                if chunk.is_finished:
                    response = ChatResponseChunk(type="done", metadata=chunk.metadata)
                elif chunk.metadata and chunk.metadata.get("error"):
                    response = ChatResponseChunk(
                        type="error", error=chunk.content, metadata=chunk.metadata,
                    )
                elif chunk.is_thinking:
                    response = ChatResponseChunk(type="thinking", content=chunk.content)
                else:
                    response = ChatResponseChunk(type="chunk", content=chunk.content)

                yield f"data: {response.model_dump_json()}\n\n"

        except Exception as e:
            error_response = ChatResponseChunk(
                type="error", error=str(e), metadata={"error": True},
            )
            yield f"data: {error_response.model_dump_json()}\n\n"

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


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
) -> ModelList:
    models = await service.list_available_models()
    return ModelList(models=models)


@router.get(
    "/health/llm",
    summary="Check LLM provider health",
)
async def health_check(
    service: Annotated[ChatService, Depends(get_chat_service)],
) -> dict[str, bool]:
    return await service.health_check()
