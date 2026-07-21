"""Pydantic schemas for delegated opencode workflow runs (idea 18)."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

WorkflowStatus = Literal[
    "draft",
    "uploading",
    "queued",
    "running",
    "done",
    "error",
    "cancelled",
]
WorkflowMode = Literal["folder", "research"]

# Terminal statuses — the client stops polling once a run reaches one.
TERMINAL_STATUSES = frozenset({"done", "error", "cancelled"})

# Snapshot budgets. Per-file matches the idea-17 read cap; the totals stop a
# stray "attach my home directory" from filling the server's disk.
MAX_FILE_BYTES = 5 * 1024 * 1024
MAX_TOTAL_BYTES = 50 * 1024 * 1024
MAX_FILE_COUNT = 2000


class WorkflowCreate(BaseModel):
    """Create a run in ``draft``; nothing executes until ``/start``."""

    instruction: str = Field(..., min_length=1, max_length=10000)
    mode: WorkflowMode = Field(
        default="folder",
        description="folder uploads a client snapshot; research starts from an empty workdir.",
    )
    conversation_id: str | None = None
    room_id: str | None = None
    tool_call_id: str | None = Field(default=None, max_length=64)
    folder_label: str | None = Field(
        default=None,
        max_length=255,
        description="Display name of the client folder (never acted on server-side).",
    )


class WorkflowFile(BaseModel):
    """One uploaded snapshot file, base64-encoded like the idea-17 bridge."""

    path: str = Field(..., min_length=1, max_length=1024)
    data: str = Field(..., description="Base64-encoded file bytes.")


class WorkflowFilesUpload(BaseModel):
    """A batch of snapshot files. Clients send several of these per run."""

    files: list[WorkflowFile]


class WorkflowUploadResult(BaseModel):
    """Running totals so the client can show upload progress."""

    file_count: int
    total_bytes: int


class WorkflowChange(BaseModel):
    """One file the workflow created, modified, or deleted.

    ``base_sha256`` is the hash of the content the client uploaded. The client
    re-hashes its local copy before applying: a mismatch means the file changed
    locally during the run, so the change is reported as a conflict instead of
    silently clobbering the user's edit.
    """

    path: str
    status: Literal["added", "modified", "deleted"]
    data: str | None = Field(default=None, description="Base64 of the new content.")
    base_sha256: str | None = None
    size: int = 0


class WorkflowChanges(BaseModel):
    """The full diff of a finished run."""

    run_id: str
    changes: list[WorkflowChange]


class WorkflowOut(BaseModel):
    """A run as returned by the API. ``workdir`` is deliberately never exposed."""

    id: str
    user_id: str
    conversation_id: str | None = None
    room_id: str | None = None
    tool_call_id: str | None = None
    status: WorkflowStatus
    instruction: str
    scope: dict[str, Any] | None = None
    summary: str | None = None
    error: str | None = None
    progress: list[dict[str, Any]] = Field(default_factory=list)
    # Index of the first chunk in ``progress`` (for ?since= paging) and the
    # total emitted so far, so the client knows the next cursor.
    progress_offset: int = 0
    progress_total: int = 0
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None = None

    model_config = {"from_attributes": True}
