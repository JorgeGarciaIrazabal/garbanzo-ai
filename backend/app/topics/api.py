"""Authenticated topic discovery and active-context endpoints."""

from datetime import UTC, datetime
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.chat import message_out
from app.topics.active_context_schemas import (
    ActiveContextItemCreate,
    ActiveContextItemOut,
    ActiveContextItemUpdate,
    ActiveContextResponse,
    ContextMutationResponse,
    FreshStartRequest,
    TopicArchiveDetailResponse,
    TopicArchiveListResponse,
    TopicArchiveOut,
    TopicSwitchRequest,
    TopicSwitchResponse,
)
from app.topics.active_context_service import (
    ActiveContextService,
    ContextSourceNotFoundError,
    ContextVersionConflictError,
)
from app.topics.schemas import (
    TopicActivationResponse,
    TopicContextStatus,
    TopicListResponse,
    TopicSelectionUpdate,
)
from app.topics.topic_service import (
    PrimaryConversationRequiredError,
    TopicNotFoundError,
    TopicService,
    TopicVersionConflictError,
)
from app.topics.topic_switch_service import (
    TopicSwitchError,
    TopicSwitchService,
)

router = APIRouter()


def _topic_service(db: Annotated[AsyncSession, Depends(get_db)]) -> TopicService:
    return TopicService(db)


def _context_service(db: Annotated[AsyncSession, Depends(get_db)]) -> ActiveContextService:
    return ActiveContextService(db)


def _switch_service(db: Annotated[AsyncSession, Depends(get_db)]) -> TopicSwitchService:
    return TopicSwitchService(db)


def _not_found() -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="not_found")


def _primary_required() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail="Dynamic context is available only in the primary chat",
    )


def _version_conflict(
    error: ContextVersionConflictError | TopicVersionConflictError,
) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail={
            "code": "context_version_conflict",
            "current_context_version": error.current_version,
        },
    )


@router.get("/topics", response_model=TopicListResponse, summary="List generated topics")
async def list_topics(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[TopicService, Depends(_topic_service)],
    mode: Literal["personal", "explore"] = Query("personal"),
) -> TopicListResponse:
    topics = (
        await service.list_personal(current_user["email"])
        if mode == "personal"
        else service.list_explore()
    )
    return TopicListResponse(mode=mode, topics=topics, generated_at=datetime.now(UTC))


@router.patch(
    "/conversations/{conversation_id}/topic",
    response_model=TopicActivationResponse,
    summary="Pin or unpin the active primary-chat topic",
)
async def update_active_topic(
    conversation_id: str,
    data: TopicSelectionUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[TopicService, Depends(_topic_service)],
) -> TopicActivationResponse:
    try:
        conversation, topic = await service.set_pinned(
            conversation_id,
            current_user["email"],
            pinned=data.pinned,
            context_version=data.context_version,
        )
    except TopicNotFoundError as error:
        raise _not_found() from error
    except PrimaryConversationRequiredError as error:
        raise _primary_required() from error
    except TopicVersionConflictError as error:
        raise _version_conflict(error) from error
    context_status = await service.context_status(topic) if topic else TopicContextStatus()
    return TopicActivationResponse(
        conversation_id=conversation.id,
        topic=service._node(topic, context_status) if topic else None,
        topic_is_pinned=conversation.topic_is_pinned,
        context_version=conversation.context_version,
        context_status=context_status,
    )


@router.get(
    "/topics/{topic_id}/context-status",
    summary="Get context pack and live-delta freshness",
)
async def get_topic_context_status(
    topic_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[TopicService, Depends(_topic_service)],
):
    topic = await service.get_owned_topic(topic_id, current_user["email"])
    if topic is None:
        raise _not_found()
    return await service.context_status(topic)


@router.get(
    "/conversations/{conversation_id}/context",
    response_model=ActiveContextResponse,
    summary="Get the current active context",
)
async def get_active_context(
    conversation_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ActiveContextService, Depends(_context_service)],
) -> ActiveContextResponse:
    try:
        return await service.get(conversation_id, current_user["email"])
    except ContextSourceNotFoundError as error:
        raise _not_found() from error


@router.post(
    "/conversations/{conversation_id}/context/items",
    response_model=ContextMutationResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add or restore an owned context source",
)
async def add_active_context_item(
    conversation_id: str,
    data: ActiveContextItemCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ActiveContextService, Depends(_context_service)],
) -> ContextMutationResponse:
    try:
        item, version = await service.add_item(
            conversation_id,
            current_user["email"],
            source_type=data.source_type,
            source_id=data.source_id,
            source_meta=data.source_meta,
            topic_id=data.topic_id,
            state=data.state,
            reason=data.reason,
            context_version=data.context_version,
        )
    except ContextVersionConflictError as error:
        raise _version_conflict(error) from error
    except ContextSourceNotFoundError as error:
        raise _not_found() from error
    return ContextMutationResponse(
        item=ActiveContextItemOut.model_validate(item), context_version=version
    )


