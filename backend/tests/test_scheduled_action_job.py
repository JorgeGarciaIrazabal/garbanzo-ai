"""Tests for the scheduled-action execution job."""

import uuid
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.models.conversation import Conversation
from app.services.scheduled_action_service import ScheduledActionService

pytestmark = pytest.mark.asyncio


async def _make_stub_module(action, patches, db_session=None, existing_conversation=None):
    """Install stubs for ChatService, ConversationService, send_to_user.

    ``existing_conversation`` simulates a previously-created conversation
    the recurring action should reuse (returned by ``ConversationService.get``).

    The stub's ``create`` inserts a *real* ``Conversation`` row into
    ``db_session`` so the job's foreign-key write to
    ``scheduled_actions.conversation_id`` satisfies SQLite's FK enforcement.
    """
    # Stub conversation: a *real* row so the FK write succeeds.
    conversation = existing_conversation
    if conversation is None:
        conversation = Conversation(
            id=str(uuid.uuid4()),
            user_id=action.user_id,
            title=f"⏰ {action.title or action.prompt}",
            model=action.model or "glm-5.2:cloud",
        )
        db_session.add(conversation)
        await db_session.commit()
        await db_session.refresh(conversation)

    convs_instance = MagicMock()
    convs_instance.create = AsyncMock(return_value=conversation)
    convs_instance.get = AsyncMock(return_value=existing_conversation)
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
    svc = ScheduledActionService(db_session)
    action = await svc.create(
        user_id=test_user_email,
        prompt="Good morning",
        cron_expr="0 9 * * *",
        title="Standup",
    )

    patches: list = []
    conversation, convs_instance, _, send_stub = await _make_stub_module(
        action, patches, db_session=db_session
    )

    session_maker_mock = MagicMock()

    class _Ctx:
        async def __aenter__(self):  # noqa: N805
            return db_session

        async def __aexit__(self, *_):  # noqa: N805
            return False

    session_maker_mock.return_value = _Ctx()
    patches.append(patch("app.jobs.scheduled_action_job.async_session_maker", session_maker_mock))
    patches.append(
        patch(
            "app.jobs.scheduled_action_job.get_settings",
            return_value=SimpleNamespace(scheduled_action_model="glm-5.2:cloud"),
        )
    )

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
    assert create_kwargs["model"] == "glm-5.2:cloud"

    # A reminders notification went out, with the conversation id.
    send_stub.assert_awaited_once()
    send_kwargs = send_stub.await_args.kwargs
    assert send_kwargs["channel"] == "reminders"
    assert send_kwargs["data"]["conversation_id"] == conversation.id
    assert send_kwargs["data"]["scheduled_action_id"] == action.id

    # Run status was recorded.
    refreshed = await svc.get(action.id, test_user_email)
    assert refreshed is not None
    assert refreshed.last_run_status == "success"
    assert refreshed.last_run_at is not None


async def test_run_scheduled_action_skips_inactive(db_session, test_user_email):
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


