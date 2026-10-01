"""Regressions for lost delegated output, paging, owner checks and capture bounds."""

import asyncio
import base64
import io
import json
import os
import zipfile
from pathlib import Path
from unittest.mock import AsyncMock, patch

import pytest
from openpyxl import Workbook
from pypdf.errors import PdfReadError
from sqlalchemy import select, update

from app.db import session as db_session_module
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.workflow_run import WorkflowRun
from app.schemas.chat import ChatResponseChunk
from app.services import workflow_outputs, workflow_runner
from app.services.chat_context import ChatContextBuilder
from app.services.chat_service import ChatService
from app.services.llm_provider import ChatChunk
from app.services.native_tools import execute_native_tool
from app.services.workflow_outputs import (
    canonical_path,
    capture_outputs,
    collect_artifacts,
    extract_output,
    get_output,
)
from app.services.workflow_service import WorkflowError, WorkflowService, _run_git
from app.topics.models import MessageTopic, Topic
from tests.test_chat_tool_loop import _make_service, _ScriptedProvider
from tests.test_workflow_endpoints import (
    _clear_overrides,
    _client,
    _install_overrides,
    _UserSwitch,
)
from tests.test_workflow_runner import _FakeProc, _stub_opencode
from tests.test_workflow_runner import captured_push as _captured_push

captured_push = _captured_push

OWNER = "test@example.com"
REPORT = "España 🌱\nThe isotope measurement was 731.42.\n" * 800


def _write_outputs(root: str):
    path = Path(root)
    (path / "hallazgos España.md").write_text(REPORT, encoding="utf-8")
    (path / "raw.bin").write_bytes(b"\xff\x00\xfe")


async def _finished(db, conversation_id=None, mode="research"):
    service = WorkflowService(db)
    run = await service.create(
        user_id=OWNER, instruction="research", mode=mode, conversation_id=conversation_id
    )
    await service.start_snapshot(run)
    await asyncio.to_thread(_write_outputs, run.workdir)
    await capture_outputs(db, run)
    await service.finish(run.id, status="done", summary=REPORT, artifacts_status="ready")
    await service.cleanup(run)
    await db.refresh(run)
    return run


async def _tool(db, **args):
    return await execute_native_tool(name="workflow_outputs", args=args, db=db, user_id=OWNER)


@pytest.mark.asyncio
async def test_complete_report_and_file_reconstruct_after_cleanup(db_session):
    run = await _finished(db_session)
    run_id = run.id
    db_session.expire_all()
    await db_session.refresh(run)
    for action, kwargs in [("read_report", {}), ("read_file", {"path": "hallazgos España.md"})]:
        pages = []
        offset = 0
        while True:
            result = await _tool(
                db_session, action=action, run_id=run.id, offset=offset, limit=3501, **kwargs
            )
            assert result["ok"], result
            pages.append(result["content"])
            if result["next_offset"] is None:
                break
            offset = result["next_offset"]
        assert "".join(pages) == REPORT
    listing = await _tool(db_session, action="list_files", run_id=run.id, limit=1)
    assert len(listing["files"]) == 1 and listing["next_offset"] == 1
    tail = await _tool(db_session, action="list_files", run_id=run.id, limit=1, offset=1)
    assert tail["next_offset"] is None
    assert (await _tool(db_session, action="read_file", run_id=run.id, path="raw.bin"))[
        "ok"
    ] is False
    run_id = run.id
    assert (
        await execute_native_tool(
            name="workflow_outputs",
            args={"action": "read_report", "run_id": run_id},
            db=db_session,
            user_id="another@example.com",
        )
    )["ok"] is False


