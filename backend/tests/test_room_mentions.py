"""Tests for @mention parsing + agent selection."""

import asyncio
from types import SimpleNamespace

from app.services.room_chat_service import RoomChatService


def test_parse_mention_single():
    names = ["Alice", "Bob"]
    assert RoomChatService.parse_mentions("hey @Alice how are you?", names) == {"Alice"}


def test_parse_mention_case_insensitive():
    names = ["Alice", "Bob"]
    assert RoomChatService.parse_mentions("yo @alice and @BOB", names) == {"Alice", "Bob"}


def test_parse_mention_unknown_ignored():
    assert RoomChatService.parse_mentions("@Charlie hi", ["Alice"]) == set()


def test_parse_mention_all_expands():
    names = ["Alice", "Bob", "Carol"]
    assert RoomChatService.parse_mentions("@all please chime in", names) == set(names)


def test_parse_mention_no_mentions():
    assert RoomChatService.parse_mentions("just thinking out loud", ["Alice"]) == set()


def _agent(id, name, mode="mention", turn=0, active=True):
    return SimpleNamespace(
        id=id,
        name=name,
        response_mode=mode,
        turn_order=turn,
        is_active=active,
        created_at=0,
    )


def _select(svc, room, content, *, triggering_agent_id=None, rr_history=None):
    return asyncio.run(
        svc._select_agents(
            room,
            content,
            triggering_agent_id,
            rr_history or [],
            history=[],
        )
    )


def test_select_agents_by_mention():
    room = SimpleNamespace(
        agents=[_agent("a1", "Alice"), _agent("a2", "Bob")],
        id="r",
        max_agent_turn_depth=3,
    )
    svc = RoomChatService.__new__(RoomChatService)
    picks = _select(svc, room, "@Bob help")
    assert [a.name for a in picks] == ["Bob"]


def test_select_agents_falls_back_to_always():
    room = SimpleNamespace(
        agents=[
            _agent("a1", "Alice", mode="always", turn=0),
            _agent("a2", "Bob", mode="always", turn=1),
            _agent("a3", "Silent", mode="mention", turn=2),
        ],
        id="r",
        max_agent_turn_depth=3,
    )
    svc = RoomChatService.__new__(RoomChatService)
    picks = _select(svc, room, "no mention here")
    assert [a.name for a in picks] == ["Alice", "Bob"]


def test_round_robin_picks_least_recent():
    room = SimpleNamespace(
        agents=[
            _agent("a1", "A", mode="round_robin", turn=0),
            _agent("a2", "B", mode="round_robin", turn=1),
        ],
        id="r",
        max_agent_turn_depth=3,
    )
    svc = RoomChatService.__new__(RoomChatService)
    picks = _select(svc, room, "no mention", rr_history=["a1"])
    # a1 spoke most recently so a2 should go
    assert picks[0].id == "a2"


def test_agent_never_responds_to_itself():
    room = SimpleNamespace(
        agents=[_agent("a1", "Alice", mode="always"), _agent("a2", "Bob", mode="always")],
        id="r",
        max_agent_turn_depth=3,
    )
    svc = RoomChatService.__new__(RoomChatService)
    picks = _select(svc, room, "hi", triggering_agent_id="a1")
    assert [a.name for a in picks] == ["Bob"]


def test_explicit_mentions_skip_auto_agents():
    """When user @-mentions someone, 'auto' agents should not LLM-judge."""
    room = SimpleNamespace(
        agents=[
            _agent("a1", "Alice", mode="mention"),
            _agent("a2", "Auto", mode="auto"),
        ],
        id="r",
        max_agent_turn_depth=3,
    )
    svc = RoomChatService.__new__(RoomChatService)
    # _auto_should_respond is not patched; if it were called, it would explode.
    # Since the user mentions Alice, only Alice should be selected and the
    # auto judge must not be invoked.
    picks = _select(svc, room, "@Alice please respond")
    assert [a.name for a in picks] == ["Alice"]


def test_auto_agent_runs_when_judge_says_yes():
    room = SimpleNamespace(
        agents=[_agent("a1", "Auto", mode="auto", turn=0)],
        id="r",
        max_agent_turn_depth=3,
    )
    svc = RoomChatService.__new__(RoomChatService)

    async def fake_judge(_room, _agent, _history):
        return True

    svc._auto_should_respond = fake_judge  # type: ignore[assignment]
    picks = asyncio.run(
        svc._select_agents(
            room,
            "what do you think?",
            None,
            [],
            history=[SimpleNamespace(content="ping", sender_user_id="u@x", sender_agent_id=None)],
        )
    )
    assert [a.name for a in picks] == ["Auto"]


def test_auto_agent_skipped_when_judge_says_no():
    room = SimpleNamespace(
        agents=[_agent("a1", "Auto", mode="auto", turn=0)],
        id="r",
        max_agent_turn_depth=3,
    )
    svc = RoomChatService.__new__(RoomChatService)

    async def fake_judge(_room, _agent, _history):
        return False

    svc._auto_should_respond = fake_judge  # type: ignore[assignment]
    picks = asyncio.run(
        svc._select_agents(
            room,
            "casual chat between humans",
            None,
            [],
            history=[SimpleNamespace(content="ping", sender_user_id="u@x", sender_agent_id=None)],
        )
    )
    assert picks == []
