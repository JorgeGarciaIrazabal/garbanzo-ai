"""Decision routing leaves deterministic room eligibility rules authoritative."""

import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import pytest

from app.db import session as db_session
from app.services.decision_service import MAX_REQUEST_BYTES, DecisionError
from app.services.room_chat_service import (
    RoomChatService,
    _detached_room_turns,
    _TurnContext,
    schedule_room_agent_turns,
)

pytestmark = pytest.mark.asyncio


def _agent(id="a", name="Auto", mode="auto", active=True, turn=0):
    return SimpleNamespace(
        id=id,
        name=name,
        response_mode=mode,
        is_active=active,
        turn_order=turn,
        created_at=0,
        system_prompt="Expert in engineering",
    )


def _history(count=1, content="Could you help?"):
    return [
        SimpleNamespace(
            content=f"{i}: {content}", sender_user_id="private-user-id", sender_agent_id=None
        )
        for i in range(count)
    ]


@pytest.fixture
def decision_room():
    service = RoomChatService.__new__(RoomChatService)
    client = SimpleNamespace(
        probabilities=AsyncMock(return_value={"needs_reply": 0.8, "should_respond": 0.8})
    )
    with (
        patch(
            "app.services.room_chat_service.get_settings",
            return_value=SimpleNamespace(room_decisions_enabled=True),
        ),
        patch("app.services.room_chat_service.get_decision_service", return_value=client),
    ):
        yield service, client


@pytest.mark.parametrize(
    "probability,selected", [(0.0, False), (0.49, False), (0.5, False), (1.0, True)]
)
async def test_auto_selection_uses_explicit_probability_threshold(
    decision_room, probability, selected
):
    service, client = decision_room
    client.probabilities.return_value = {"needs_reply": probability, "should_respond": probability}
    room = SimpleNamespace(id="r", agents=[_agent()])
    result = await service._select_agents(room, "help?", None, [], _history())
    assert bool(result) is selected
    assert client.probabilities.await_count == (2 if selected else 1)


async def test_mentions_skip_decisions_and_preserve_self_and_active_rules(decision_room):
    service, client = decision_room
    room = SimpleNamespace(id="r", agents=[_agent(), _agent("b", "Inactive", active=False)])
    assert await service._select_agents(room, "@Auto", None, [], _history()) == [room.agents[0]]
    assert await service._select_agents(room, "@Auto", "a", [], _history()) == []
    client.probabilities.assert_not_awaited()


async def test_self_and_inactive_auto_agents_are_never_scored(decision_room):
    service, client = decision_room
    room = SimpleNamespace(id="r", agents=[_agent(), _agent("b", "Inactive", active=False)])
    assert await service._select_agents(room, "help?", "a", [], _history()) == []
    client.probabilities.assert_not_awaited()


async def test_always_and_round_robin_rules_are_preserved(decision_room):
    service, client = decision_room
    room = SimpleNamespace(
        id="r",
        agents=[
            _agent("a", "Always", "always"),
            _agent("b", "RR", "round_robin"),
            _agent("c", "Auto", turn=2),
        ],
    )
    result = await service._select_agents(room, "help?", None, [], _history())
    assert [agent.id for agent in result] == ["a", "c"]
    room.agents.pop(0)
    result = await service._select_agents(room, "help?", None, [], _history())
    assert [agent.id for agent in result] == ["b", "c"]
    assert client.probabilities.await_count == 4


async def test_failure_propagates_instead_of_silencing_agent(decision_room):
    service, client = decision_room
    client.probabilities.side_effect = DecisionError("service unavailable")
    with pytest.raises(DecisionError, match="service unavailable"):
        await service._select_agents(
            SimpleNamespace(id="r", agents=[_agent()]), "help?", None, [], _history()
        )


