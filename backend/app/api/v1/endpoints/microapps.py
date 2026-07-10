"""Micro-Apps Agentic Workspace endpoints.

Every route is behind ``get_current_user`` and behind the feature flag: when
``MICROAPPS_REPO_PATH`` is unset the whole group returns 404 with a clear
"feature disabled" message.
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse

from app.core.config import get_settings
from app.core.security import create_microapps_panel_token, get_current_user
from app.schemas.chat import ChatResponseChunk
from app.schemas.microapp import (
    AgentAbortRequest,
    AgentChatRequest,
    ChangesSummary,
    HouseCreateRequest,
    HouseFile,
    MicroAppInfo,
    PublishRequest,
    PublishResult,
    RevertRequest,
    WorkspaceStatus,
)
from app.services import microapp_registry
from app.services.microapp_agent import agent
from app.services.microapp_workspace import (
    FeatureDisabledError,
    Workspace,
    WorkspaceError,
    manager,
)

logger = logging.getLogger(__name__)

router = APIRouter()

_SSE_HEADERS = {
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no",
}


def require_feature() -> None:
    """404 when the micro-apps feature is disabled."""
    if not manager.enabled:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Micro-apps workspace feature is disabled",
        )


FeatureGate = Annotated[None, Depends(require_feature)]
CurrentUser = Annotated[dict[str, Any], Depends(get_current_user)]


def _to_status(ws: Workspace) -> WorkspaceStatus:
    settings = get_settings()
    proxied = settings.microapps_proxy_mode
    return WorkspaceStatus(
        state=ws.state,
        dev_url=ws.dev_url,
        dev_port=ws.dev_port if ws.state in ("starting", "ready") else None,
        branch=ws.branch,
        opencode_ready=ws.opencode_ready,
        setup_progress=ws.setup_progress,
        proxied=proxied,
        panel_token=(
            create_microapps_panel_token(ws.user_email, ws.slug, settings)
            if proxied
            else None
        ),
    )


def _worktree_or_repo(user_email: str) -> Path:
    """The user's worktree if it exists on disk, else the shared repo root."""
    ws = manager.status(user_email)
    return ws.path if ws.path.is_dir() else manager.repo_path


# ---------------------------------------------------------------------------
# Workspace lifecycle
# ---------------------------------------------------------------------------


@router.post("/workspace", response_model=WorkspaceStatus)
async def start_workspace(_: FeatureGate, current_user: CurrentUser) -> WorkspaceStatus:
    """Create/start the worktree, dev server and opencode agent for the user."""
    try:
        ws = await manager.ensure(current_user["email"])
    except FeatureDisabledError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except WorkspaceError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    return _to_status(ws)


@router.get("/workspace", response_model=WorkspaceStatus)
async def get_workspace(_: FeatureGate, current_user: CurrentUser) -> WorkspaceStatus:
    """Return the in-memory status of the user's workspace (no side effects)."""
    return _to_status(manager.status(current_user["email"]))


@router.delete("/workspace", response_model=WorkspaceStatus)
async def stop_workspace(_: FeatureGate, current_user: CurrentUser) -> WorkspaceStatus:
    """Stop the dev server + agent processes. The worktree is kept on disk."""
    manager.stop(current_user["email"])
    return _to_status(manager.status(current_user["email"]))


# ---------------------------------------------------------------------------
# Registry + houses
# ---------------------------------------------------------------------------


@router.get("/apps", response_model=list[MicroAppInfo])
async def list_apps(_: FeatureGate, current_user: CurrentUser) -> list[MicroAppInfo]:
    """List micro-apps from the worktree's (or repo's) registry.json."""
    return microapp_registry.read_registry(_worktree_or_repo(current_user["email"]))


@router.get("/houses", response_model=list[HouseFile])
async def list_houses(_: FeatureGate, current_user: CurrentUser) -> list[HouseFile]:
    """List the git-tracked house data files in the workspace."""
    return microapp_registry.list_houses(_worktree_or_repo(current_user["email"]))


@router.post("/houses", response_model=HouseFile, status_code=status.HTTP_201_CREATED)
async def create_house(
    _: FeatureGate, current_user: CurrentUser, data: HouseCreateRequest
) -> HouseFile:
    """Create a new house file from a template in the user's worktree."""
    try:
        rel = await asyncio.to_thread(
            manager.create_house, current_user["email"], data.name, data.template
        )
    except WorkspaceError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    houses = microapp_registry.list_houses(manager.status(current_user["email"]).path)
    for h in houses:
        if h.path == rel:
            return h
    raise HTTPException(status_code=500, detail="Created house not found on disk")


# ---------------------------------------------------------------------------
# Agent (SSE)
# ---------------------------------------------------------------------------


async def _sse(gen: AsyncIterator[ChatResponseChunk]) -> AsyncIterator[str]:
    try:
        async for chunk in gen:
            yield f"data: {chunk.model_dump_json()}\n\n"
    except Exception as exc:  # noqa: BLE001
        err = ChatResponseChunk(type="error", error=str(exc)[:500])
        yield f"data: {err.model_dump_json()}\n\n"


@router.post("/agent/chat")
async def agent_chat(
    _: FeatureGate, current_user: CurrentUser, data: AgentChatRequest
) -> StreamingResponse:
    """Stream an instruction to the opencode agent as Server-Sent Events."""
    workspace = manager.status(current_user["email"])
    return StreamingResponse(
        _sse(agent.stream_instruction(workspace, data.instruction, data.session_id)),
        media_type="text/event-stream",
        headers=_SSE_HEADERS,
    )


@router.post("/agent/abort")
async def agent_abort(
    _: FeatureGate, current_user: CurrentUser, data: AgentAbortRequest
) -> dict[str, bool]:
    """Abort a running opencode session."""
    workspace = manager.status(current_user["email"])
    ok = await agent.abort(workspace, data.session_id)
    return {"aborted": ok}


# ---------------------------------------------------------------------------
# Git: changes / publish / revert
# ---------------------------------------------------------------------------


@router.get("/changes", response_model=ChangesSummary)
async def get_changes(_: FeatureGate, current_user: CurrentUser) -> ChangesSummary:
    """Structured summary of the workspace changes vs origin/main."""
    try:
        return await asyncio.to_thread(manager.changes, current_user["email"])
    except WorkspaceError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/publish", response_model=PublishResult)
async def publish(
    _: FeatureGate, current_user: CurrentUser, data: PublishRequest
) -> PublishResult:
    """Validate houses, commit, rebase onto origin/main and push HEAD:main."""
    try:
        return await asyncio.to_thread(
            manager.publish, current_user["email"], data.message
        )
    except WorkspaceError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc


@router.post("/revert", response_model=ChangesSummary)
async def revert(
    _: FeatureGate, current_user: CurrentUser, data: RevertRequest
) -> ChangesSummary:
    """Discard changes, scoped to paths or (explicitly) everything."""
    try:
        return await asyncio.to_thread(
            manager.revert, current_user["email"], data.paths, data.all
        )
    except WorkspaceError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
