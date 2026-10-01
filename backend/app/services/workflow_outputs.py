"""Durable, bounded workflow artifacts and owner-scoped model retrieval."""

from __future__ import annotations

import asyncio
import hashlib
import io
import json
import mimetypes
import os
import stat
import subprocess
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any, Literal

from markitdown import MarkItDown
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import undefer

from app.core.config import get_settings
from app.models.workflow_artifact import WorkflowArtifact
from app.models.workflow_run import WorkflowRun
from app.schemas.workflow import MAX_FILE_BYTES, MAX_FILE_COUNT, MAX_TOTAL_BYTES, TERMINAL_STATUSES
from app.services.client_file_extract import (
    _MARKITDOWN_EXTENSIONS,
    _STRUCTURED_EXTENSIONS,
    TEXT_EXTENSIONS,
)
from app.services.knowledge_base_service import _looks_like_text, extract_text
from app.services.workflow_service import WorkflowError, _run_git

# Traversal itself is bounded, including directories and files that are not outputs.
MAX_TREE_ENTRIES = 10000
MAX_TEXT_CHARS = 5 * 1024 * 1024
MAX_PAGE_CHARS = 12000
_EXCLUDED_DIRS = frozenset(
    {
        ".git",
        ".garbanzo-workflow-inputs",
        ".opencode",
        "node_modules",
        "__pycache__",
        ".venv",
        "venv",
        ".pytest_cache",
        ".ruff_cache",
        ".mypy_cache",
    }
)


def canonical_path(path: str) -> str:
    parts = PurePosixPath(path).parts
    if (
        not path
        or path.startswith("/")
        or "\\" in path
        or "\x00" in path
        or ".." in parts
        or str(PurePosixPath(path)) != path
        or len(path) > 1024
    ):
        raise WorkflowError("Unsafe output path.")
    return path


def collect_artifacts(workdir: Path, mode: str, baseline: str | None) -> list[dict[str, Any]]:
    """Snapshot real output bytes without staging git or following any symlinks."""
    originals: dict[str, str] = {}
    hash_algorithm = "sha1"
    if mode == "folder":
        if not baseline:
            raise WorkflowError("The workflow output baseline is missing.")
        tree = _run_git(workdir, "ls-tree", "-r", "-z", baseline)
        for entry in tree.stdout.split(b"\0"):
            if entry:
                metadata, path = entry.split(b"\t", 1)
                originals[canonical_path(path.decode("utf-8"))] = metadata.split()[2].decode()
        hash_algorithm = (
            _run_git(workdir, "rev-parse", "--show-object-format").stdout.decode().strip()
        )
    artifacts: list[dict[str, Any]] = []
    total = 0
    for dirfd, name, path, info in _walk_outputs(workdir):
        if path == "opencode.json" and (mode == "research" or path not in originals):
            continue  # server-generated configuration; never an output
        if not stat.S_ISREG(info.st_mode):
            raise WorkflowError(f"Output {path!r} is not a regular file (symlinks are forbidden).")
        if info.st_size > MAX_FILE_BYTES:
            raise WorkflowError(f"Output {path!r} exceeds the file size limit.")
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dirfd)
        with os.fdopen(fd, "rb") as handle:
            if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
                raise WorkflowError(f"Output {path!r} changed during capture.")
            data = handle.read(MAX_FILE_BYTES + 1)
        if len(data) > MAX_FILE_BYTES:
            raise WorkflowError("Workflow outputs exceed the file size limit.")
        if mode == "folder" and path in originals:
            blob = f"blob {len(data)}\0".encode() + data
            if hashlib.new(hash_algorithm, blob).hexdigest() == originals[path]:
                continue
        total += len(data)
        if len(artifacts) >= MAX_FILE_COUNT or total > MAX_TOTAL_BYTES:
            raise WorkflowError("Workflow outputs exceed the count or byte limits.")
        artifacts.append(
            {
                "id": str(uuid.uuid4()),
                "path": path,
                "data": data,
                "size_bytes": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
                "media_type": mimetypes.guess_type(path)[0] or "application/octet-stream",
            }
        )
    return sorted(artifacts, key=lambda entry: entry["path"])


