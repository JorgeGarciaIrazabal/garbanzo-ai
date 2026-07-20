"""Tests for WorkflowService (idea 18): snapshot upload, baseline, diff.

The snapshot directory is a trust boundary — the client names every path — so
the escape guard and the upload budgets get direct coverage, as does the
git-diff change detection that write-back depends on.
"""

import base64
import hashlib
from pathlib import Path

import pytest

from app.schemas.workflow import MAX_FILE_BYTES, MAX_FILE_COUNT
from app.services.workflow_service import (
    WorkflowError,
    WorkflowService,
    _collect_changes,
    _git_baseline,
    safe_join,
)

OWNER = "test@example.com"


def _b64(text: str) -> str:
    return base64.b64encode(text.encode()).decode()


def _exists(path) -> bool:
    """Module-level so async tests don't trip ruff's ASYNC240 (blocking IO)."""
    return Path(path).exists()


async def _new_run(db_session, **kwargs):
    """A draft run owned by the conftest-seeded test user."""
    service = WorkflowService(db_session)
    run = await service.create(user_id=OWNER, instruction="do the thing", **kwargs)
    return service, run


# ---------------------------------------------------------------------------
# safe_join — the escape guard
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "rel",
    [
        "../outside.txt",
        "a/../../outside.txt",
        "/etc/passwd",
        "",
    ],
)
def test_safe_join_rejects_escapes(tmp_path, rel):
    with pytest.raises(WorkflowError):
        safe_join(tmp_path, rel)


def test_safe_join_allows_nested_paths(tmp_path):
    resolved = safe_join(tmp_path, "src/app/main.py")
    assert resolved == (tmp_path / "src/app/main.py").resolve()


def test_safe_join_rejects_symlink_escape(tmp_path):
    outside = tmp_path.parent / "outside_dir"
    outside.mkdir(exist_ok=True)
    root = tmp_path / "root"
    root.mkdir()
    (root / "link").symlink_to(outside, target_is_directory=True)
    with pytest.raises(WorkflowError):
        safe_join(root, "link/secret.txt")


# ---------------------------------------------------------------------------
# upload
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_add_files_writes_snapshot_and_tracks_totals(db_session):
    service, run = await _new_run(db_session)
    count, total = await service.add_files(
        run,
        [("a.txt", _b64("hello")), ("nested/b.txt", _b64("world!"))],
    )
    assert (count, total) == (2, 11)
    assert (Path(run.workdir) / "a.txt").read_text() == "hello"
    assert (Path(run.workdir) / "nested/b.txt").read_text() == "world!"
    assert run.status == "uploading"
    assert run.scope["file_count"] == 2


@pytest.mark.asyncio
async def test_add_files_rejects_escaping_path(db_session):
    service, run = await _new_run(db_session)
    with pytest.raises(WorkflowError):
        await service.add_files(run, [("../evil.txt", _b64("nope"))])
    assert not (Path(run.workdir).parent / "evil.txt").exists()


@pytest.mark.asyncio
async def test_add_files_rejects_oversized_file(db_session):
    service, run = await _new_run(db_session)
    payload = base64.b64encode(b"x" * (MAX_FILE_BYTES + 1)).decode()
    with pytest.raises(WorkflowError, match="larger than"):
        await service.add_files(run, [("big.bin", payload)])


@pytest.mark.asyncio
async def test_add_files_rejects_too_many_files(db_session):
    service, run = await _new_run(db_session)
    run.scope = {**run.scope, "file_count": MAX_FILE_COUNT}
    with pytest.raises(WorkflowError, match="more than"):
        await service.add_files(run, [("one-too-many.txt", _b64("x"))])


@pytest.mark.asyncio
async def test_add_files_rejects_invalid_base64(db_session):
    service, run = await _new_run(db_session)
    with pytest.raises(WorkflowError, match="base64"):
        await service.add_files(run, [("a.txt", "not base64!!")])


@pytest.mark.asyncio
async def test_add_files_refused_after_start(db_session):
    service, run = await _new_run(db_session)
    await service.add_files(run, [("a.txt", _b64("hi"))])
    await service.start_snapshot(run)
    with pytest.raises(WorkflowError, match="already started"):
        await service.add_files(run, [("b.txt", _b64("late"))])


