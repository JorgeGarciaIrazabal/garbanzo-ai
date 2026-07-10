"""Pydantic I/O schemas for the Micro-Apps Agentic Workspace feature.

The backend hosts a git worktree of the user's micro-apps monorepo, runs its
dev server + a headless opencode agent inside it, and exposes git
publish/revert. These models are the wire contract the Flutter frontend is
built against.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class WorkspaceStatus(BaseModel):
    """Live status of a user's micro-apps workspace."""

    state: Literal["stopped", "starting", "ready", "error"] = Field(
        ...,
        description=(
            "Lifecycle state. 'stopped' = no processes; 'starting' = worktree "
            "or subprocesses coming up; 'ready' = dev server + opencode live; "
            "'error' = last start failed (see setup_progress)."
        ),
    )
    dev_url: str | None = Field(
        None,
        description=(
            "Loopback URL of the running dev server (e.g. http://127.0.0.1:8142). "
            "Usable from the SAME host (Flutter web dev, desktop). NOT reachable "
            "from a separate Android device — use dev_port with the API-base host "
            "instead (see dev_port)."
        ),
    )
    dev_port: int | None = Field(
        None,
        description=(
            "Port the dev server listens on (binds all interfaces). Clients on a "
            "different host (Android device) should build the URL as "
            "http://<api-base-host>:<dev_port>/ so it resolves the same way the "
            "API base does."
        ),
    )
    branch: str | None = Field(
        None,
        description="Git branch backing this workspace (e.g. garbanzo/<slug>).",
    )
    opencode_ready: bool = Field(
        default=False,
        description="Whether the opencode agent HTTP API is reachable.",
    )
    proxied: bool = Field(
        default=False,
        description=(
            "When true, load the app through the backend's /micro-apps reverse "
            "proxy (same origin as the API) instead of connecting to dev_port "
            "directly. Set in deployments where only the backend is public."
        ),
    )
    panel_token: str | None = Field(
        None,
        description=(
            "Short-lived token to append as ?mp_token= on the first proxied "
            "panel request; the proxy exchanges it for an HttpOnly cookie. "
            "Only set when proxied is true."
        ),
    )
    setup_progress: str | None = Field(
        None,
        description=(
            "Human-readable progress or error message during setup "
            "(e.g. 'Installing dependencies for house-designer…')."
        ),
    )


class MicroAppInfo(BaseModel):
    """A single entry from the repo's registry.json, passed through verbatim.

    Unknown keys are preserved so the frontend and registry can evolve without
    a backend change.
    """

    model_config = ConfigDict(extra="allow")

    id: str = Field(..., description="Stable app id / directory name")
    name: str = Field(..., description="Human-readable app name")
    path: str = Field(..., description="Deploy path, e.g. 'house-designer/'")
    icon: str | None = Field(None, description="Emoji or icon hint")
    description: str | None = Field(None, description="Short description")
    projectParam: bool | None = Field(  # noqa: N815 — mirrors registry.json key
        None, description="Whether the app accepts a ?project= file URL"
    )
    dataDir: str | None = Field(  # noqa: N815 — mirrors registry.json key
        None, description="Directory holding this app's data files (e.g. 'houses/')"
    )
    dataExt: str | None = Field(  # noqa: N815 — mirrors registry.json key
        None, description="Data file extension (e.g. '.house.json')"
    )
    suggestions: list[str] | None = Field(
        None, description="Example instructions to seed the agent composer"
    )


class HouseFile(BaseModel):
    """A single house data file in the worktree's houses/ directory."""

    path: str = Field(..., description="Repo-relative path, e.g. 'houses/tiny-cabin.house.json'")
    name: str = Field(..., description="Base filename without directory")
    modified_at: float = Field(..., description="Last-modified time (epoch seconds)")
    size: int = Field(..., description="File size in bytes")


class ChangeFile(BaseModel):
    """One changed file in the working tree / branch vs the publish base."""

    path: str = Field(..., description="Repo-relative path")
    status: str = Field(
        ...,
        description="Single-letter git status: M, A, D, R, ? (untracked), or U (unmerged)",
    )
    plus: int = Field(default=0, description="Lines added (0 for binary/untracked)")
    minus: int = Field(default=0, description="Lines removed (0 for binary/untracked)")


class ChangesSummary(BaseModel):
    """Structured summary of uncommitted + committed changes vs origin/main."""

    files: list[ChangeFile] = Field(default_factory=list, description="Changed files")
    ahead: int = Field(default=0, description="Commits on this branch not on origin/main")
    behind: int = Field(default=0, description="Commits on origin/main not on this branch")


class PublishRequest(BaseModel):
    """Request to validate, commit, rebase and push the workspace changes."""

    message: str | None = Field(
        None,
        description="Commit message. A default is generated when omitted.",
    )


class PublishResult(BaseModel):
    """Outcome of a publish operation."""

    committed: bool = Field(..., description="Whether a commit was created")
    commit: str | None = Field(None, description="Short SHA of the new commit, if any")
    pushed: bool = Field(..., description="Whether the branch was pushed to origin/main")
    message: str = Field(..., description="Human-readable outcome summary")


class RevertRequest(BaseModel):
    """Request to discard changes, scoped to paths or (explicitly) everything."""

    paths: list[str] | None = Field(
        None,
        description="Repo-relative paths to revert. None + all=True reverts everything.",
    )
    all: bool = Field(
        default=False,
        description="Must be set true to revert ALL changes when paths is omitted.",
    )


class AgentChatRequest(BaseModel):
    """Request to stream an instruction to the opencode agent."""

    instruction: str = Field(..., min_length=1, description="Natural-language instruction (EN/ES)")
    session_id: str | None = Field(
        None,
        description="Existing opencode session id to continue; omit to start a new session.",
    )


class AgentAbortRequest(BaseModel):
    """Request to abort a running opencode session."""

    session_id: str = Field(..., description="opencode session id to abort")


class HouseCreateRequest(BaseModel):
    """Request to create a new house file from a template."""

    name: str = Field(
        ...,
        min_length=1,
        max_length=80,
        description="Human name; slugified into houses/<slug>.house.json",
    )
    template: str | None = Field(
        None,
        description="Template house filename to copy (default: tiny-cabin.house.json)",
    )


class FeatureDisabledResponse(BaseModel):
    """Returned (404) when MICROAPPS_REPO_PATH is unset."""

    detail: str = Field(default="Micro-apps workspace feature is disabled")
    metadata: dict[str, Any] | None = None
