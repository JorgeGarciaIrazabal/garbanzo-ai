"""Delegated opencode workflow runs (idea 18).

Folder runs upload a client snapshot; research runs start with an empty
server-side workdir. Execution is detached from the request, and the client
follows along with ``GET /workflows/{id}?since=<cursor>``.
"""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.models.workflow_run import WorkflowRun
from app.schemas.workflow import (
    WorkflowChanges,
    WorkflowCreate,
    WorkflowFilesUpload,
    WorkflowOut,
    WorkflowUploadResult,
)
from app.services import workflow_runner, workflow_watchers
from app.services.workflow_service import WorkflowError, WorkflowService

router = APIRouter()


def get_service(db: Annotated[AsyncSession, Depends(get_db)]) -> WorkflowService:
    return WorkflowService(db)


def _to_out(run: WorkflowRun, *, since: int = 0) -> WorkflowOut:
    """Serialize a run, returning only the progress after ``since``."""
    progress = list(run.progress or [])
    offset = min(max(since, 0), len(progress))
    return WorkflowOut(
        id=run.id,
        user_id=run.user_id,
        conversation_id=run.conversation_id,
        room_id=run.room_id,
        tool_call_id=run.tool_call_id,
        status=run.status,  # type: ignore[arg-type]
        instruction=run.instruction,
        scope=run.scope,
        summary=run.summary,
        error=run.error,
        progress=progress[offset:],
        progress_offset=offset,
        progress_total=len(progress),
        created_at=run.created_at,
        updated_at=run.updated_at,
        completed_at=run.completed_at,
    )


async def _owned(
    run_id: str,
    user_id: str,
    service: WorkflowService,
) -> WorkflowRun:
    run = await service.get(run_id, user_id)
    if run is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Workflow not found")
    return run


@router.post(
    "",
    response_model=WorkflowOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a delegated workflow run (draft — nothing executes yet)",
)
async def create_workflow(
    data: WorkflowCreate,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[WorkflowService, Depends(get_service)],
) -> WorkflowOut:
    try:
        if data.conversation_id:
            mcp_tools = await service.conversation_mcp_tools(
                data.conversation_id, current_user["email"]
            )
            attached_files = await service.conversation_attachments(
                data.conversation_id,
                current_user["email"],
                data.tool_call_id,
            )
        else:
            mcp_tools = []
            attached_files = []
        run = await service.create(
            user_id=current_user["email"],
            instruction=data.instruction,
            conversation_id=data.conversation_id,
            room_id=data.room_id,
            tool_call_id=data.tool_call_id,
            folder_label=data.folder_label,
            mode=data.mode,
            mcp_tools=mcp_tools,
            attached_files=attached_files,
        )
    except WorkflowError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    return _to_out(run)


@router.get(
    "",
    response_model=list[WorkflowOut],
    summary="List the user's runs for a conversation (hydrates cards after reload)",
)
async def list_workflows(
    conversation_id: Annotated[str, Query()],
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[WorkflowService, Depends(get_service)],
) -> list[WorkflowOut]:
    runs = await service.list_for_conversation(current_user["email"], conversation_id)
    # Progress is omitted from the list view; clients fetch it per run.
    return [_to_out(run, since=len(run.progress or [])) for run in runs]


@router.post(
    "/{run_id}/files",
    response_model=WorkflowUploadResult,
    summary="Upload a batch of the folder snapshot",
)
async def upload_files(
    run_id: str,
    data: WorkflowFilesUpload,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[WorkflowService, Depends(get_service)],
) -> WorkflowUploadResult:
    run = await _owned(run_id, current_user["email"], service)
    try:
        count, total = await service.add_files(run, [(f.path, f.data) for f in data.files])
    except WorkflowError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return WorkflowUploadResult(file_count=count, total_bytes=total)


@router.post(
    "/{run_id}/start",
    response_model=WorkflowOut,
    summary="Baseline the snapshot and start the detached run",
)
async def start_workflow(
    run_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[WorkflowService, Depends(get_service)],
) -> WorkflowOut:
    run = await _owned(run_id, current_user["email"], service)
    try:
        await service.start_snapshot(run)
    except WorkflowError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    # Detached on purpose: the run must survive this request ending.
    workflow_runner.launch(run.id)
    return _to_out(run)


@router.get(
    "/{run_id}",
    response_model=WorkflowOut,
    summary="Poll a run's status and progress",
)
async def get_workflow(
    run_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[WorkflowService, Depends(get_service)],
    since: Annotated[int, Query(ge=0)] = 0,
) -> WorkflowOut:
    run = await _owned(run_id, current_user["email"], service)
    # This poll is also the "someone is looking at the app" signal, which
    # suppresses the completion push (see workflow_watchers).
    workflow_watchers.mark_watching(run_id)
    return _to_out(run, since=since)


@router.get(
    "/{run_id}/changes",
    response_model=WorkflowChanges,
    summary="The run's git diff, for the client to apply locally",
)
async def get_changes(
    run_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[WorkflowService, Depends(get_service)],
) -> WorkflowChanges:
    run = await _owned(run_id, current_user["email"], service)
    if run.status in ("draft", "uploading", "queued", "running"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This workflow is still running.",
        )
    try:
        changes = await service.compute_changes(run)
    except WorkflowError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    return WorkflowChanges(run_id=run.id, changes=changes)


@router.get(
    "/{run_id}/output",
    response_class=Response,
    summary="Download a completed research workflow's markdown output",
)
async def get_output(
    run_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[WorkflowService, Depends(get_service)],
) -> Response:
    run = await _owned(run_id, current_user["email"], service)
    if (run.scope or {}).get("mode", "folder") != "research":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Only research workflows have downloadable output.",
        )
    if run.status != "done":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This workflow has not completed successfully.",
        )
    return Response(
        content=run.summary or "",
        media_type="text/markdown",
        headers={"Content-Disposition": f'attachment; filename="research-{run.id}.md"'},
    )


@router.post(
    "/{run_id}/applied",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Discard the server-side snapshot once the client has applied the diff",
)
async def mark_applied(
    run_id: str,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[WorkflowService, Depends(get_service)],
) -> None:
    run = await _owned(run_id, current_user["email"], service)
    if (run.scope or {}).get("mode", "folder") != "folder":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Research workflows have no file changes to apply.",
        )
    await service.cleanup(run)
