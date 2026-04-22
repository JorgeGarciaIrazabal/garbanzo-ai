"""Tests for @mention parsing + agent selection."""

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


def test_select_agents_by_mention():
    room = SimpleNamespace(
        agents=[_agent("a1", "Alice"), _agent("a2", "Bob")],
        id="r",
        max_agent_turn_depth=3,
    )
    svc = RoomChatService.__new__(RoomChatService)
    picks = svc._select_agents(room, "@Bob help", triggering_agent_id=None, round_robin_history=[])
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
    picks = svc._select_agents(room, "no mention here", triggering_agent_id=None, round_robin_history=[])
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
    picks = svc._select_agents(
        room, "no mention", triggering_agent_id=None, round_robin_history=["a1"]
    )
    # a1 spoke most recently so a2 should go
    assert picks[0].id == "a2"


def test_agent_never_responds_to_itself():
    room = SimpleNamespace(
        agents=[_agent("a1", "Alice", mode="always"), _agent("a2", "Bob", mode="always")],
        id="r",
        max_agent_turn_depth=3,
    )
    svc = RoomChatService.__new__(RoomChatService)
    picks = svc._select_agents(room, "hi", triggering_agent_id="a1", round_robin_history=[])
    assert [a.name for a in picks] == ["Bob"]
