"""Knowledge base API: upload, list, delete documents + semantic search."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.knowledge_base import (
    KnowledgeChunkMatch,
    KnowledgeDocumentList,
    KnowledgeDocumentOut,
    KnowledgeSearchResponse,
)
from app.services.knowledge_base_service import KnowledgeBaseService

router = APIRouter()


def get_kb_service(db: Annotated[AsyncSession, Depends(get_db)]) -> KnowledgeBaseService:
    return KnowledgeBaseService(db)


@router.post(
    "/documents",
    response_model=KnowledgeDocumentOut,
    status_code=status.HTTP_201_CREATED,
    summary="Upload a document to the knowledge base",
)
async def upload_document(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[KnowledgeBaseService, Depends(get_kb_service)],
    settings: Annotated[Settings, Depends(get_settings)],
    file: Annotated[UploadFile, File(...)],
) -> KnowledgeDocumentOut:
    max_bytes = settings.kb_max_file_size_mb * 1024 * 1024

    payload = await file.read()
    if len(payload) == 0:
        raise HTTPException(status_code=400, detail="Empty file")
    if len(payload) > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"File too large (max {settings.kb_max_file_size_mb} MB)",
        )

    try:
        doc = await service.create_document(
            user_id=current_user["email"],
            filename=file.filename or "document",
            mime_type=file.content_type or "",
            file_bytes=payload,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return KnowledgeDocumentOut.model_validate(doc)


@router.get(
    "/documents",
    response_model=KnowledgeDocumentList,
    summary="List knowledge base documents",
)
async def list_documents(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[KnowledgeBaseService, Depends(get_kb_service)],
) -> KnowledgeDocumentList:
    docs = await service.list_documents(user_id=current_user["email"])
    items = [KnowledgeDocumentOut.model_validate(d) for d in docs]
    return KnowledgeDocumentList(items=items, total=len(items))


@router.get(
    "/documents/{document_id}",
    response_model=KnowledgeDocumentOut,
    summary="Get a specific document",
)
async def get_document(
    document_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[KnowledgeBaseService, Depends(get_kb_service)],
) -> KnowledgeDocumentOut:
    doc = await service.get_document(document_id, user_id=current_user["email"])
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    return KnowledgeDocumentOut.model_validate(doc)


@router.delete(
    "/documents/{document_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a document and its chunks",
)
async def delete_document(
    document_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[KnowledgeBaseService, Depends(get_kb_service)],
) -> None:
    deleted = await service.delete_document(document_id, user_id=current_user["email"])
    if not deleted:
        raise HTTPException(status_code=404, detail="Document not found")


@router.get(
    "/search",
    response_model=KnowledgeSearchResponse,
    summary="Semantic search over the user's knowledge base",
)
async def search(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[KnowledgeBaseService, Depends(get_kb_service)],
    q: Annotated[str, Query(..., min_length=1, description="Search query")],
    limit: Annotated[int, Query(ge=1, le=20)] = 5,
) -> KnowledgeSearchResponse:
    matches = await service.search(user_id=current_user["email"], query=q, limit=limit)
    return KnowledgeSearchResponse(
        query=q,
        matches=[
            KnowledgeChunkMatch(
                document_id=m.document_id,
                document_filename=m.document_filename,
                content=m.content,
                score=m.score,
            )
            for m in matches
        ],
    )
