"""Presentation invariants and durable, permission-checked user submissions."""

import copy
import uuid
from unittest.mock import AsyncMock, Mock

import pytest
from fastapi import HTTPException
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.models.memory import UserMemory
from app.models.message import Message
from app.models.ui_submission import UISubmissionRecord
from app.schemas.visual_ui import Presentation, UISubmission
from app.services.visual_ui import UIActionService, validate_values


def example():
    return {
        "summary": "Save a useful memory.",
        "surface_id": "memory",
        "components": [
            {
                "id": "root",
                "component": "Form",
                "fields": [
                    {"name": "content", "label": "Memory", "type": "text", "required": True}
                ],
                "action": "save",
                "submitLabel": "Save memory",
            }
        ],
        "actions": [
            {
                "id": "save",
                "kind": "tool",
                "tool": "memories",
                "arguments": {"operation": "create"},
                "bindings": {"content": "content"},
            }
        ],
    }


def test_catalog_accepts_composed_visuals_and_rejects_invalid_trees():
    presentation = Presentation.model_validate(example())
    assert presentation.result()["presentation"]["surface_id"] == "memory"
    for components in (
        [{"id": "root", "component": "HTML", "text": "<script>"}],
        [{"id": "root", "component": "Column", "children": ["root"]}],
        [{"id": "root", "component": "Column", "children": ["missing"]}],
        [
            {"id": "root", "component": "Text", "text": "hello"},
            {"id": "unused", "component": "Text", "text": "hidden"},
        ],
        [
            {
                "id": "root",
                "component": "Chart",
                "kind": "pie",
                "labels": ["a"],
                "series": [{"label": "x", "values": [-1]}],
            }
        ],
    ):
        with pytest.raises(ValueError):
            Presentation.model_validate(
                {"summary": "test", "surface_id": "x", "components": components}
            )


def test_rejects_invalid_actions_and_nonfinite_data():
    invalid = example()
    invalid["actions"][0]["bindings"] = {"content": "undeclared"}
    with pytest.raises(ValueError, match="bindings"):
        Presentation.model_validate(invalid)
    invalid = example()
    invalid["components"][0]["action"] = "unknown"
    with pytest.raises(ValueError, match="declared"):
        Presentation.model_validate(invalid)
    with pytest.raises(ValueError):
        Presentation.model_validate(
            {
                "summary": "test",
                "surface_id": "x",
                "components": [
                    {
                        "id": "root",
                        "component": "Chart",
                        "kind": "line",
                        "labels": ["x"],
                        "series": [{"label": "x", "values": [float("nan")]}],
                    },
                ],
            }
        )


def test_submission_values_are_typed_and_cannot_add_arguments():
    component = example()["components"][0]
    assert validate_values(component, {"content": "A useful memory"}) == {
        "content": "A useful memory"
    }
    for values in ({"user_id": "other"}, {"content": "  "}, {"content": False}):
        with pytest.raises(ValueError):
            validate_values(component, values)
    component = {
        "component": "Form",
        "fields": [{"name": "count", "label": "Count", "type": "number", "required": True}],
    }
    with pytest.raises(ValueError):
        validate_values(component, {"count": True})


async def saved_presentation(db, conversation, args=None):
    presentation = Presentation.model_validate(args or example())
    source = Message(
        id=str(uuid.uuid4()),
        conversation_id=conversation.id,
        role="tool_result",
        content=presentation.summary,
        session_epoch=conversation.session_epoch,
        meta={
            "tool_call_id": "visual-call",
            "tool_name": "render_ui",
            "result": presentation.result(),
        },
    )
    db.add(source)
    await db.commit()
    return source


def submission(**overrides):
    return UISubmission.model_validate(
        {
            "tool_call_id": "visual-call",
            "surface_id": "memory",
            "action_id": "save",
            "submission_id": str(uuid.uuid4()),
            "values": {"content": "I prefer tea"},
            **overrides,
        }
    )


@pytest.mark.asyncio
async def test_repeated_submit_executes_once_and_survives_new_service(
    db_session,
    test_conversation,
    test_user_email,
    monkeypatch,
):
    await saved_presentation(db_session, test_conversation)
    service = UIActionService(db_session)
    # Discover only local tools; the actual native executor still runs.
    monkeypatch.setattr(service.chat._mcp, "list_all_tools", AsyncMock(return_value=[]))
    result = await service.submit(test_conversation.id, test_user_email, submission())
    assert result["status"] == "completed", result
    assert result["result"]["ok"] is True
    replay = await UIActionService(db_session).submit(
        test_conversation.id, test_user_email, submission()
    )
    assert replay == result
    memories = (await db_session.scalars(select(UserMemory))).all()
    assert len(memories) == 1
    assert memories[0].content == "I prefer tea"
    state = await service.state(test_conversation.id, test_user_email, "visual-call")
    assert state["submissions"] == [result]
    with pytest.raises(HTTPException) as error:
        await service.submit(
            test_conversation.id, test_user_email, submission(values={"content": "different"})
        )
    assert error.value.status_code == 409


