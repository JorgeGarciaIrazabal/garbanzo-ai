"""Authenticated virtual folders, original-byte downloads and reusable chat links."""

from collections.abc import AsyncGenerator
from typing import Annotated, Any
from urllib.parse import quote

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, Response, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.virtual_folder import (
    MAX_FILE_BYTES,
    MAX_PAGE_CHARS,
    FileOut,
    FileText,
    FolderName,
    FolderOut,
    TextCreate,
    TextUpdate,
)
from app.services.virtual_folder_service import FolderError, VirtualFolderService

router = APIRouter()
User = Annotated[dict[str, Any], Depends(get_current_user)]


async def get_service(
    db: Annotated[AsyncSession, Depends(get_db)],
) -> AsyncGenerator[VirtualFolderService]:
    try:
        yield VirtualFolderService(db)
    except FolderError as exc:
        await db.rollback()
        raise HTTPException(status_code=exc.status_code, detail=str(exc)) from exc


Service = Annotated[VirtualFolderService, Depends(get_service)]


def download(data: bytes, filename: str, media_type: str) -> Response:
    return Response(
        data,
        media_type=media_type,
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{quote(filename, safe='')}",
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "private, no-store",
        },
    )


@router.get("", response_model=list[FolderOut])
async def list_folders(user: User, service: Service):
    return await service.list_folders(user["email"])


@router.post("", response_model=FolderOut, status_code=201)
async def create_folder(data: FolderName, user: User, service: Service):
    return await service.create_folder(user["email"], data.name)


# Static conversation routes precede folder-id routes.
@router.get("/conversations/{conversation_id}", response_model=list[FolderOut])
async def list_attached(conversation_id: str, user: User, service: Service):
    return await service.attached_folders(conversation_id, user["email"])


@router.put("/conversations/{conversation_id}/{folder_id}", response_model=FolderOut)
async def attach_folder(conversation_id: str, folder_id: str, user: User, service: Service):
    return await service.attach(conversation_id, folder_id, user["email"])


@router.delete("/conversations/{conversation_id}/{folder_id}", status_code=204)
async def detach_folder(conversation_id: str, folder_id: str, user: User, service: Service):
    await service.detach(conversation_id, folder_id, user["email"])


@router.patch("/{folder_id}", response_model=FolderOut)
async def rename_folder(folder_id: str, data: FolderName, user: User, service: Service):
    return await service.rename_folder(folder_id, user["email"], data.name)


@router.delete("/{folder_id}", status_code=204)
async def delete_folder(folder_id: str, user: User, service: Service):
    await service.delete_folder(folder_id, user["email"])


@router.get("/{folder_id}/files", response_model=list[FileOut])
async def list_files(folder_id: str, user: User, service: Service):
    return await service.list_files(folder_id, user["email"])


@router.post("/{folder_id}/files", response_model=FileOut, status_code=201)
async def upload_file(
    folder_id: str,
    user: User,
    service: Service,
    file: Annotated[UploadFile, File()],
    path: Annotated[str | None, Form()] = None,
):
    await service.owned_folder(folder_id, user["email"])
    payload = await file.read(MAX_FILE_BYTES + 1)
    if len(payload) > MAX_FILE_BYTES:
        raise FolderError("File exceeds the 10 MiB limit.", 413)
    return await service.create_file(
        folder_id, user["email"], path or file.filename or "file", payload
    )


@router.post("/{folder_id}/text", response_model=FileOut, status_code=201)
async def create_text(folder_id: str, data: TextCreate, user: User, service: Service):
    return await service.create_text(folder_id, user["email"], data.path, data.content)


@router.get("/{folder_id}/files/{file_id}/content")
async def download_file(folder_id: str, file_id: str, user: User, service: Service):
    file = await service.get_file(folder_id, file_id, user["email"], data=True)
    return download(file.data, file.path.rsplit("/", 1)[-1], file.media_type)


@router.get("/{folder_id}/files/{file_id}/text", response_model=FileText)
async def read_text(
    folder_id: str,
    file_id: str,
    user: User,
    service: Service,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=MAX_PAGE_CHARS)] = MAX_PAGE_CHARS,
):
    return await service.read_text(folder_id, file_id, user["email"], offset, limit)


@router.put("/{folder_id}/files/{file_id}/text", response_model=FileOut)
async def update_text(folder_id: str, file_id: str, data: TextUpdate, user: User, service: Service):
    return await service.update_text(folder_id, file_id, user["email"], data.content, data.revision)


@router.delete("/{folder_id}/files/{file_id}", status_code=204)
async def delete_file(
    folder_id: str,
    file_id: str,
    user: User,
    service: Service,
    revision: Annotated[int, Query(ge=1)],
):
    await service.delete_file(folder_id, file_id, user["email"], revision)


@router.get("/{folder_id}/download")
async def download_folder(folder_id: str, user: User, service: Service):
    filename, data = await service.archive(folder_id, user["email"])
    return download(data, filename, "application/zip")
