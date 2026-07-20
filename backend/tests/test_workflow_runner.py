"""Tests for the detached opencode workflow runner (idea 18).

opencode is never spawned: ``_start_opencode`` and the agent's event stream are
both stubbed, so these cover the parts that actually carry risk — progress
relay, summary capture, failure handling, and reporting the result back into
the conversation.
"""

import asyncio

import pytest

from app.models.message import Message
from app.models.workflow_run import WorkflowRun
from app.schemas.chat import ChatResponseChunk
from app.services import workflow_runner
from app.services.workflow_service import WorkflowService

OWNER = "test@example.com"


class _FakeProc:
    """Looks alive enough for terminate() to leave it alone."""

    pid = 1234

    def poll(self):
        return 0


def _stub_opencode(monkeypatch, chunks: list[ChatResponseChunk]):
    """Make the runner think opencode started and streamed ``chunks``."""
    monkeypatch.setattr(
        workflow_runner,
        "_start_opencode",
        lambda workdir, settings: (_FakeProc(), "http://127.0.0.1:0"),
    )

    async def _stream(self, endpoint, instruction, session_id=None):
        for chunk in chunks:
            yield chunk

    monkeypatch.setattr(workflow_runner.MicroappAgent, "stream_instruction", _stream)


@pytest.fixture()
def captured_push(monkeypatch):
    """Capture FCM sends instead of touching firebase."""
    sent: list[dict] = []

    async def _send(db, user_id, **kwargs):
        sent.append({"user_id": user_id, **kwargs})
        return 1

    from app.services import fcm_service

    monkeypatch.setattr(fcm_service, "send_to_user", _send)
    return sent


async def _queued_run(db_session, conversation_id=None) -> WorkflowRun:
    service = WorkflowService(db_session)
    run = await service.create(
        user_id=OWNER,
        instruction="tidy the code",
        conversation_id=conversation_id,
    )
    await service.start_snapshot(run)
    return run


@pytest.mark.asyncio
async def test_run_records_progress_and_summary(db_session, monkeypatch, captured_push):
    run = await _queued_run(db_session)
    _stub_opencode(
        monkeypatch,
        [
            ChatResponseChunk(type="session", metadata={"session_id": "sess-1"}),
            ChatResponseChunk(type="chunk", content="Renamed "),
            ChatResponseChunk(type="chunk", content="the parser."),
            ChatResponseChunk(type="done", metadata={}),
        ],
    )

    await workflow_runner._run(run.id)

    await db_session.refresh(run)
    assert run.status == "done"
    assert run.summary == "Renamed the parser."
    assert run.opencode_session_id == "sess-1"
    assert run.completed_at is not None
    # The streamed text is coalesced into a single replayable entry.
    assert [e["type"] for e in run.progress] == ["chunk"]


@pytest.mark.asyncio
async def test_run_marks_error_when_the_agent_fails(db_session, monkeypatch, captured_push):
    run = await _queued_run(db_session)
    _stub_opencode(
        monkeypatch,
        [
            ChatResponseChunk(type="chunk", content="starting"),
            ChatResponseChunk(type="error", error="model exploded"),
        ],
    )

    await workflow_runner._run(run.id)

    await db_session.refresh(run)
    assert run.status == "error"
    assert "model exploded" in run.error


@pytest.mark.asyncio
async def test_run_errors_when_opencode_never_starts(db_session, monkeypatch, captured_push):
    run = await _queued_run(db_session)
    monkeypatch.setattr(
        workflow_runner,
        "_start_opencode",
        lambda workdir, settings: (None, "http://127.0.0.1:0"),
    )

    await workflow_runner._run(run.id)

    await db_session.refresh(run)
    assert run.status == "error"
    assert "opencode" in run.error