@router.patch(
    "/conversations/{conversation_id}/context/items/{item_id}",
    response_model=ContextMutationResponse,
    summary="Pin, unpin, exclude, or restore a context item",
)
async def update_active_context_item(
    conversation_id: str,
    item_id: str,
    data: ActiveContextItemUpdate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ActiveContextService, Depends(_context_service)],
) -> ContextMutationResponse:
    try:
        item, version = await service.update_item(
            conversation_id,
            item_id,
            current_user["email"],
            state=data.state,
            context_version=data.context_version,
        )
    except ContextVersionConflictError as error:
        raise _version_conflict(error) from error
    except ContextSourceNotFoundError as error:
        raise _not_found() from error
    return ContextMutationResponse(
        item=ActiveContextItemOut.model_validate(item), context_version=version
    )


@router.post(
    "/conversations/{conversation_id}/context/fresh-start",
    response_model=ContextMutationResponse,
    summary="Clear dynamic context without deleting messages",
)
async def fresh_start_context(
    conversation_id: str,
    data: FreshStartRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[ActiveContextService, Depends(_context_service)],
) -> ContextMutationResponse:
    try:
        version = await service.fresh_start(
            conversation_id,
            current_user["email"],
            keep_pins=data.keep_pins,
            context_version=data.context_version,
        )
    except ContextVersionConflictError as error:
        raise _version_conflict(error) from error
    except ContextSourceNotFoundError as error:
        raise _not_found() from error
    return ContextMutationResponse(context_version=version)


@router.post(
    "/conversations/{conversation_id}/topics/switch",
    response_model=TopicSwitchResponse,
    summary="Idempotently switch or combine the primary chat topic",
)
async def switch_topic(
    conversation_id: str,
    data: TopicSwitchRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[TopicSwitchService, Depends(_switch_service)],
) -> TopicSwitchResponse:
    user = await service.db.get(User, current_user["email"])
    if user is None:
        raise _not_found()
    try:
        if data.mode == "combine":
            return await service.combine(
                conversation_id=conversation_id,
                user=user,
                topic_id=data.topic_id,
                label=data.label,
                idempotency_key=data.idempotency_key,
            )
        return await service.switch(
            conversation_id=conversation_id,
            user=user,
            topic_id=data.topic_id,
            label=data.label,
            idempotency_key=data.idempotency_key,
            archive=data.archive,
            retain_pinned=data.retain_pinned,
        )
    except TopicSwitchError as error:
        detail = str(error)
        if detail == "topic_not_found":
            raise _not_found() from error
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=detail,
        ) from error
    except PrimaryConversationRequiredError as error:
        raise _primary_required() from error
    except TopicNotFoundError as error:
        raise _not_found() from error


@router.get(
    "/topics/{topic_id}/archives",
    response_model=TopicArchiveListResponse,
    summary="List archived primary threads attached to a topic",
)
async def list_topic_archives(
    topic_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[TopicSwitchService, Depends(_switch_service)],
) -> TopicArchiveListResponse:
    user = await service.db.get(User, current_user["email"])
    if user is None:
        raise _not_found()
    try:
        archives = await service.list_archives(topic_id, user)
    except TopicNotFoundError as error:
        raise _not_found() from error
    return TopicArchiveListResponse(
        topic_id=topic_id,
        archives=[TopicArchiveOut.model_validate(archive) for archive in archives],
    )


@router.get(
    "/topics/{topic_id}/archives/{archive_id}",
    response_model=TopicArchiveDetailResponse,
    summary="Read messages from an archived primary-chat session",
)
async def get_topic_archive(
    topic_id: str,
    archive_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[TopicSwitchService, Depends(_switch_service)],
    before: Annotated[str | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 100,
) -> TopicArchiveDetailResponse:
    user = await service.db.get(User, current_user["email"])
    if user is None:
        raise _not_found()
    try:
        archive, epoch, messages, has_more = await service.get_archive_messages(
            topic_id,
            archive_id,
            user,
            before=before,
            limit=limit,
        )
    except TopicNotFoundError as error:
        raise _not_found() from error
    except TopicSwitchError as error:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(error),
        ) from error
    return TopicArchiveDetailResponse(
        archive=TopicArchiveOut.model_validate(archive),
        topic_label=(archive.payload or {}).get("topic_label"),
        session_epoch=epoch,
        messages=[message_out(message) for message in messages],
        has_more=has_more,
    )
