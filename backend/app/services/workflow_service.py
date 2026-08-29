"""Persistence + snapshot handling for delegated opencode workflows (idea 18).

A run's lifecycle:

1. :meth:`create` — row in ``draft``, plus an empty server-side temp directory.
2. :meth:`add_files` — the desktop client uploads its folder in batches; every
   path is forced back inside the temp directory before anything is written.
3. :meth:`start_snapshot` — ``git init`` + a baseline commit, so whatever
   opencode does afterwards is recoverable as an exact diff.
4. (the runner executes) — :meth:`append_progress` / :meth:`finish`.
5. :meth:`compute_changes` — ``git diff`` against the baseline, returned to the
   client with the *pre-run* hash of each file so it can refuse to clobber a
   file it edited locally in the meantime.

The backend only ever handles uploaded bytes and its own temp directory — it
never opens a path the client named on the client's machine (idea 17's rule).
"""

from __future__ import annotations

import asyncio
import base64
import binascii
import hashlib
import logging
import shutil
import subprocess
import tempfile
import unicodedata
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conversation import Conversation
from app.models.message import Message
from app.models.workflow_run import WorkflowRun
from app.schemas.workflow import (
    MAX_FILE_BYTES,
    MAX_FILE_COUNT,
    MAX_TOTAL_BYTES,
    WorkflowChange,
)

logger = logging.getLogger(__name__)

# Prefix for the per-run temp directories, so a leaked one is identifiable.
_WORKDIR_PREFIX = "garbanzo-workflow-"

# Conversation attachments are copied into this reserved directory before the
# detached runner starts. It is excluded from git diffs: these are input copies,
# not files from the user's attached folder that should be written back.
WORKFLOW_INPUT_DIR = ".garbanzo-workflow-inputs"

# Identity for the baseline commit — never pushed anywhere, but git refuses to
# commit without one.
_GIT_ENV_ARGS = (
    "-c",
    "user.name=Garbanzo",
    "-c",
    "user.email=workflow@garbanzo.local",
    "-c",
    "commit.gpgsign=false",
)

# Coalesce streaming text into the previous progress entry instead of appending
# a row per token, and hard-cap the list so a runaway run can't bloat the JSONB.
_MAX_PROGRESS_ENTRIES = 2000
_COALESCING_TYPES = frozenset({"chunk", "thinking"})

# Never offered back to the user: opencode's own state plus the dependency and
# build trees a run can create (bash is allowed, so `npm install` is fair game
# — without this the diff would carry thousands of node_modules files into the
# user's real folder). ``opencode.json`` is added at runtime, and only when we
# were the ones who wrote it — a project with its own stays diffable.
_TOOL_RESIDUE = [
    f"{WORKFLOW_INPUT_DIR}/",
    ".opencode/",
    "node_modules/",
    "__pycache__/",
    ".venv/",
    "venv/",
    ".pytest_cache/",
    ".ruff_cache/",
    ".mypy_cache/",
]


class WorkflowError(RuntimeError):
    """A workflow operation failed with a user-facing message."""


def safe_join(root: Path, rel_path: str) -> Path:
    """Resolve ``rel_path`` inside ``root``, refusing anything that escapes.

    The client supplies these paths, so this is a trust boundary: absolute
    paths, ``..`` traversal, and symlink escapes must all be rejected before we
    write a single byte.
    """
    if not rel_path or rel_path.startswith("/") or "\x00" in rel_path:
        raise WorkflowError(f"Unsafe path: {rel_path!r}")
    root_res = root.resolve()
    candidate = (root_res / rel_path).resolve()
    if candidate != root_res and root_res not in candidate.parents:
        raise WorkflowError(f"Path escapes the workflow folder: {rel_path!r}")
    return candidate