async def test_context_contains_only_bounded_last_eight_messages_and_persona(decision_room):
    service, client = decision_room
    agent = _agent()
    agent.system_prompt = "🧑" * 10000
    room = SimpleNamespace(id="r", agents=[agent])
    history = _history(10, content="\x00😀" * 10000)
    await service._select_agents(room, "help?", None, [], history)
    gate = client.probabilities.await_args_list[0].kwargs["state"]
    assert gate["latest_message"].startswith("9:")
    assert gate["preceding_message"]["content"].startswith("8:")
    assert "recent_conversation" not in gate
    kwargs = client.probabilities.await_args.kwargs
    state = kwargs["state"]
    assert len(state["recent_conversation"]) == 8
    assert state["recent_conversation"][0]["content"].startswith("2:")
    assert "private-user-id" not in json.dumps(state)
    assert (
        len(json.dumps({"model": "clef:cloud", **kwargs}, ensure_ascii=False).encode())
        < MAX_REQUEST_BYTES
    )


async def test_depth_cap_prevents_decision_calls(decision_room):
    service, client = decision_room
    service._load_history = AsyncMock()
    room = SimpleNamespace(id="r", max_agent_turn_depth=2, agents=[_agent()])
    await service._run_agent_turns(
        _TurnContext(room=room, depth=2), triggering_content="help?", triggering_agent_id=None
    )
    service._load_history.assert_not_awaited()
    client.probabilities.assert_not_awaited()


async def test_disabled_feature_uses_configured_legacy_judge():
    service = RoomChatService.__new__(RoomChatService)
    service._auto_should_respond = AsyncMock(return_value=True)
    settings = SimpleNamespace(room_decisions_enabled=False, room_auto_judge_model="legacy")
    with (
        patch("app.services.room_chat_service.get_settings", return_value=settings),
        patch("app.services.room_chat_service.get_decision_service") as client_factory,
    ):
        result = await service._select_agents(
            SimpleNamespace(id="r", agents=[_agent()]), "help?", None, [], _history()
        )
    assert len(result) == 1
    service._auto_should_respond.assert_awaited_once()
    client_factory.assert_not_called()


async def test_saved_post_broadcasts_decision_failure_without_losing_message(monkeypatch):
    service = RoomChatService.__new__(RoomChatService)
    saved = SimpleNamespace(id="saved")
    service._load_room = AsyncMock(return_value=SimpleNamespace(id="r"))
    service._persist_message = AsyncMock(return_value=saved)
    service._message_event = lambda _: {"type": "message"}
    service._notify_offline_members = AsyncMock()
    service._run_agent_turns = AsyncMock(side_effect=DecisionError("unavailable"))
    broadcast = AsyncMock()
    monkeypatch.setattr("app.services.room_chat_service.room_manager.broadcast", broadcast)
    result = await service.handle_user_post("r", "user", "hello")
    assert result is saved
    assert broadcast.await_args_list[-1].args[1]["type"] == "error"
    assert "message was saved" in broadcast.await_args_list[-1].args[1]["error"]


async def test_detached_selection_failure_is_visible(monkeypatch):

    class Session:
        async def __aenter__(self):
            return object()

        async def __aexit__(self, *_):
            pass

    service = SimpleNamespace(
        _load_room=AsyncMock(return_value=SimpleNamespace(id="r")),
        _run_agent_turns=AsyncMock(side_effect=DecisionError("unavailable")),
    )
    monkeypatch.setattr(db_session, "async_session_maker", Session)
    monkeypatch.setattr("app.services.room_chat_service.RoomChatService", lambda _: service)
    broadcast = AsyncMock()
    monkeypatch.setattr("app.services.room_chat_service.room_manager.broadcast", broadcast)
    schedule_room_agent_turns("r", "hello")
    await asyncio.gather(*list(_detached_room_turns))
    assert broadcast.await_args.args[1]["type"] == "error"


async def test_closing_acknowledgment_stops_before_history_judgment(decision_room):
    service, client = decision_room
    client.probabilities.return_value = {"needs_reply": 0.01}
    room = SimpleNamespace(id="r", agents=[_agent()])
    assert (
        await service._select_agents(
            room, "Thanks, perfect.", None, [], _history(content="Thanks, perfect.")
        )
        == []
    )
    client.probabilities.assert_awaited_once()
    assert "recent_conversation" not in client.probabilities.await_args.kwargs["state"]


async def test_new_request_still_requires_agent_relevance(decision_room):
    service, client = decision_room
    client.probabilities.side_effect = [{"needs_reply": 0.9}, {"should_respond": 0.5}]
    assert (
        await service._select_agents(
            SimpleNamespace(id="r", agents=[_agent()]), "help?", None, [], _history()
        )
        == []
    )