def _walk_outputs(workdir: Path):
    """Lazy descriptor-based traversal; bound entries before allocating directory lists."""
    visited = 0

    def walk(dirfd, prefix, depth):
        nonlocal visited
        if depth > 100:
            raise WorkflowError("Workflow output tree exceeds the depth limit.")
        with os.scandir(dirfd) as entries:
            for entry in entries:
                visited += 1
                if visited > MAX_TREE_ENTRIES:
                    raise WorkflowError("Workflow output tree exceeds the traversal limit.")
                if entry.name in _EXCLUDED_DIRS:
                    continue
                path = canonical_path(prefix + entry.name)
                info = entry.stat(follow_symlinks=False)
                if stat.S_ISDIR(info.st_mode):
                    child = os.open(
                        entry.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dirfd
                    )
                    try:
                        yield from walk(child, path + "/", depth + 1)
                    finally:
                        os.close(child)
                else:
                    yield dirfd, entry.name, path, info

    rootfd = os.open(workdir, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        yield from walk(rootfd, "", 0)
    finally:
        os.close(rootfd)


async def capture_outputs(db: AsyncSession, run: WorkflowRun) -> None:
    """Stage artifacts in the terminal-state transaction; caller commits once."""
    if not run.workdir:
        raise WorkflowError("The workflow workspace is missing; output files cannot be preserved.")
    try:
        entries = await asyncio.to_thread(
            collect_artifacts,
            Path(run.workdir),
            (run.scope or {}).get("mode", "folder"),
            (run.scope or {}).get("baseline_revision"),
        )
    except OSError as exc:
        raise WorkflowError(
            "Cannot read workflow output files; the workspace was retained."
        ) from exc
    db.add_all([WorkflowArtifact(run_id=run.id, **entry) for entry in entries])


async def owned_run(db: AsyncSession, user_id: str, run_id: str) -> WorkflowRun:
    result = await db.execute(
        select(WorkflowRun).where(WorkflowRun.id == run_id, WorkflowRun.user_id == user_id)
    )
    run = result.scalar_one_or_none()
    if run is None:
        raise WorkflowError("Workflow not found.")
    return run


def require_outputs(run: WorkflowRun) -> None:
    if run.artifacts_status != "ready":
        raise WorkflowError(
            run.artifacts_error
            or (
                "Historical output files were not preserved."
                if run.artifacts_status == "unavailable"
                else "Workflow output files are not available yet."
            )
        )


async def list_outputs(db: AsyncSession, run: WorkflowRun, offset: int, limit: int) -> dict:
    require_outputs(run)
    result = await db.execute(
        select(WorkflowArtifact)
        .where(WorkflowArtifact.run_id == run.id)
        .order_by(WorkflowArtifact.path)
        .offset(offset)
        .limit(limit + 1)
    )
    rows = list(result.scalars())
    return {
        "run_id": run.id,
        "status": run.status,
        "artifacts_status": run.artifacts_status,
        "files": [
            {
                "id": r.id,
                "path": r.path,
                "media_type": r.media_type,
                "size_bytes": r.size_bytes,
                "sha256": r.sha256,
            }
            for r in rows[:limit]
        ],
        "next_offset": offset + limit if len(rows) > limit else None,
    }


async def get_output(db: AsyncSession, run: WorkflowRun, path: str) -> WorkflowArtifact:
    require_outputs(run)
    canonical_path(path)
    result = await db.execute(
        select(WorkflowArtifact)
        .options(undefer(WorkflowArtifact.data))
        .where(WorkflowArtifact.run_id == run.id, WorkflowArtifact.path == path)
    )
    row = result.scalar_one_or_none()
    if row is None:
        raise WorkflowError("Output file not found.")
    return row


def extract_output(path: str, data: bytes) -> str:
    """Strict extraction: unsupported/corrupt/oversized content is an error, never text."""
    suffix = Path(path).suffix.lower()
    if suffix in {".xlsx", ".ods", ".docx", ".pptx", ".epub"}:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            if (
                len(archive.infolist()) > MAX_TREE_ENTRIES
                or sum(entry.file_size for entry in archive.infolist()) > MAX_TOTAL_BYTES
            ):
                raise WorkflowError(
                    "Document exceeds the expanded extraction limits; download it instead."
                )
    if suffix in _STRUCTURED_EXTENSIONS and suffix != ".csv":
        text = extract_text(data, path, "")
    elif suffix in _MARKITDOWN_EXTENSIONS:
        text = _strict_markdown(path, data)
    else:
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise WorkflowError(
                "This file has no supported text representation; download it instead."
            ) from exc
        if suffix not in TEXT_EXTENSIONS and text and not _looks_like_text(text):
            raise WorkflowError(
                "This file has no supported text representation; download it instead."
            )
    if len(text) > MAX_TEXT_CHARS:
        raise WorkflowError("Extracted document exceeds the text limit; download it instead.")
    return text


def _strict_markdown(path: str, data: bytes) -> str:
    # The legacy client helper suppresses conversion errors; workflow reads must propagate them.
    with tempfile.NamedTemporaryFile(suffix=Path(path).suffix) as tmp:
        tmp.write(data)
        tmp.flush()
        return MarkItDown().convert(tmp.name).text_content


def text_page(text: str, offset: int, limit: int) -> dict:
    end = min(offset + limit, len(text))
    return {
        "content": text[offset:end],
        "offset": offset,
        "total_chars": len(text),
        "has_more": end < len(text),
        "next_offset": end if end < len(text) else None,
    }


class OutputArgs(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    action: Literal["list_runs", "read_report", "list_files", "read_file"]
    run_id: str | None = None
    conversation_id: str | None = None
    path: str | None = None
    offset: int = Field(default=0, ge=0)
    limit: int | None = Field(default=None, ge=1, le=MAX_PAGE_CHARS)


async def _execute_workflow_outputs(*, args: dict, db: AsyncSession, user_id: str) -> dict:
    request = OutputArgs.model_validate(args)
    listing = request.action in {"list_runs", "list_files"}
    limit = request.limit or (20 if listing else MAX_PAGE_CHARS)
    if listing and limit > 50:
        raise WorkflowError("List pages are limited to 50 entries.")
    if request.action == "list_runs":
        query = select(WorkflowRun).where(WorkflowRun.user_id == user_id)
        if request.conversation_id:
            query = query.where(WorkflowRun.conversation_id == request.conversation_id)
        result = await db.execute(
            query.order_by(WorkflowRun.created_at.desc(), WorkflowRun.id.desc())
            .offset(request.offset)
            .limit(limit + 1)
        )
        rows = list(result.scalars())
        return {
            "ok": True,
            "runs": [
                {
                    "run_id": r.id,
                    "status": r.status,
                    "instruction": r.instruction[:200],
                    "conversation_id": r.conversation_id,
                    "session_epoch": r.session_epoch,
                    "artifacts_status": r.artifacts_status,
                    "artifacts_error": r.artifacts_error,
                }
                for r in rows[:limit]
            ],
            "next_offset": request.offset + limit if len(rows) > limit else None,
        }
    if not request.run_id:
        raise WorkflowError("run_id is required; use list_runs to find it.")
    run = await owned_run(db, user_id, request.run_id)
    if run.status not in TERMINAL_STATUSES:
        raise WorkflowError("This workflow is still running.")
    if request.action == "list_files":
        return {"ok": True, **await list_outputs(db, run, request.offset, limit)}
    if request.action == "read_report":
        if run.summary is None:
            raise WorkflowError(run.error or "This workflow has no report.")
        return {
            "ok": True,
            "run_id": run.id,
            "status": run.status,
            **text_page(run.summary, request.offset, limit),
        }
    if not request.path:
        raise WorkflowError("path is required; use list_files to find it.")
    artifact = await get_output(db, run, request.path)
    try:
        text = await asyncio.to_thread(extract_isolated, artifact.path, artifact.data)
    except Exception as exc:
        raise WorkflowError(f"Cannot extract {artifact.path!r}: {exc}") from exc
    return {
        "ok": True,
        "run_id": run.id,
        "status": run.status,
        "path": artifact.path,
        "representation": "extracted_text",
        **text_page(text, request.offset, limit),
    }


WORKFLOW_OUTPUTS_DESCRIPTOR = {
    "type": "function",
    "function": {
        "name": "workflow_outputs",
        "description": (
            "Read preserved delegated agent outputs. list_runs finds your runs (optionally "
            "filtered by conversation_id); read_report reads the complete report in pages; "
            "list_files lists generated files; read_file reads full extracted file text in pages. "
            "Use next_offset until null. Failed/cancelled run output is partial. Binary files "
            "without text remain downloadable. Never ask users to paste already preserved outputs."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": ["list_runs", "read_report", "list_files", "read_file"],
                },
                "run_id": {"type": "string"},
                "conversation_id": {"type": "string"},
                "path": {"type": "string"},
                "offset": {"type": "integer", "minimum": 0},
                "limit": {"type": "integer", "minimum": 1, "maximum": MAX_PAGE_CHARS},
            },
            "required": ["action"],
            "additionalProperties": False,
        },
    },
}