async def test_run_scheduled_action_reuses_conversation(db_session, test_user_email):
    """A recurring action whose ``conversation_id`` is already set posts
    into that same conversation instead of creating a new one (user-report
    89b954f7).
    """
    svc = ScheduledActionService(db_session)
    action = await svc.create(
        user_id=test_user_email,
        prompt="Daily standup",
        cron_expr="0 9 * * *",
        title="Standup",
    )
    # Simulate a prior run having created a real conversation and pointing
    # the action at it.
    existing = Conversation(
        id="existing-conv-456",
        user_id=test_user_email,
        title="⏰ Standup",
        model="glm-5.2:cloud",
    )
    db_session.add(existing)
    await db_session.commit()
    await db_session.refresh(existing)
    action.conversation_id = existing.id
    await db_session.commit()

    patches: list = []
    _, convs_instance, _, send_stub = await _make_stub_module(
        action, patches, db_session=db_session, existing_conversation=existing
    )

    session_maker_mock = MagicMock()

    class _Ctx:
        async def __aenter__(self):  # noqa: N805
            return db_session

        async def __aexit__(self, *_):  # noqa: N805
            return False

    session_maker_mock.return_value = _Ctx()
    patches.append(patch("app.jobs.scheduled_action_job.async_session_maker", session_maker_mock))
    patches.append(
        patch(
            "app.jobs.scheduled_action_job.get_settings",
            return_value=SimpleNamespace(scheduled_action_model="glm-5.2:cloud"),
        )
    )

    for p in patches:
        p.start()
    try:
        from app.jobs.scheduled_action_job import run_scheduled_action

        await run_scheduled_action(action.id)
    finally:
        for p in reversed(patches):
            p.stop()

    # No new conversation was created — the existing one was reused.
    convs_instance.create.assert_not_called()
    convs_instance.get.assert_awaited_once()
    get_args = convs_instance.get.call_args.args
    assert get_args[0] == "existing-conv-456"

    # The notification points at the reused conversation.
    send_stub.assert_awaited_once()
    send_kwargs = send_stub.await_args.kwargs
    assert send_kwargs["channel"] == "reminders"
    assert send_kwargs["data"]["conversation_id"] == "existing-conv-456"
    assert send_kwargs["data"]["scheduled_action_id"] == action.id


async def test_run_scheduled_action_recreates_if_conversation_deleted(db_session, test_user_email):
    """If the action's conversation was soft-deleted, a new one is created
    and the action's ``conversation_id`` is repointed at it.
    """
    svc = ScheduledActionService(db_session)
    action = await svc.create(
        user_id=test_user_email,
        prompt="Daily standup",
        cron_expr="0 9 * * *",
    )
    # Real soft-deleted conversation so the FK write to conversation_id
    # succeeds on the first run, before the job detects is_deleted and
    # repoints at the fresh one.
    dead = Conversation(
        id="dead-conv",
        user_id=test_user_email,
        title="⏰ Standup",
        model="glm-5.2:cloud",
        is_deleted=True,
    )
    db_session.add(dead)
    await db_session.commit()
    action.conversation_id = dead.id
    await db_session.commit()

    # Real fresh conversation the stub ``create`` will return.
    fresh = Conversation(
        id="new-conv-789",
        user_id=test_user_email,
        title="⏰ Standup",
        model="glm-5.2:cloud",
    )
    db_session.add(fresh)
    await db_session.commit()
    await db_session.refresh(fresh)

    patches: list = []
    convs_instance = MagicMock()
    convs_instance.get = AsyncMock(return_value=dead)
    convs_instance.create = AsyncMock(return_value=fresh)
    patches.append(
        patch(
            "app.jobs.scheduled_action_job.ConversationService",
            return_value=convs_instance,
        )
    )

    async def _iter_chunks(**_):
        yield SimpleNamespace(
            content="ok",
            is_thinking=False,
            is_finished=True,
            metadata=None,
        )

    chat_instance = MagicMock()
    chat_instance.send_message = _iter_chunks
    patches.append(patch("app.jobs.scheduled_action_job.ChatService", return_value=chat_instance))
    patches.append(patch("app.jobs.scheduled_action_job.send_to_user", AsyncMock()))

    class _Ctx:
        async def __aenter__(self):  # noqa: N805
            return db_session

        async def __aexit__(self, *_):  # noqa: N805
            return False

    session_maker_mock = MagicMock(return_value=_Ctx())
    patches.append(patch("app.jobs.scheduled_action_job.async_session_maker", session_maker_mock))
    patches.append(
        patch(
            "app.jobs.scheduled_action_job.get_settings",
            return_value=SimpleNamespace(scheduled_action_model="glm-5.2:cloud"),
        )
    )

    for p in patches:
        p.start()
    try:
        from app.jobs.scheduled_action_job import run_scheduled_action

        await run_scheduled_action(action.id)
    finally:
        for p in reversed(patches):
            p.stop()

    # A new conversation was created and the action was repointed at it.
    convs_instance.create.assert_awaited_once()
    refreshed = await svc.get(action.id, test_user_email)
    assert refreshed is not None
    assert refreshed.conversation_id == "new-conv-789"