def _run_git(workdir: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(  # noqa: S603
        ["git", *_GIT_ENV_ARGS, *args],
        cwd=str(workdir),
        capture_output=True,
        check=check,
    )


class WorkflowService:
    """DB + snapshot operations for workflow runs."""

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    # -- CRUD ---------------------------------------------------------------

    async def create(
        self,
        *,
        user_id: str,
        instruction: str,
        conversation_id: str | None = None,
        room_id: str | None = None,
        tool_call_id: str | None = None,
        folder_label: str | None = None,
        mode: str = "folder",
        mcp_tools: list[str] | None = None,
        attached_files: list[tuple[str, bytes]] | None = None,
    ) -> WorkflowRun:
        """Create a ``draft`` run and its isolated server-side snapshot dir."""
        workdir = await asyncio.to_thread(tempfile.mkdtemp, prefix=_WORKDIR_PREFIX)
        attachment_paths = await asyncio.to_thread(
            _write_workflow_inputs,
            Path(workdir),
            attached_files or [],
        )
        run = WorkflowRun(
            id=str(uuid.uuid4()),
            user_id=user_id,
            instruction=instruction,
            conversation_id=conversation_id,
            room_id=room_id,
            tool_call_id=tool_call_id,
            status="draft",
            workdir=workdir,
            progress=[],
            scope={
                "mode": mode,
                "folder_label": folder_label,
                "file_count": 0,
                "total_bytes": 0,
                "attachment_paths": attachment_paths,
                "attachment_count": len(attached_files or []),
                "attachment_bytes": sum(len(data) for _, data in (attached_files or [])),
                "permissions": ["edit", "bash", "webfetch"],
                # None means every enabled MCP visible to this user; a list is
                # the conversation's explicit tool whitelist (native entries
                # are removed before it reaches here).
                "mcp_tools": mcp_tools,
            },
        )
        self.db.add(run)
        await self.db.commit()
        await self.db.refresh(run)
        return run

    async def conversation_attachments(
        self,
        conversation_id: str,
        user_id: str,
        tool_call_id: str | None = None,
    ) -> list[tuple[str, bytes]]:
        """Return exact files from the user message that launched a workflow.

        Ownership is checked before message metadata is inspected. When the
        proposal tool call can be located, its immediately preceding user
        message is used; otherwise the latest user message is a compatibility
        fallback for older proposals and direct API callers.
        """
        result = await self.db.execute(
            select(Conversation.id).where(
                Conversation.id == conversation_id,
                Conversation.user_id == user_id,
                Conversation.is_deleted.is_(False),
            )
        )
        if result.scalar_one_or_none() is None:
            raise WorkflowError("Conversation not found.")

        anchor_seq: int | None = None
        if tool_call_id:
            result = await self.db.execute(
                select(Message)
                .where(
                    Message.conversation_id == conversation_id,
                    Message.role == "tool_call",
                )
                .order_by(Message.seq.desc())
            )
            for message in result.scalars():
                calls = (message.meta or {}).get("tool_calls") or []
                if any(call.get("id") == tool_call_id for call in calls):
                    anchor_seq = message.seq
                    break

        query = select(Message).where(
            Message.conversation_id == conversation_id,
            Message.role == "user",
        )
        if anchor_seq is not None:
            query = query.where(Message.seq < anchor_seq)
        result = await self.db.execute(query.order_by(Message.seq.desc()).limit(1))
        source = result.scalar_one_or_none()
        if source is None:
            return []

        files: list[tuple[str, bytes]] = []
        total = 0
        for entry in (source.meta or {}).get("attachments") or []:
            name = entry.get("name") or "attachment"
            data = entry.get("data")
            if not isinstance(data, str) or not data:
                raise WorkflowError(
                    f"Attached file {name!r} is not available to delegate. "
                    "Attach it again with the current app version."
                )
            try:
                raw = base64.b64decode(data, validate=True)
            except (binascii.Error, ValueError) as exc:
                raise WorkflowError(f"Attached file {name!r} has an invalid payload.") from exc
            if len(raw) > MAX_FILE_BYTES:
                raise WorkflowError(
                    f"Attached file {name!r} is larger than the "
                    f"{MAX_FILE_BYTES // (1024 * 1024)} MB workflow limit."
                )
            total += len(raw)
            if len(files) >= MAX_FILE_COUNT or total > MAX_TOTAL_BYTES:
                raise WorkflowError("Conversation attachments exceed the workflow input limits.")
            files.append((str(name), raw))
        return files

    async def conversation_mcp_tools(
        self,
        conversation_id: str,
        user_id: str,
    ) -> list[str] | None:
        """Return the MCP allowance for a user-owned conversation.

        ``None`` preserves the conversation contract of "all enabled tools";
        an explicit list keeps only MCP keys because detached opencode does
        not execute Garbanzo's in-process native tools.
        """
        result = await self.db.execute(
            select(Conversation).where(
                Conversation.id == conversation_id,
                Conversation.user_id == user_id,
                Conversation.is_deleted.is_(False),
            )
        )
        conversation = result.scalar_one_or_none()
        if conversation is None:
            raise WorkflowError("Conversation not found.")
        enabled = conversation.enabled_tools
        if enabled is None:
            return None
        return [key for key in enabled if not key.startswith("__garbo__:")]

    async def get(self, run_id: str, user_id: str) -> WorkflowRun | None:
        """Fetch a run owned by ``user_id`` (None if missing or not theirs)."""
        result = await self.db.execute(
            select(WorkflowRun).where(
                WorkflowRun.id == run_id,
                WorkflowRun.user_id == user_id,
            )
        )
        return result.scalar_one_or_none()

    async def list_for_conversation(self, user_id: str, conversation_id: str) -> list[WorkflowRun]:
        result = await self.db.execute(
            select(WorkflowRun)
            .where(
                WorkflowRun.user_id == user_id,
                WorkflowRun.conversation_id == conversation_id,
            )
            .order_by(WorkflowRun.created_at.desc())
        )
        return list(result.scalars().all())

    # -- snapshot upload ----------------------------------------------------

    async def add_files(
        self,
        run: WorkflowRun,
        files: list[tuple[str, str]],
    ) -> tuple[int, int]:
        """Write a batch of ``(path, base64)`` files into the run's snapshot.

        Returns the running ``(file_count, total_bytes)``. Raises
        :class:`WorkflowError` on an unsafe path or a budget overrun.
        """
        if run.status not in ("draft", "uploading"):
            raise WorkflowError("This workflow has already started.")
        if (run.scope or {}).get("mode", "folder") != "folder":
            raise WorkflowError("Research workflows do not accept folder uploads.")
        if not run.workdir:
            raise WorkflowError("This workflow has no snapshot directory.")
        root = Path(run.workdir)
        scope = dict(run.scope or {})
        count = int(scope.get("file_count", 0))
        total = int(scope.get("total_bytes", 0))

        decoded: list[tuple[Path, bytes]] = []
        for rel_path, b64 in files:
            target = safe_join(root, rel_path)
            input_root = (root / WORKFLOW_INPUT_DIR).resolve()
            if target == input_root or input_root in target.parents:
                raise WorkflowError(f"{WORKFLOW_INPUT_DIR} is reserved for message attachments.")
            try:
                data = base64.b64decode(b64, validate=True)
            except (binascii.Error, ValueError) as exc:
                raise WorkflowError(f"Invalid base64 for {rel_path!r}") from exc
            if len(data) > MAX_FILE_BYTES:
                raise WorkflowError(f"{rel_path} is larger than the {MAX_FILE_BYTES} byte limit.")
            count += 1
            total += len(data)
            if count + int(scope.get("attachment_count", 0)) > MAX_FILE_COUNT:
                raise WorkflowError(f"Folder has more than {MAX_FILE_COUNT} files.")
            if total + int(scope.get("attachment_bytes", 0)) > MAX_TOTAL_BYTES:
                raise WorkflowError(f"Folder is larger than {MAX_TOTAL_BYTES // (1024 * 1024)} MB.")
            decoded.append((target, data))

        await asyncio.to_thread(_write_files, decoded)

        scope.update(file_count=count, total_bytes=total)
        run.scope = scope
        run.status = "uploading"
        await self.db.commit()
        return count, total

    async def start_snapshot(self, run: WorkflowRun) -> None:
        """Git-init the snapshot and commit the baseline, then mark ``queued``.

        The baseline commit is what makes change detection exact: everything
        opencode does afterwards shows up in ``git diff``, and the original
        bytes stay retrievable for the client's conflict check.
        """
        if run.status not in ("draft", "uploading"):
            raise WorkflowError("This workflow has already started.")
        if not run.workdir:
            raise WorkflowError("This workflow has no snapshot directory.")
        await asyncio.to_thread(_git_baseline, Path(run.workdir))
        run.status = "queued"
        await self.db.commit()
        # commit() expires the instance; callers serialize it straight after.
        await self.db.refresh(run)

    # -- progress + completion ---------------------------------------------

    async def append_progress(self, run_id: str, entries: list[dict[str, Any]]) -> None:
        """Append translated opencode chunks, coalescing streamed text."""
        if not entries:
            return
        run = await self.db.get(WorkflowRun, run_id)
        if run is None:
            return
        progress = list(run.progress or [])
        for entry in entries:
            last = progress[-1] if progress else None
            if (
                last is not None
                and entry.get("type") in _COALESCING_TYPES
                and last.get("type") == entry.get("type")
            ):
                last["content"] = (last.get("content") or "") + (entry.get("content") or "")
                continue
            if len(progress) >= _MAX_PROGRESS_ENTRIES:
                break
            progress.append(entry)
        run.progress = progress
        if run.status == "queued":
            run.status = "running"
        await self.db.commit()

    async def set_session(self, run_id: str, session_id: str) -> None:
        await self.db.execute(
            update(WorkflowRun)
            .where(WorkflowRun.id == run_id)
            .values(opencode_session_id=session_id, status="running")
        )
        await self.db.commit()

    async def finish(
        self,
        run_id: str,
        *,
        status: str,
        summary: str | None = None,
        error: str | None = None,
    ) -> None:
        await self.db.execute(
            update(WorkflowRun)
            .where(WorkflowRun.id == run_id)
            .values(
                status=status,
                summary=summary,
                error=error,
                completed_at=datetime.now(UTC),
            )
        )
        await self.db.commit()

    async def sweep_stale(self) -> int:
        """Fail runs left mid-flight by a backend restart.

        Their opencode subprocess died with the old process, so a ``running``
        row can never progress — without this a client polls it forever.
        """
        result = await self.db.execute(
            update(WorkflowRun)
            .where(WorkflowRun.status.in_(("queued", "running")))
            .values(
                status="error",
                error="The server restarted while this workflow was running.",
                completed_at=datetime.now(UTC),
            )
        )
        await self.db.commit()
        return result.rowcount or 0

    # -- diff ---------------------------------------------------------------

    async def compute_changes(self, run: WorkflowRun) -> list[WorkflowChange]:
        """Diff the snapshot against its baseline commit."""
        if (run.scope or {}).get("mode", "folder") != "folder":
            raise WorkflowError("Research workflows do not have file changes.")
        if not run.workdir:
            return []
        return await asyncio.to_thread(_collect_changes, Path(run.workdir))

    async def cleanup(self, run: WorkflowRun) -> None:
        """Delete the server-side snapshot once the client has the diff."""
        if run.workdir:
            await asyncio.to_thread(shutil.rmtree, run.workdir, True)
            run.workdir = None
            await self.db.commit()


# ---------------------------------------------------------------------------
# Blocking helpers (always called via asyncio.to_thread)
# ---------------------------------------------------------------------------


def _write_files(decoded: list[tuple[Path, bytes]]) -> None:
    for path, data in decoded:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def _write_workflow_inputs(root: Path, files: list[tuple[str, bytes]]) -> list[str]:
    """Write collision-safe attachment copies and return their relative paths."""
    if not files:
        return []
    input_root = root / WORKFLOW_INPUT_DIR
    used: set[str] = set()
    paths: list[str] = []
    for original_name, data in files:
        filename = _safe_attachment_filename(original_name, used)
        target = safe_join(input_root, filename)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        rel = target.relative_to(root).as_posix()
        paths.append(rel)
    return paths


def _safe_attachment_filename(original_name: str, used: set[str]) -> str:
    """Preserve Unicode names while removing paths and resolving collisions."""
    leaf = original_name.replace("\\", "/").rsplit("/", 1)[-1]
    leaf = unicodedata.normalize("NFC", leaf).strip()
    leaf = "".join(char for char in leaf if unicodedata.category(char) != "Cc")
    if leaf in ("", ".", ".."):
        leaf = "attachment"
    leaf = _truncate_utf8(leaf, 220)

    stem = Path(leaf).stem or "attachment"
    suffix = Path(leaf).suffix
    candidate = leaf
    index = 2
    while candidate.casefold() in used:
        marker = f" ({index})"
        candidate = f"{_truncate_utf8(stem, 220 - len(marker.encode()) - len(suffix.encode()))}{marker}{suffix}"
        index += 1
    used.add(candidate.casefold())
    return candidate


def _truncate_utf8(value: str, max_bytes: int) -> str:
    encoded = value.encode("utf-8")
    if len(encoded) <= max_bytes:
        return value
    return encoded[:max_bytes].decode("utf-8", "ignore") or "attachment"


def absorb_into_baseline(workdir: Path, paths: list[str]) -> None:
    """Commit ``paths`` on top of the baseline so they never reach the diff.

    :func:`exclude_from_diff` only hides *untracked* files — tool residue that
    has to live inside a file the baseline already tracks (e.g. a permission
    envelope injected into a project's own ``opencode.json``) must instead be
    committed, so the diff the client auto-applies starts from the patched
    content rather than offering the patch back to the user.
    """
    if not (workdir / ".git").exists():
        return
    _run_git(workdir, "add", *paths, check=False)
    _run_git(workdir, "commit", "--quiet", "-m", "tool residue", check=False)


def exclude_from_diff(workdir: Path, patterns: list[str]) -> None:
    """Add ``patterns`` to the snapshot's ``.git/info/exclude``.

    Uses ``.git/info/exclude`` rather than a ``.gitignore``: the latter would
    itself be a new file in the working tree and get offered back to the user
    as a change. Everything listed here is agent/tool residue that must never
    be written into the user's real folder.
    """
    info = workdir / ".git" / "info"
    if not info.parent.exists():
        return
    info.mkdir(parents=True, exist_ok=True)
    with (info / "exclude").open("a", encoding="utf-8") as fh:
        fh.write("\n" + "\n".join(patterns) + "\n")


def _git_baseline(workdir: Path) -> None:
    _run_git(workdir, "init", "--quiet")
    exclude_from_diff(workdir, _TOOL_RESIDUE)
    _run_git(workdir, "add", "-A")
    # An empty snapshot has nothing to commit; allow it so the run can still
    # create files from scratch.
    _run_git(workdir, "commit", "--quiet", "--allow-empty", "-m", "baseline", check=False)


def _collect_changes(workdir: Path) -> list[WorkflowChange]:
    """Return the added/modified/deleted files relative to the baseline."""
    if not (workdir / ".git").exists():
        return []
    _run_git(workdir, "add", "-A", check=False)
    proc = _run_git(
        workdir,
        "diff",
        "--cached",
        "--name-status",
        "--no-renames",
        "-z",
        "HEAD",
        check=False,
    )
    # -z output is NUL-separated: status, path, status, path, ...
    parts = [p for p in proc.stdout.decode("utf-8", "replace").split("\0") if p]
    changes: list[WorkflowChange] = []
    for i in range(0, len(parts) - 1, 2):
        code, rel = parts[i][:1], parts[i + 1]
        status = {"A": "added", "M": "modified", "D": "deleted"}.get(code)
        if status is None:
            continue
        base_sha = None
        if status in ("modified", "deleted"):
            base = _run_git(workdir, "show", f"HEAD:{rel}", check=False)
            if base.returncode == 0:
                base_sha = hashlib.sha256(base.stdout).hexdigest()
        data = None
        size = 0
        if status != "deleted":
            target = workdir / rel
            try:
                content = target.read_bytes()
            except OSError:
                continue
            size = len(content)
            # Oversized results are reported without content: the client shows
            # them as skipped rather than writing a truncated file.
            if size <= MAX_FILE_BYTES:
                data = base64.b64encode(content).decode("ascii")
        changes.append(
            WorkflowChange(
                path=rel,
                status=status,  # type: ignore[arg-type]
                data=data,
                base_sha256=base_sha,
                size=size,
            )
        )
    return changes