WORKFLOW_OUTPUTS_NUDGE = (
    "Use workflow_outputs for follow-up questions about delegated agent reports or generated "
    "files. Use the run ID in its completion message, or list_runs to find it. Read the relevant "
    "report/files before answering; follow next_offset for more content. Historical files that "
    "were deleted before output preservation are explicitly unavailable."
)


def extract_isolated(path: str, data: bytes) -> str:
    """Document parsers run with memory/CPU/time limits outside the API process."""
    suffix = Path(path).suffix.lower()
    if suffix not in _STRUCTURED_EXTENSIONS | _MARKITDOWN_EXTENSIONS or suffix == ".csv":
        return extract_output(path, data)
    try:
        proc = subprocess.run(  # noqa: S603
            [sys.executable, "-m", "app.services.workflow_extract_worker", path],
            input=data,
            capture_output=True,
            timeout=20,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise WorkflowError("Document extraction timed out; download it instead.") from exc
    if proc.returncode != 0:
        raise WorkflowError(
            "Document extraction failed or exceeded resource limits; download it instead."
        )
    result = json.loads(proc.stdout)
    if not result["ok"]:
        raise WorkflowError(result["error"])
    return result["text"]


async def execute_workflow_outputs(*, args: dict, db: AsyncSession, user_id: str) -> dict:
    """Fit JSON pages inside the actual model tool-result budget without losing cursors."""
    result = await _execute_workflow_outputs(args=args, db=db, user_id=user_id)
    budget = get_settings().tool_result_max_chars
    if budget <= 0:
        return result
    while len(json.dumps(result, default=str)) > budget:
        if "content" in result and result["content"]:
            result["content"] = result["content"][: len(result["content"]) // 2]
            result["next_offset"] = result["offset"] + len(result["content"])
            result["has_more"] = result["next_offset"] < result["total_chars"]
        elif (key := "files" if "files" in result else "runs") in result and len(result[key]) > 1:
            result[key] = result[key][: len(result[key]) // 2]
            result["next_offset"] = args.get("offset", 0) + len(result[key])
        else:
            raise WorkflowError("Tool result budget is too small for an output page.")
    return result
