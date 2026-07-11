"""Final sanity pass: call the actual ``_auto_should_respond`` method (not
the standalone benchmark prompt copies) on the Madrid/Granada scenario plus
a few high-confidence scenarios to confirm the production code now answers
correctly with the new defaults.
"""

from __future__ import annotations

import asyncio
from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import uuid4

from app.services.room_chat_service import RoomChatService


def _msg(content: str, *, user: str | None = None, agent_id: str | None = None):
    return SimpleNamespace(
        id=str(uuid4()),
        content=content,
        sender_user_id=user,
        sender_agent_id=agent_id,
        meta=None,
        created_at=datetime.now(UTC),
        role="user" if user else "assistant",
    )


async def main() -> None:
    # Ensure the Ollama provider is registered (the service registers it
    # in __init__, which we skip via __new__).
    from app.core.config import get_settings
    from app.services.llm_provider import ProviderRegistry
    from app.services.ollama_provider import OllamaProvider

    if "ollama" not in ProviderRegistry.list_providers():
        ProviderRegistry.register(OllamaProvider(base_url=get_settings().ollama_base_url))

    svc = RoomChatService.__new__(RoomChatService)

    cases = [
        (
            "Madrid/Granada (bug #1)",
            SimpleNamespace(
                name="Helper",
                system_prompt=None,
                is_active=True,
                id="a1",
                provider="ollama",
                model="llama3.2:3b",
            ),
            [SimpleNamespace(name="Helper", id="a1", is_active=True)],
            [
                _msg(
                    "I would like to know how long it takes to go from madrid to granada in spain",
                    user="alice@example.com",
                )
            ],
            True,
        ),
        (
            "Story request, single agent (bug #2)",
            SimpleNamespace(
                name="agent",
                system_prompt=None,
                is_active=True,
                id="a1",
                provider="ollama",
                model="llama3.2:3b",
            ),
            [SimpleNamespace(name="agent", id="a1", is_active=True)],
            [
                _msg("I'm planning a road trip from Madrid to Granada", user="alice@example.com"),
                _msg(
                    "can you create a super story about people doing this trip?",
                    user="alice@example.com",
                ),
            ],
            True,
        ),
        (
            "Pure human small talk",
            SimpleNamespace(
                name="Helper",
                system_prompt=None,
                is_active=True,
                id="a1",
                provider="ollama",
                model="llama3.2:3b",
            ),
            [SimpleNamespace(name="Helper", id="a1", is_active=True)],
            [
                _msg("did you watch the game?", user="alice@example.com"),
                _msg("yeah it was crazy", user="bob@example.com"),
            ],
            False,
        ),
        (
            "Coding question to coder",
            SimpleNamespace(
                name="Coder",
                system_prompt="You are a senior Python engineer.",
                is_active=True,
                id="a1",
                provider="ollama",
                model="llama3.2:3b",
            ),
            [
                SimpleNamespace(name="Coder", id="a1", is_active=True),
                SimpleNamespace(name="Helper", id="a2", is_active=True),
            ],
            [_msg("how do I sort a list of dicts by a nested key?", user="alice@example.com")],
            True,
        ),
        (
            "Acknowledgement",
            SimpleNamespace(
                name="Helper",
                system_prompt=None,
                is_active=True,
                id="a1",
                provider="ollama",
                model="llama3.2:3b",
            ),
            [SimpleNamespace(name="Helper", id="a1", is_active=True)],
            [
                _msg("100 °C at sea level.", agent_id="a1"),
                _msg("thanks!", user="alice@example.com"),
            ],
            False,
        ),
    ]

    print(f"{'Scenario':<38} {'Expected':<10} {'Got':<10} {'Hit'}")
    print("-" * 70)
    for label, agent, agents, history, expected in cases:
        room = SimpleNamespace(id="room-test", agents=agents, members=[])
        try:
            decision = await svc._auto_should_respond(room, agent, history)
        except Exception as e:
            print(f"{label:<38} {'ERROR':<10} {repr(e)}")
            continue
        hit = "✅" if decision == expected else "❌"
        got = "JUMP IN" if decision else "stay quiet"
        want = "JUMP IN" if expected else "stay quiet"
        print(f"{label:<38} {want:<10} {got:<10} {hit}")


if __name__ == "__main__":
    asyncio.run(main())
