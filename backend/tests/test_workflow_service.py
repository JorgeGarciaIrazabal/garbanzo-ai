"""Tests for WorkflowService (idea 18): snapshot upload, baseline, diff.

The snapshot directory is a trust boundary — the client names every path — so
the escape guard and the upload budgets get direct coverage, as does the
git-diff change detection that write-back depends on.
"""

import base64
import hashlib
import io
import uuid
import zipfile
from pathlib import Path

import pytest

from app.models.message import Message
from app.schemas.workflow import MAX_FILE_BYTES, MAX_FILE_COUNT
from app.services.workflow_service import (
    WORKFLOW_INPUT_DIR,
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


@pytest.mark.asyncio
async def test_research_run_rejects_folder_upload_and_diff(db_session):
    service, run = await _new_run(db_session, mode="research", mcp_tools=[])
    assert run.scope["mode"] == "research"
    with pytest.raises(WorkflowError, match="do not accept folder uploads"):
        await service.add_files(run, [("notes.md", _b64("nope"))])

    await service.start_snapshot(run)
    assert (Path(run.workdir) / ".git").exists()
    with pytest.raises(WorkflowError, match="do not have file changes"):
        await service.compute_changes(run)


@pytest.mark.asyncio
async def test_launching_message_attachments_are_copied_with_unicode_names(
    db_session,
    test_conversation,
):
    pdf = b"%PDF exact bytes\x00\xff"
    user_message = Message(
        id=str(uuid.uuid4()),
        conversation_id=test_conversation.id,
        role="user",
        content="Revisa el contrato",
        seq=100,
        meta={
            "attachments": [
                {
                    "name": "CONTRATO DE INTERMEDIACION ISLAS HÉBRIDAS 70.pdf",
                    "mime_type": "application/pdf",
                    "type": "document",
                    "encoding": "base64",
                    "data": base64.b64encode(pdf).decode("ascii"),
                }
            ]
        },
    )
    tool_message = Message(
        id=str(uuid.uuid4()),
        conversation_id=test_conversation.id,
        role="tool_call",
        content="[]",
        seq=200,
        meta={"tool_calls": [{"id": "delegate-1", "name": "delegate_workflow"}]},
    )
    db_session.add_all([user_message, tool_message])
    await db_session.commit()

    service = WorkflowService(db_session)
    files = await service.conversation_attachments(
        test_conversation.id,
        OWNER,
        "delegate-1",
    )
    run = await service.create(
        user_id=OWNER,
        instruction="analyze it",
        mode="research",
        attached_files=files,
    )

    rel_path = run.scope["attachment_paths"][0]
    assert rel_path == (f"{WORKFLOW_INPUT_DIR}/CONTRATO DE INTERMEDIACION ISLAS HÉBRIDAS 70.pdf")
    assert (Path(run.workdir) / rel_path).read_bytes() == pdf
    await service.start_snapshot(run)
    assert _collect_changes(Path(run.workdir)) == []


@pytest.mark.asyncio
async def test_workflow_attachment_names_drop_paths_and_resolve_unicode_collisions(db_session):
    service = WorkflowService(db_session)
    run = await service.create(
        user_id=OWNER,
        instruction="analyze",
        attached_files=[
            ("../../señor.pdf", b"one"),
            ("SEÑOR.pdf", b"two"),
        ],
    )

    assert run.scope["attachment_paths"] == [
        f"{WORKFLOW_INPUT_DIR}/señor.pdf",
        f"{WORKFLOW_INPUT_DIR}/SEÑOR (2).pdf",
    ]
    assert not (Path(run.workdir).parent / "señor.pdf").exists()


@pytest.mark.asyncio
async def test_folder_upload_cannot_overwrite_reserved_message_attachments(db_session):
    service, run = await _new_run(db_session)
    with pytest.raises(WorkflowError, match="reserved"):
        await service.add_files(
            run,
            [(f"{WORKFLOW_INPUT_DIR}/contract.pdf", _b64("overwrite"))],
        )

    with pytest.raises(WorkflowError, match="reserved"):
        await service.add_files(
            run,
            [(f"safe/../{WORKFLOW_INPUT_DIR}/contract.pdf", _b64("overwrite"))],
        )


@pytest.mark.asyncio
async def test_legacy_attachment_without_bytes_requires_reattach(db_session, test_conversation):
    db_session.add(
        Message(
            id=str(uuid.uuid4()),
            conversation_id=test_conversation.id,
            role="user",
            content="old message",
            meta={"attachments": [{"name": "old.pdf", "type": "document"}]},
        )
    )
    await db_session.commit()

    service = WorkflowService(db_session)
    with pytest.raises(WorkflowError, match="Attach it again"):
        await service.conversation_attachments(test_conversation.id, OWNER)


@pytest.mark.asyncio
async def test_conversation_attachments_reject_other_users(db_session, test_conversation):
    service = WorkflowService(db_session)
    with pytest.raises(WorkflowError, match="Conversation not found"):
        await service.conversation_attachments(
            test_conversation.id,
            "someone-else@example.com",
        )


@pytest.mark.asyncio
async def test_conversation_attachment_enforces_per_file_limit(
    db_session,
    test_conversation,
    monkeypatch,
):
    monkeypatch.setattr("app.services.workflow_service.MAX_FILE_BYTES", 2)
    db_session.add(
        Message(
            id=str(uuid.uuid4()),
            conversation_id=test_conversation.id,
            role="user",
            content="oversized",
            meta={
                "attachments": [
                    {
                        "name": "large.pdf",
                        "data": base64.b64encode(b"123").decode("ascii"),
                    }
                ]
            },
        )
    )
    await db_session.commit()

    service = WorkflowService(db_session)
    with pytest.raises(WorkflowError, match="workflow limit"):
        await service.conversation_attachments(test_conversation.id, OWNER)


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


def test_collect_changes_handles_binary_files_byte_exactly(tmp_path):
    """Spreadsheets, decks, and images must survive the diff untouched.

    Detection uses ``--name-status`` (never a textual patch) and content is
    carried as base64, so binary formats are safe — this pins that down.
    """

    def make_xlsx(path, note):
        with zipfile.ZipFile(path, "w") as z:
            z.writestr("[Content_Types].xml", "<Types/>")
            z.writestr("xl/sharedStrings.xml", note)

    make_xlsx(tmp_path / "book.xlsx", "before")
    (tmp_path / "logo.png").write_bytes(bytes([0x89, 0x50, 0x4E, 0x47, 0, 1, 255, 254]))
    _git_baseline(tmp_path)
    original = (tmp_path / "book.xlsx").read_bytes()

    make_xlsx(tmp_path / "book.xlsx", "after")
    make_xlsx(tmp_path / "deck.pptx", "slides")

    changes = {c.path: c for c in _collect_changes(tmp_path)}
    assert set(changes) == {"book.xlsx", "deck.pptx"}  # untouched png not reported

    edited = changes["book.xlsx"]
    assert edited.status == "modified"
    assert edited.base_sha256 == hashlib.sha256(original).hexdigest()
    # Byte-exact, and still a readable office file after the round trip.
    round_tripped = base64.b64decode(edited.data)
    assert round_tripped == (tmp_path / "book.xlsx").read_bytes()
    assert zipfile.is_zipfile(io.BytesIO(round_tripped))


def test_collect_changes_omits_content_for_oversized_files(tmp_path):
    _git_baseline(tmp_path)
    (tmp_path / "huge.pptx").write_bytes(b"x" * (MAX_FILE_BYTES + 1))

    change = next(c for c in _collect_changes(tmp_path) if c.path == "huge.pptx")
    # Reported so the user knows it exists, but without content — the client
    # shows it as skipped rather than writing a truncated file.
    assert change.data is None
    assert change.size > MAX_FILE_BYTES


def test_collect_changes_excludes_tool_residue(tmp_path):
    """A run that installs dependencies must not ship them back to the user."""
    (tmp_path / "main.py").write_text("print('hi')")
    _git_baseline(tmp_path)

    (tmp_path / ".opencode").mkdir()
    (tmp_path / ".opencode/state.json").write_text("{}")
    (tmp_path / "node_modules/left-pad").mkdir(parents=True)
    (tmp_path / "node_modules/left-pad/index.js").write_text("noise")
    (tmp_path / "__pycache__").mkdir()
    (tmp_path / "__pycache__/main.pyc").write_bytes(b"\x00")
    (tmp_path / "main.py").write_text("print('bye')")

    assert [c.path for c in _collect_changes(tmp_path)] == ["main.py"]


def test_seeded_opencode_config_is_not_offered_to_the_user(tmp_path):
    from app.core.config import get_settings
    from app.services.workflow_runner import seed_opencode_config

    (tmp_path / "main.py").write_text("x = 1")
    _git_baseline(tmp_path)
    seed_opencode_config(tmp_path, get_settings())

    assert (tmp_path / "opencode.json").exists()  # opencode still sees it
    assert _collect_changes(tmp_path) == []  # but the user never does


def test_a_projects_own_opencode_config_stays_diffable(tmp_path):
    from app.core.config import get_settings
    from app.services.workflow_runner import seed_opencode_config

    (tmp_path / "opencode.json").write_text('{"model": "theirs"}')
    _git_baseline(tmp_path)
    seed_opencode_config(tmp_path, get_settings())  # must not overwrite it
    assert '"theirs"' in (tmp_path / "opencode.json").read_text()

    (tmp_path / "opencode.json").write_text('{"model": "edited-by-agent"}')
    assert [c.path for c in _collect_changes(tmp_path)] == ["opencode.json"]


def test_a_permissionless_project_config_gets_the_allow_envelope(tmp_path):
    """A detached run has nobody to answer permission prompts — a project
    config without a ``permission`` block would stall opencode until the time
    budget kills the run. The envelope is injected, but committed onto the
    baseline so it never reaches the user's folder through the diff."""
    import json

    from app.core.config import get_settings
    from app.services.opencode_config import DEFAULT_PERMISSION
    from app.services.workflow_runner import seed_opencode_config

    (tmp_path / "opencode.json").write_text('{"model": "theirs"}')
    _git_baseline(tmp_path)
    seed_opencode_config(tmp_path, get_settings())

    config = json.loads((tmp_path / "opencode.json").read_text())
    assert config["model"] == "theirs"  # everything else is kept
    assert config["permission"] == DEFAULT_PERMISSION
    assert _collect_changes(tmp_path) == []  # the injection is not a "change"


def test_a_project_config_with_its_own_permissions_is_respected(tmp_path):
    from app.core.config import get_settings
    from app.services.workflow_runner import seed_opencode_config

    (tmp_path / "opencode.json").write_text('{"permission": {"edit": "deny"}}')
    _git_baseline(tmp_path)
    seed_opencode_config(tmp_path, get_settings())

    assert '"deny"' in (tmp_path / "opencode.json").read_text()
    assert _collect_changes(tmp_path) == []


def test_a_non_json_project_config_is_left_alone(tmp_path):
    from app.core.config import get_settings
    from app.services.workflow_runner import seed_opencode_config

    jsonc = '{\n  // comment makes this JSONC\n  "model": "theirs"\n}'
    (tmp_path / "opencode.json").write_text(jsonc)
    _git_baseline(tmp_path)
    seed_opencode_config(tmp_path, get_settings())

    assert (tmp_path / "opencode.json").read_text() == jsonc


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