# ---------------------------------------------------------------------------
# baseline + diff
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_start_snapshot_marks_queued_and_creates_git(db_session):
    service, run = await _new_run(db_session)
    await service.add_files(run, [("a.txt", _b64("hi"))])
    await service.start_snapshot(run)
    assert run.status == "queued"
    assert (Path(run.workdir) / ".git").exists()


def test_collect_changes_detects_add_modify_delete(tmp_path):
    (tmp_path / "keep.txt").write_text("unchanged")
    (tmp_path / "edit.txt").write_text("before")
    (tmp_path / "gone.txt").write_text("bye")
    _git_baseline(tmp_path)

    # What "opencode" did:
    (tmp_path / "new.txt").write_text("brand new")
    (tmp_path / "edit.txt").write_text("after")
    (tmp_path / "gone.txt").unlink()

    changes = {c.path: c for c in _collect_changes(tmp_path)}
    assert set(changes) == {"new.txt", "edit.txt", "gone.txt"}
    assert changes["new.txt"].status == "added"
    assert base64.b64decode(changes["new.txt"].data) == b"brand new"
    # An added file has no baseline content to conflict against.
    assert changes["new.txt"].base_sha256 is None

    assert changes["edit.txt"].status == "modified"
    assert base64.b64decode(changes["edit.txt"].data) == b"after"
    assert changes["edit.txt"].base_sha256 == hashlib.sha256(b"before").hexdigest()

    assert changes["gone.txt"].status == "deleted"
    assert changes["gone.txt"].data is None
    assert changes["gone.txt"].base_sha256 == hashlib.sha256(b"bye").hexdigest()


def test_collect_changes_empty_when_nothing_touched(tmp_path):
    (tmp_path / "a.txt").write_text("same")
    _git_baseline(tmp_path)
    assert _collect_changes(tmp_path) == []


def test_collect_changes_without_git_returns_empty(tmp_path):
    assert _collect_changes(tmp_path / "missing") == []


@pytest.mark.asyncio
async def test_compute_changes_round_trip(db_session):
    service, run = await _new_run(db_session)
    await service.add_files(run, [("doc.md", _b64("v1"))])
    await service.start_snapshot(run)
    (Path(run.workdir) / "doc.md").write_text("v2")

    changes = await service.compute_changes(run)
    assert [c.path for c in changes] == ["doc.md"]
    assert base64.b64decode(changes[0].data) == b"v2"
    assert changes[0].base_sha256 == hashlib.sha256(b"v1").hexdigest()


# ---------------------------------------------------------------------------
# progress, completion, cleanup
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_append_progress_coalesces_streamed_text(db_session):
    service, run = await _new_run(db_session)
    await service.start_snapshot(run)
    await service.append_progress(
        run.id,
        [
            {"type": "chunk", "content": "Hel"},
            {"type": "chunk", "content": "lo"},
            {"type": "tool_call", "content": ""},
            {"type": "chunk", "content": "!"},
        ],
    )
    await db_session.refresh(run)
    assert [e["type"] for e in run.progress] == ["chunk", "tool_call", "chunk"]
    assert run.progress[0]["content"] == "Hello"
    # A queued run flips to running as soon as the agent speaks.
    assert run.status == "running"


@pytest.mark.asyncio
async def test_finish_records_summary_and_completion(db_session):
    service, run = await _new_run(db_session)
    await service.finish(run.id, status="done", summary="all set")
    await db_session.refresh(run)
    assert (run.status, run.summary) == ("done", "all set")
    assert run.completed_at is not None


@pytest.mark.asyncio
async def test_sweep_stale_fails_orphaned_runs(db_session):
    service, run = await _new_run(db_session)
    run.status = "running"
    await db_session.commit()

    assert await service.sweep_stale() == 1
    await db_session.refresh(run)
    assert run.status == "error"
    assert "restarted" in run.error


@pytest.mark.asyncio
async def test_cleanup_removes_the_snapshot(db_session):
    service, run = await _new_run(db_session)
    await service.add_files(run, [("a.txt", _b64("hi"))])
    workdir = run.workdir
    await service.cleanup(run)
    assert run.workdir is None
    assert not _exists(workdir)


@pytest.mark.asyncio
async def test_get_is_scoped_to_the_owner(db_session):
    service, run = await _new_run(db_session)
    assert await service.get(run.id, OWNER) is not None
    assert await service.get(run.id, "someone-else@example.com") is None