@pytest.mark.asyncio
async def test_legacy_runs_have_reports_but_explicitly_unavailable_files(db_session):
    run = WorkflowRun(
        id="legacy", user_id=OWNER, instruction="old", status="done", summary="old report"
    )
    db_session.add(run)
    await db_session.commit()
    assert (await _tool(db_session, action="read_report", run_id="legacy"))[
        "content"
    ] == "old report"
    result = await _tool(db_session, action="list_files", run_id="legacy")
    assert not result["ok"] and "Historical" in result["error"]


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "args",
    [
        {"action": "read_report", "offset": -1},
        {"action": "list_runs", "limit": 51},
        {"action": "list_runs", "limit": True},
        {"action": "read_report", "limit": 12001},
        {"action": "read_report"},
        {"action": "list_runs", "user_id": "forged"},
    ],
)
async def test_invalid_tool_arguments_are_explicit(db_session, args):
    assert not (await _tool(db_session, **args))["ok"]


@pytest.mark.parametrize("path", ["/etc/passwd", "../secret", "a/../../x", "a/./b", "a\\b", ""])
def test_output_paths_are_canonical(path):
    with pytest.raises(WorkflowError):
        canonical_path(path)


def test_capture_refuses_symlinks_and_special_files(tmp_path):
    outside = tmp_path.parent / "outside-secret"
    outside.write_text("private")
    (tmp_path / "leak.txt").symlink_to(outside)
    with pytest.raises(WorkflowError, match="regular file"):
        collect_artifacts(tmp_path, "research", None)
    (tmp_path / "leak.txt").unlink()
    (tmp_path / "leak-dir").symlink_to(tmp_path.parent, target_is_directory=True)
    with pytest.raises(WorkflowError, match="symlinks"):
        collect_artifacts(tmp_path, "research", None)
    (tmp_path / "leak-dir").unlink()
    os.mkfifo(tmp_path / "pipe")
    with pytest.raises(WorkflowError, match="regular file"):
        collect_artifacts(tmp_path, "research", None)


@pytest.mark.parametrize(
    "bound", ["MAX_FILE_BYTES", "MAX_TOTAL_BYTES", "MAX_FILE_COUNT", "MAX_TREE_ENTRIES"]
)
def test_capture_limits_are_explicit(tmp_path, monkeypatch, bound):
    (tmp_path / "one.md").write_bytes(b"123456")
    (tmp_path / "two.md").write_bytes(b"123456")
    monkeypatch.setattr(workflow_outputs, bound, 1 if bound.endswith(("COUNT", "ENTRIES")) else 7)
    if bound == "MAX_FILE_BYTES":
        monkeypatch.setattr(workflow_outputs, bound, 5)
    with pytest.raises(WorkflowError, match="limit"):
        collect_artifacts(tmp_path, "research", None)


def test_corrupt_supported_document_is_not_returned_as_report():
    with pytest.raises(PdfReadError):
        extract_output("broken.pdf", b"not a pdf")
    with pytest.raises(WorkflowError, match="no supported text"):
        extract_output("image.png", b"\x89PNG\x00\xff")


