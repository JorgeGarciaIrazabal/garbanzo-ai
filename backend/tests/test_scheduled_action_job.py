"""Tests for the scheduled-action execution job."""

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

pytestmark = pytest.mark.asyncio


async def _make_stub_module(action, patches):
    """Install stubs for ChatService, ConversationService, send_to_user."""
    # Stub conversation
    conversation = SimpleNamespace(id="conv-123")
    convs_instance = MagicMock()
    convs_instance.create = AsyncMock(return_value=conversation)
    patches.append(
        patch(
            "app.jobs.scheduled_action_job.ConversationService",
            return_value=convs_instance,
        )
    )

    # Stub ChatService — send_message yields a couple of chunks.
    async def _iter_chunks(**_):
        yield SimpleNamespace(
            content="hi ",
            is_thinking=False,
            is_finished=False,
            metadata=None,
        )
        yield SimpleNamespace(
            content="there",
            is_thinking=False,
            is_finished=True,
            metadata={"tokens_prompt": 5},
        )

    chat_instance = MagicMock()
    chat_instance.send_message = _iter_chunks
    patches.append(
        patch(
            "app.jobs.scheduled_action_job.ChatService",
            return_value=chat_instance,
        )
    )

    # No-op notification sender.
    send_stub = AsyncMock(return_value=1)
    patches.append(patch("app.jobs.scheduled_action_job.send_to_user", send_stub))

    return conversation, convs_instance, chat_instance, send_stub


async def test_run_scheduled_action_happy_path(db_session, test_user_email):
    from app.services.scheduled_action_service import ScheduledActionService

    svc = ScheduledActionService(db_session)
    action = await svc.create(
        user_id=test_user_email,
        prompt="Good morning",
        cron_expr="0 9 * * *",
        title="Standup",
    )

    patches: list = []
    _, convs_instance, _, send_stub = await _make_stub_module(action, patches)

    session_maker_mock = MagicMock()

    class _Ctx:
        async def __aenter__(self):  # noqa: N805
            return db_session

        async def __aexit__(self, *_):  # noqa: N805
            return False

    session_maker_mock.return_value = _Ctx()
    patches.append(patch("app.jobs.scheduled_action_job.async_session_maker", session_maker_mock))

    for p in patches:
        p.start()
    try:
        from app.jobs.scheduled_action_job import run_scheduled_action

        await run_scheduled_action(action.id)
    finally:
        for p in reversed(patches):
            p.stop()

    # A conversation was created for this user.
    convs_instance.create.assert_called_once()
    create_kwargs = convs_instance.create.call_args.kwargs
    assert create_kwargs["user_id"] == test_user_email
    assert create_kwargs["title"].startswith("⏰")

    # A reminders notification went out, with the conversation id.
    send_stub.assert_awaited_once()
    send_kwargs = send_stub.await_args.kwargs
    assert send_kwargs["channel"] == "reminders"
    assert send_kwargs["data"]["conversation_id"] == "conv-123"
    assert send_kwargs["data"]["scheduled_action_id"] == action.id

    # Run status was recorded.
    refreshed = await svc.get(action.id, test_user_email)
    assert refreshed is not None
    assert refreshed.last_run_status == "success"
    assert refreshed.last_run_at is not None


async def test_run_scheduled_action_skips_inactive(db_session, test_user_email):
    from app.services.scheduled_action_service import ScheduledActionService

    svc = ScheduledActionService(db_session)
    action = await svc.create(
        user_id=test_user_email,
        prompt="x",
        cron_expr="0 9 * * *",
        is_active=False,
    )

    patches: list = []
    conv_mock = MagicMock()
    patches.append(patch("app.jobs.scheduled_action_job.ConversationService", conv_mock))
    patches.append(patch("app.jobs.scheduled_action_job.ChatService", MagicMock()))
    patches.append(patch("app.jobs.scheduled_action_job.send_to_user", AsyncMock()))

    class _Ctx:
        async def __aenter__(self):  # noqa: N805
            return db_session

        async def __aexit__(self, *_):  # noqa: N805
            return False

    session_maker_mock = MagicMock(return_value=_Ctx())
    patches.append(patch("app.jobs.scheduled_action_job.async_session_maker", session_maker_mock))

    for p in patches:
        p.start()
    try:
        from app.jobs.scheduled_action_job import run_scheduled_action

        await run_scheduled_action(action.id)
    finally:
        for p in reversed(patches):
            p.stop()

    # Nothing should be spun up for an inactive action.
    conv_mock.assert_not_called()


async def test_run_scheduled_action_missing_action_is_noop(db_session):
    patches: list = []
    patches.append(patch("app.jobs.scheduled_action_job.ConversationService", MagicMock()))
    patches.append(patch("app.jobs.scheduled_action_job.ChatService", MagicMock()))

    class _Ctx:
        async def __aenter__(self):  # noqa: N805
            return db_session

        async def __aexit__(self, *_):  # noqa: N805
            return False

    patches.append(
        patch(
            "app.jobs.scheduled_action_job.async_session_maker",
            MagicMock(return_value=_Ctx()),
        )
    )

    for p in patches:
        p.start()
    try:
        from app.jobs.scheduled_action_job import run_scheduled_action

        # Does not raise.
        await run_scheduled_action("does-not-exist")
    finally:
        for p in reversed(patches):
            p.stop()