@pytest.mark.asyncio
async def test_permission_and_stale_presentation_rejections(
    db_session,
    test_conversation,
    test_user_email,
):
    source = await saved_presentation(db_session, test_conversation)
    service = UIActionService(db_session)
    with pytest.raises(HTTPException) as error:
        await service.state(test_conversation.id, "someone-else@example.com", "visual-call")
    assert error.value.status_code == 404
    test_conversation.enabled_tools = []
    await db_session.commit()
    with pytest.raises(HTTPException) as error:
        await service.submit(test_conversation.id, test_user_email, submission())
    assert error.value.status_code == 403
    tools, lookup = await service.chat._resolve_tools_for_conversation(test_conversation)
    assert list(lookup) == ["render_ui"]
    rendered = await service.chat._execute_tool_call(
        {"name": "render_ui", "arguments": example()}, lookup, test_conversation
    )
    assert rendered["ok"]
    test_conversation.enabled_tools = None
    db_session.add(
        Message(
            id=str(uuid.uuid4()),
            conversation_id=test_conversation.id,
            role="user",
            content="new request",
            seq=source.seq + 1,
        )
    )
    await db_session.commit()
    with pytest.raises(HTTPException) as error:
        await service.submit(test_conversation.id, test_user_email, submission())
    assert error.value.status_code == 409


@pytest.mark.asyncio
async def test_pending_and_failed_claims_never_retry(
    db_session,
    test_conversation,
    test_user_email,
    monkeypatch,
):
    source = await saved_presentation(db_session, test_conversation)
    data = submission()
    record = UISubmissionRecord(
        id=data.submission_id,
        message_id=source.id,
        action_id="save",
        status="pending",
        values=data.values,
    )
    db_session.add(record)
    await db_session.commit()
    service = UIActionService(db_session)
    execute = AsyncMock(side_effect=AssertionError("must not execute"))
    monkeypatch.setattr(service.chat, "_execute_tool_call", execute)
    assert (await service.submit(test_conversation.id, test_user_email, data))[
        "status"
    ] == "pending"
    record.status = "failed"
    record.result = {"ok": False, "error": "uncertain outcome"}
    await db_session.commit()
    assert (await service.submit(test_conversation.id, test_user_email, data))["status"] == "failed"
    execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_follow_up_is_contextual_and_api_requires_auth(
    db_session,
    test_conversation,
    test_user_email,
    monkeypatch,
):
    launch = Mock()
    monkeypatch.setattr(UIActionService, "start_follow_up", launch)
    args = copy.deepcopy(example())
    args["actions"] = [{"id": "save", "kind": "follow_up", "prompt": "Explain my choice"}]
    await saved_presentation(db_session, test_conversation, args)
    result = await UIActionService(db_session).submit(
        test_conversation.id, test_user_email, submission()
    )
    message_id = result["result"]["message_id"]
    user_message = await db_session.get(Message, message_id)
    assert "Explain my choice" in user_message.content
    assert "I prefer tea" in user_message.content
    assert "Memory: I prefer tea" in user_message.content
    replay = await UIActionService(db_session).submit(
        test_conversation.id, test_user_email, submission()
    )
    assert replay == result
    launch.assert_called_once_with(test_conversation.id, test_user_email, message_id)
    users = (await db_session.scalars(select(Message).where(Message.role == "user"))).all()
    assert len(users) == 1
    path = f"/api/v1/chat/conversations/{test_conversation.id}/ui-actions"
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        assert (await client.post(path, json=submission().model_dump())).status_code == 401
        app.dependency_overrides[get_current_user] = lambda: {"email": test_user_email}
        app.dependency_overrides[get_db] = lambda: db_session
        try:
            response = await client.get(path, params={"tool_call_id": "visual-call"})
            assert response.status_code == 200, response.text
            assert response.json()["submissions"][0]["status"] == "completed"
        finally:
            app.dependency_overrides.pop(get_current_user, None)
            app.dependency_overrides.pop(get_db, None)


@pytest.mark.parametrize(
    "field",
    [
        {"type": "select", "options": ["A"], "value": 7},
        {"type": "select", "options": ["A"], "value": "B"},
        {"type": "select", "options": ["A", "A"], "value": "A"},
        {"type": "number", "value": "seven"},
        {"type": "checkbox", "value": 1},
        {"type": "date", "value": "2026-02-31"},
    ],
)
def test_form_defaults_must_be_renderable(field):
    args = example()
    args["components"][0]["fields"] = [{"name": "content", "label": "Value", **field}]
    with pytest.raises(ValueError):
        Presentation.model_validate(args)


@pytest.mark.asyncio
async def test_prompt_only_submission_preserves_thinking(
    db_session,
    test_conversation,
    test_user_email,
    monkeypatch,
):
    test_conversation.thinking_level = "high"
    args = example()
    args["components"][0]["fields"] = []
    args["actions"] = [
        {
            "id": "save",
            "kind": "tool",
            "tool": "set_conversation_style",
            "arguments": {"system_prompt": "Be concise"},
        }
    ]
    await saved_presentation(db_session, test_conversation, args)
    service = UIActionService(db_session)
    monkeypatch.setattr(service.chat._mcp, "list_all_tools", AsyncMock(return_value=[]))
    result = await service.submit(test_conversation.id, test_user_email, submission(values={}))
    assert result["status"] == "completed", result
    await db_session.refresh(test_conversation)
    assert test_conversation.thinking_level == "high"
    assert test_conversation.system_prompt == "Be concise"