@pytest.mark.asyncio
async def test_run_times_out(db_session, monkeypatch, captured_push):
    run = await _queued_run(db_session)
    monkeypatch.setattr(workflow_runner, "MAX_RUN_SECONDS", 0.05)
    monkeypatch.setattr(
        workflow_runner,
        "_start_opencode",
        lambda workdir, settings: (_FakeProc(), "http://127.0.0.1:0"),
    )

    async def _slow(self, endpoint, instruction, session_id=None):
        await asyncio.sleep(5)
        yield ChatResponseChunk(type="done", metadata={})

    monkeypatch.setattr(workflow_runner.MicroappAgent, "stream_instruction", _slow)

    await workflow_runner._run(run.id)

    await db_session.refresh(run)
    assert run.status == "error"
    assert "time budget" in run.error


@pytest.mark.asyncio
async def test_completion_posts_summary_and_push(
    db_session, monkeypatch, captured_push, test_conversation
):
    run = await _queued_run(db_session, conversation_id=test_conversation.id)
    _stub_opencode(
        monkeypatch,
        [
            ChatResponseChunk(type="chunk", content="All done."),
            ChatResponseChunk(type="done", metadata={}),
        ],
    )

    await workflow_runner._run(run.id)

    from sqlalchemy import select

    messages = (
        (
            await db_session.execute(
                select(Message).where(Message.conversation_id == test_conversation.id)
            )
        )
        .scalars()
        .all()
    )
    assert len(messages) == 1
    assert messages[0].role == "assistant"
    assert "All done." in messages[0].content
    assert messages[0].meta["workflow_run_id"] == run.id

    assert len(captured_push) == 1
    assert captured_push[0]["data"]["workflow_run_id"] == run.id
    assert captured_push[0]["data"]["conversation_id"] == test_conversation.id


@pytest.mark.asyncio
async def test_no_push_when_the_user_is_watching(
    db_session, monkeypatch, captured_push, test_conversation
):
    """A push while the app is open is noise — the progress line already
    showed the result and the conversation reloaded."""
    from app.services import workflow_watchers

    run = await _queued_run(db_session, conversation_id=test_conversation.id)
    _stub_opencode(
        monkeypatch,
        [
            ChatResponseChunk(type="chunk", content="All done."),
            ChatResponseChunk(type="done", metadata={}),
        ],
    )
    # The desktop app polls ~every 1.5s while a run is live.
    workflow_watchers.mark_watching(run.id)

    await workflow_runner._run(run.id)

    assert captured_push == []
    # The summary still lands in the conversation — only the push is skipped.
    from sqlalchemy import select

    messages = (
        (
            await db_session.execute(
                select(Message).where(Message.conversation_id == test_conversation.id)
            )
        )
        .scalars()
        .all()
    )
    assert len(messages) == 1
    assert "All done." in messages[0].content
    # The watcher entry is released so the map can't grow unbounded.
    assert not workflow_watchers.is_watched(run.id)


@pytest.mark.asyncio
async def test_push_sent_when_the_poll_is_stale(
    db_session, monkeypatch, captured_push, test_conversation
):
    """App closed mid-run: polling stopped, so the user does need telling."""
    from app.services import workflow_watchers

    run = await _queued_run(db_session, conversation_id=test_conversation.id)
    _stub_opencode(monkeypatch, [ChatResponseChunk(type="done", metadata={})])
    workflow_watchers.mark_watching(run.id)
    # Simulate the app having gone away well before the run finished.
    monkeypatch.setattr(workflow_watchers, "WATCHING_WINDOW_SECONDS", -1.0)

    await workflow_runner._run(run.id)

    assert len(captured_push) == 1
    assert captured_push[0]["data"]["workflow_run_id"] == run.id


@pytest.mark.asyncio
async def test_run_that_vanished_is_a_no_op(db_session, monkeypatch, captured_push):
    # No exception, no push — the row is simply gone.
    await workflow_runner._run("does-not-exist")
    assert captured_push == []


@pytest.mark.asyncio
async def test_launch_tracks_and_clears_the_task(db_session, monkeypatch, captured_push):
    run = await _queued_run(db_session)
    _stub_opencode(monkeypatch, [ChatResponseChunk(type="done", metadata={})])

    task = workflow_runner.launch(run.id)
    assert run.id in workflow_runner.active_run_ids()
    await task
    assert run.id not in workflow_runner.active_run_ids()