def test_compressed_document_limits_are_explicit(monkeypatch):
    data = io.BytesIO()
    with zipfile.ZipFile(data, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("large.xml", "a" * 1000)
    monkeypatch.setattr(workflow_outputs, "MAX_TOTAL_BYTES", 100)
    with pytest.raises(WorkflowError, match="expanded extraction"):
        extract_output("report.docx", data.getvalue())


@pytest.mark.asyncio
async def test_folder_changes_and_artifacts_survive_applied(db_session):
    service = WorkflowService(db_session)
    run = await service.create(user_id=OWNER, instruction="edit")
    await service.add_files(run, [("doc.md", base64.b64encode(b"original").decode())])
    await service.start_snapshot(run)
    await asyncio.to_thread((Path(run.workdir) / "doc.md").write_text, "changed")
    await capture_outputs(db_session, run)
    await service.finish(run.id, status="done", artifacts_status="ready")
    changes = await service.compute_changes(run)
    assert changes[0].base_sha256 and base64.b64decode(changes[0].data) == b"changed"
    await service.cleanup(run)
    assert (await get_output(db_session, run, "doc.md")).data == b"changed"


@pytest.mark.asyncio
async def test_runner_preserves_files_before_cleanup(db_session, monkeypatch, captured_push):
    service = WorkflowService(db_session)
    run = await service.create(user_id=OWNER, instruction="research", mode="research", mcp_tools=[])
    await service.start_snapshot(run)
    await asyncio.to_thread(_write_outputs, run.workdir)
    _stub_opencode(
        monkeypatch,
        [
            ChatResponseChunk(type="chunk", content="Complete report."),
            ChatResponseChunk(type="done", metadata={}),
        ],
    )
    await workflow_runner._run(run.id)
    await db_session.refresh(run)
    assert run.status == "done" and run.artifacts_status == "ready" and run.workdir is None
    assert (await get_output(db_session, run, "hallazgos España.md")).data.decode() == REPORT


@pytest.mark.asyncio
@pytest.mark.parametrize("failure", ["capture", "commit"])
async def test_failed_preservation_retains_files_and_report(
    db_session, monkeypatch, captured_push, failure
):
    service = WorkflowService(db_session)
    run = await service.create(user_id=OWNER, instruction="research", mode="research", mcp_tools=[])
    await service.start_snapshot(run)
    await asyncio.to_thread(_write_outputs, run.workdir)
    _stub_opencode(
        monkeypatch,
        [
            ChatResponseChunk(type="chunk", content="valuable report"),
            ChatResponseChunk(type="done", metadata={}),
        ],
    )
    if failure == "capture":
        monkeypatch.setattr(
            workflow_runner, "capture_outputs", AsyncMock(side_effect=OSError("cannot read"))
        )
    else:
        real_finish = WorkflowService.finish
        calls = 0

        async def failed_once(self, *args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 1:
                raise RuntimeError("database persistence failed")
            return await real_finish(self, *args, **kwargs)

        monkeypatch.setattr(WorkflowService, "finish", failed_once)
    run_id = run.id
    await workflow_runner._run(run_id)
    await db_session.refresh(run)
    assert run.status == "error" and run.artifacts_status == "error"
    assert run.summary == "valuable report" and run.workdir
    assert (await list_outputs_if_error(db_session, run))["ok"] is False
    assert await asyncio.to_thread(Path(run.workdir).exists)


async def list_outputs_if_error(db, run):
    return await _tool(db, action="list_files", run_id=run.id)


@pytest.mark.asyncio
async def test_completion_uses_originating_epoch_and_provider_gets_report(
    db_session,
    test_conversation,
    monkeypatch,
    captured_push,
):
    test_conversation.is_primary = True
    test_conversation.session_epoch = 4
    await db_session.commit()
    run = await _finished(db_session, test_conversation.id)
    await workflow_runner._report_completion(
        db=db_session,
        user_id=OWNER,
        run_id=run.id,
        conversation_id=test_conversation.id,
        instruction="research",
        summary="Final isotope report",
        status="done",
        error=None,
        session_epoch=run.session_epoch,
    )
    message = (
        (
            await db_session.execute(
                select(Message).where(
                    Message.conversation_id == test_conversation.id, Message.role == "assistant"
                )
            )
        )
        .scalars()
        .one()
    )
    assert message.session_epoch == 4 and run.id in message.content
    history = ChatContextBuilder(None, None, None).build_message_history([message])
    assert run.id in history[0].content
    calls = [
        {
            "id": "read-result",
            "name": "workflow_outputs",
            "arguments": {
                "action": "read_file",
                "run_id": run.id,
                "path": "hallazgos España.md",
                "limit": 3000,
            },
        }
    ]
    provider = _ScriptedProvider(
        [
            [
                ChatChunk(content="", is_finished=False, tool_calls=calls),
                ChatChunk(content="", is_finished=True),
            ],
            [ChatChunk(content="The isotope is 731.42.", is_finished=True)],
        ]
    )
    service = await _make_service(db_session, provider)
    with patch(
        "app.services.chat_service.MCPService.list_all_tools", new=AsyncMock(return_value=[])
    ):
        async for _ in service.send_message(
            conversation_id=test_conversation.id,
            user_id=OWNER,
            content="What measurement did the agent find?",
        ):
            pass
    assert any(
        "731.42" in (m.content or "") for m in provider.calls[1]["messages"] if m.role == "tool"
    )
    assert any(d["function"]["name"] == "workflow_outputs" for d in provider.calls[0]["tools"])
    assert any(
        run.id in (m.content or "") for m in provider.calls[0]["messages"] if m.role == "assistant"
    )
    test_conversation.enabled_tools = []
    await db_session.commit()
    tools, lookup = await ChatService(db_session)._resolve_tools_for_conversation(test_conversation)
    assert "workflow_outputs" not in lookup


@pytest.mark.asyncio
async def test_topic_switch_does_not_move_completion_into_new_epoch(
    db_session, test_conversation, captured_push
):
    test_conversation.session_epoch = 8
    await db_session.commit()
    run = await _finished(db_session, test_conversation.id)
    test_conversation.session_epoch = 9
    await db_session.commit()
    await workflow_runner._report_completion(
        db=db_session,
        user_id=OWNER,
        run_id=run.id,
        conversation_id=test_conversation.id,
        instruction="research",
        summary="old topic findings",
        status="done",
        error=None,
        session_epoch=run.session_epoch,
    )
    message = (
        (
            await db_session.execute(
                select(Message).where(Message.meta.is_not(None), Message.role == "assistant")
            )
        )
        .scalars()
        .one()
    )
    assert message.session_epoch == 8
    runs = await _tool(db_session, action="list_runs")
    assert runs["runs"][0]["run_id"] == run.id  # explicitly retrievable by owner after topic switch


@pytest.mark.asyncio
async def test_output_endpoints_download_exact_bytes_and_enforce_owner(db_session):
    run = await _finished(db_session)
    switch = _UserSwitch()
    _install_overrides(db_session, switch)
    try:
        async with _client() as client:
            url = f"/api/v1/workflows/{run.id}/outputs"
            listing = await client.get(url)
            assert listing.status_code == 200 and len(listing.json()["files"]) == 2
            raw = await client.get(url + "/file", params={"path": "raw.bin"})
            assert raw.status_code == 200 and raw.content == b"\xff\x00\xfe"
            assert raw.headers["cache-control"] == "private, no-store"
            assert raw.headers["content-disposition"].startswith("attachment;")
            assert (
                await client.get(url + "/file", params={"path": "../secret"})
            ).status_code == 400
            assert (await client.get(url + "/file", params={"path": "missing"})).status_code == 404
            switch.email = "other@example.com"
            assert (await client.get(url)).status_code == 404
            assert (await client.get(url + "/file", params={"path": "raw.bin"})).status_code == 404
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_cancel_stops_body_and_child_before_capturing(db_session, monkeypatch, captured_push):
    service = WorkflowService(db_session)
    run = await service.create(user_id=OWNER, instruction="research", mode="research", mcp_tools=[])
    await service.start_snapshot(run)
    active = asyncio.Event()
    stopped = asyncio.Event()
    terminated = []
    proc = _FakeProc()
    monkeypatch.setattr(
        workflow_runner, "_start_opencode", lambda workdir, settings: (proc, "http://fake")
    )

    async def stream(self, endpoint, instruction, session_id=None):
        active.set()
        try:
            await asyncio.Event().wait()
            yield ChatResponseChunk(type="done")
        finally:
            stopped.set()

    monkeypatch.setattr(workflow_runner.MicroappAgent, "stream_instruction", stream)
    monkeypatch.setattr(workflow_runner, "terminate", lambda child: terminated.append(child))

    async def capture(db, row):
        assert stopped.is_set() and terminated == [proc]
        await capture_outputs(db, row)

    monkeypatch.setattr(workflow_runner, "capture_outputs", capture)
    task = asyncio.create_task(workflow_runner._run(run.id))
    await asyncio.wait_for(active.wait(), 5)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    await db_session.refresh(run)
    assert run.status == "cancelled" and run.artifacts_status == "ready" and run.workdir is None


@pytest.mark.asyncio
async def test_agent_git_commits_do_not_hide_archived_outputs(db_session):
    service = WorkflowService(db_session)
    run = await service.create(user_id=OWNER, instruction="edit")
    await service.add_files(run, [("doc.md", base64.b64encode(b"original").decode())])
    await service.start_snapshot(run)
    await asyncio.to_thread((Path(run.workdir) / "doc.md").write_text, "committed output")
    await asyncio.to_thread(_run_git, Path(run.workdir), "add", "-A")
    await asyncio.to_thread(_run_git, Path(run.workdir), "commit", "-m", "agent commit")
    await capture_outputs(db_session, run)
    await service.finish(run.id, status="done", artifacts_status="ready")
    assert (await get_output(db_session, run, "doc.md")).data == b"committed output"


@pytest.mark.asyncio
async def test_completion_ingestion_remains_in_original_topic(
    db_session, test_conversation, captured_push
):
    old = Topic(id="old-output-topic", user_id=OWNER, label="Research", normalized_label="research")
    new = Topic(id="new-output-topic", user_id=OWNER, label="Travel", normalized_label="travel")
    db_session.add_all([old, new])
    await db_session.flush()
    test_conversation.is_primary = True
    test_conversation.session_epoch = 5
    test_conversation.active_topic_id = old.id
    await db_session.commit()
    run = await _finished(db_session, test_conversation.id)
    test_conversation.session_epoch = 6
    test_conversation.active_topic_id = new.id
    test_conversation.topic_is_pinned = True
    await db_session.commit()
    await workflow_runner._report_completion(
        db=db_session,
        user_id=OWNER,
        run_id=run.id,
        conversation_id=test_conversation.id,
        instruction="research",
        summary="isotope findings",
        status="done",
        error=None,
        session_epoch=run.session_epoch,
    )
    membership = (await db_session.execute(select(MessageTopic))).scalars().one()
    assert membership.topic_id == old.id
    assert test_conversation.active_topic_id == new.id


def _spreadsheet():
    workbook = Workbook()
    workbook.active.append(["Country", "Measurement"])
    workbook.active.append(["España", "731.42"])
    data = io.BytesIO()
    workbook.save(data)
    workbook.close()
    return data.getvalue()


@pytest.mark.asyncio
async def test_read_spreadsheet_uses_full_strict_isolated_extraction(db_session):
    service = WorkflowService(db_session)
    run = await service.create(user_id=OWNER, instruction="spreadsheet", mode="research")
    await service.start_snapshot(run)
    payload = _spreadsheet()
    await asyncio.to_thread((Path(run.workdir) / "measurements.xlsx").write_bytes, payload)
    await capture_outputs(db_session, run)
    await service.finish(run.id, status="done", artifacts_status="ready")
    await service.cleanup(run)
    result = await _tool(db_session, action="read_file", run_id=run.id, path="measurements.xlsx")
    assert result["ok"], result
    assert "España" in result["content"] and "731.42" in result["content"]


@pytest.mark.asyncio
async def test_pages_fit_provider_budget_without_losing_unicode_or_cursor(db_session, monkeypatch):
    run = await _finished(db_session)
    settings = workflow_outputs.get_settings().model_copy(update={"tool_result_max_chars": 2000})
    monkeypatch.setattr(workflow_outputs, "get_settings", lambda: settings)
    result = await _tool(db_session, action="read_report", run_id=run.id)
    assert result["ok"] and len(json.dumps(result, default=str)) <= 2000
    assert result["has_more"] and result["next_offset"] == len(result["content"])
    assert result["content"] == REPORT[: result["next_offset"]]


@pytest.mark.asyncio
async def test_repeated_cancel_during_finalization_cannot_lose_outputs(
    db_session,
    monkeypatch,
    captured_push,
):
    service = WorkflowService(db_session)
    run = await service.create(user_id=OWNER, instruction="research", mode="research", mcp_tools=[])
    await service.start_snapshot(run)
    await asyncio.to_thread(_write_outputs, run.workdir)
    _stub_opencode(
        monkeypatch,
        [
            ChatResponseChunk(type="chunk", content="finished report"),
            ChatResponseChunk(type="done", metadata={}),
        ],
    )
    saving = asyncio.Event()
    release = asyncio.Event()

    async def slow_capture(db, row):
        saving.set()
        await release.wait()
        await capture_outputs(db, row)

    monkeypatch.setattr(workflow_runner, "capture_outputs", slow_capture)
    task = asyncio.create_task(workflow_runner._run(run.id))
    await asyncio.wait_for(saving.wait(), 5)
    task.cancel()
    await asyncio.sleep(0)
    task.cancel()
    await asyncio.sleep(0)
    assert not task.done()
    release.set()
    with pytest.raises(asyncio.CancelledError):
        await task
    await db_session.refresh(run)
    assert run.status == "done" and run.artifacts_status == "ready" and run.workdir is None
    assert run.summary == "finished report"
    assert (await get_output(db_session, run, "raw.bin")).data == b"\xff\x00\xfe"


@pytest.mark.asyncio
async def test_restart_and_pending_preservation_cannot_be_applied(db_session):
    service = WorkflowService(db_session)
    run = await service.create(user_id=OWNER, instruction="edit")
    await service.start_snapshot(run)
    await asyncio.to_thread(_write_outputs, run.workdir)
    run_id = run.id
    _install_overrides(db_session, _UserSwitch())
    try:
        async with _client() as client:
            # Even a terminal row must not authorize cleanup while capture is pending.
            run.status = "error"
            await db_session.commit()
            assert (await client.post(f"/api/v1/workflows/{run_id}/applied")).status_code == 409
            run.status = "running"
            await db_session.commit()
            assert await service.sweep_stale() == 1
            await db_session.refresh(run)
            assert run.artifacts_status == "error" and "restart" in run.artifacts_error
            assert (await client.post(f"/api/v1/workflows/{run_id}/applied")).status_code == 409
            assert await asyncio.to_thread(Path(run.workdir).exists)
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_tool_picker_catalog_includes_output_reader(db_session):
    _install_overrides(db_session, _UserSwitch())
    try:
        with patch(
            "app.api.v1.endpoints.mcp.MCPService.list_all_tools", new=AsyncMock(return_value=[])
        ):
            async with _client() as client:
                response = await client.get("/api/v1/mcp/tools")
        assert response.status_code == 200
        descriptor = next(tool for tool in response.json() if tool["name"] == "workflow_outputs")
        assert descriptor["server_id"] == "__garbo__"
        assert "read_file" in descriptor["input_schema"]["properties"]["action"]["enum"]
    finally:
        _clear_overrides()


@pytest.mark.asyncio
async def test_old_completion_does_not_seed_fresh_empty_topic(
    db_session, test_conversation, captured_push
):
    old = Topic(
        id="archived-output-topic", user_id=OWNER, label="Research", normalized_label="research"
    )
    db_session.add(old)
    await db_session.flush()
    test_conversation.is_primary = True
    test_conversation.active_topic_id = old.id
    test_conversation.session_epoch = 11
    await db_session.commit()
    run = await _finished(db_session, test_conversation.id)
    async with db_session_module.async_session_maker() as switching_db:
        await switching_db.execute(
            update(Conversation)
            .where(Conversation.id == test_conversation.id)
            .values(session_epoch=12, active_topic_id=None)
        )
        await switching_db.commit()
    assert test_conversation.session_epoch == 11  # stale long-lived identity map
    await workflow_runner._report_completion(
        db=db_session,
        user_id=OWNER,
        run_id=run.id,
        conversation_id=test_conversation.id,
        instruction="research",
        summary="old output",
        status="done",
        error=None,
        session_epoch=run.session_epoch,
    )
    await db_session.refresh(test_conversation)
    assert test_conversation.active_topic_id is None
    assert (await db_session.execute(select(MessageTopic))).scalars().one().topic_id == old.id
