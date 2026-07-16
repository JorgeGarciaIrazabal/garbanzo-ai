"""Tests for the dynamic <context> block (time / timezone / location)."""

from collections.abc import AsyncIterator
from datetime import UTC, datetime

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.api.v1.endpoints.chat import get_chat_service
from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.db.session import get_db
from app.main import app
from app.models.user import User
from app.schemas.chat import ChatOptions
from app.services.chat_context import build_dynamic_context_block
from app.services.chat_service import ChatService
from app.services.llm_provider import ChatChunk, LLMProvider, ModelInfo, ProviderRegistry
from app.services.llm_provider import Message as LLMMessage

pytestmark = pytest.mark.asyncio

# A fixed instant so assertions are deterministic: a Thursday, 14:30 UTC,
# which is 10:30 in New York (EDT) — crossing no date boundary — and
# 23:30 in Tokyo, crossing one.
_NOW = datetime(2026, 7, 16, 14, 30, tzinfo=UTC)


class TestBlockFormat:
    async def test_utc_time_always_present(self):
        block = build_dynamic_context_block(now=_NOW)
        assert block.startswith("<context>")
        assert block.endswith("</context>")
        assert "Current UTC time: Thursday 2026-07-16 14:30 UTC" in block

    async def test_framed_as_background_only(self):
        block = build_dynamic_context_block(now=_NOW)
        assert "Use it only when the user's request actually depends on it" in block

    async def test_local_time_with_timezone(self):
        block = build_dynamic_context_block(timezone="America/New_York", now=_NOW)
        assert "User's local time: Thursday 2026-07-16 10:30 (America/New_York)" in block

    async def test_local_time_crosses_date_boundary(self):
        block = build_dynamic_context_block(timezone="Asia/Tokyo", now=_NOW)
        assert "User's local time: Thursday 2026-07-16 23:30 (Asia/Tokyo)" in block

    async def test_no_timezone_no_local_line(self):
        block = build_dynamic_context_block(now=_NOW)
        assert "local time" not in block

    async def test_unknown_timezone_skips_line_keeps_block(self):
        # Validated at the API boundary; render must still survive a zone
        # the server's zoneinfo no longer knows.
        block = build_dynamic_context_block(timezone="Mars/Olympus_Mons", now=_NOW)
        assert "local time" not in block
        assert "Current UTC time:" in block

    async def test_location_line_when_shared(self):
        block = build_dynamic_context_block(location="Madrid, Spain", now=_NOW)
        assert "User's approximate location: Madrid, Spain" in block

    async def test_no_location_line_by_default(self):
        block = build_dynamic_context_block(now=_NOW)
        assert "location" not in block


class TestGeocodingFormat:
    async def test_city_and_country(self):
        from app.services.geocoding import format_city

        assert format_city({"address": {"city": "Madrid", "country": "Spain"}}) == "Madrid, Spain"

    async def test_town_fallback(self):
        from app.services.geocoding import format_city

        assert format_city({"address": {"town": "Ronda", "country": "Spain"}}) == "Ronda, Spain"

    async def test_country_only(self):
        from app.services.geocoding import format_city

        assert format_city({"address": {"country": "Spain"}}) == "Spain"

    async def test_nothing_useful_returns_none(self):
        from app.services.geocoding import format_city

        assert format_city({}) is None
        assert format_city({"address": {}}) is None


class TestRoomsParity:
    async def test_room_agent_system_prompt_carries_context_block(self, db_session):
        """Room agents get the same <context> block — but UTC-only: a room
        has several humans, so no single member's timezone/location fits."""
        import uuid

        from app.models.room import RoomAgent
        from app.services.room_chat_service import RoomChatService
        from app.services.room_service import RoomService

        service = RoomService(db_session)
        room = await service.create(owner_id="test@example.com", name="Ctx room")
        db_session.add(
            RoomAgent(
                id=str(uuid.uuid4()),
                room_id=room.id,
                name="Echo",
                provider="fake",
                model="fake-model",
                response_mode="always",
            )
        )
        await db_session.commit()
        room = await service.get(room.id)

        messages = RoomChatService(db_session)._build_llm_history(room, room.agents[0], [])

        assert messages[0].role == "system"
        assert "<context>" in messages[0].content
        assert "Current UTC time:" in messages[0].content
        assert "local time" not in messages[0].content
        assert "location" not in messages[0].content


@pytest.fixture(autouse=True)
def _no_background_title(monkeypatch):
    """Same rationale as test_conversation_thinking_level.py: keep the
    first-exchange auto-title task off the real DATABASE_URL engine."""
    monkeypatch.setattr(ChatService, "_spawn_title_generation", lambda *a, **k: None)


_TEST_SETTINGS = Settings(
    secret_key="test-secret-key-do-not-use-in-prod",
    database_url="sqlite+aiosqlite:///:memory:",
    access_token_expire_minutes=30,
)

OWNER = "test@example.com"  # seeded by conftest


class _RecordingProvider(LLMProvider):
    """Streams one reply and records the messages each call received."""

    def __init__(self):
        self.received_messages: list[list[LLMMessage]] = []

    @property
    def name(self) -> str:
        return "ctx-recording"

    async def stream_chat(
        self,
        messages: list[LLMMessage],
        model: str,
        options: ChatOptions | None = None,
        cancel_event=None,
        tools=None,
    ) -> AsyncIterator[ChatChunk]:
        self.received_messages.append(messages)
        yield ChatChunk(content="hi", is_finished=False)
        yield ChatChunk(content="", is_finished=True, metadata={"tokens_generated": 1})

    async def chat(self, messages, model, options=None, tools=None) -> str:
        return ""

    async def list_models(self) -> list[ModelInfo]:
        return []

    async def health_check(self) -> bool:
        return True


class TestChatTurnEndToEnd:
    """The block as the provider actually receives it on a real chat turn."""

    def _install(self, db_session, provider):
        async def _override_db():
            yield db_session

        async def _override_user():
            return {"email": OWNER, "token_payload": {}}

        app.dependency_overrides[get_db] = _override_db
        app.dependency_overrides[get_settings] = lambda: _TEST_SETTINGS
        app.dependency_overrides[get_current_user] = _override_user
        ProviderRegistry.register(provider)
        app.dependency_overrides[get_chat_service] = lambda: ChatService(
            db_session, provider_name=provider.name
        )

    def _clear(self):
        for dep in (get_db, get_settings, get_current_user, get_chat_service):
            app.dependency_overrides.pop(dep, None)

    async def _set_user_context(self, db_session, timezone, location):
        user = (await db_session.execute(select(User).where(User.email == OWNER))).scalar_one()
        user.timezone = timezone
        user.location = location
        await db_session.commit()

    async def _send_turn(self, db_session, provider, conversation_patch=None) -> str:
        """POST one message and return the system prompt the provider saw.

        ``conversation_patch`` is applied via PATCH after creation — the
        create schema deliberately doesn't accept fields like enabled_tools.
        """
        self._install(db_session, provider)
        try:
            client = AsyncClient(transport=ASGITransport(app=app), base_url="http://test")
            async with client as c:
                resp = await c.post(
                    "/api/v1/chat/conversations",
                    json={"title": "Ctx"},
                )
                assert resp.status_code == 201, resp.text
                conv = resp.json()
                if conversation_patch:
                    resp = await c.patch(
                        f"/api/v1/chat/conversations/{conv['id']}",
                        json=conversation_patch,
                    )
                    assert resp.status_code == 200, resp.text
                resp = await c.post(
                    f"/api/v1/chat/conversations/{conv['id']}/chat",
                    json={"message": "hi"},
                    headers={"Accept": "text/event-stream"},
                )
                assert resp.status_code == 200
        finally:
            self._clear()

        assert len(provider.received_messages) == 1
        messages = provider.received_messages[0]
        assert messages[0].role == "system"
        return messages[0].content

    async def test_block_present_with_timezone_and_location(self, db_session):
        await self._set_user_context(db_session, "Europe/Madrid", "Madrid, Spain")
        prompt = await self._send_turn(db_session, _RecordingProvider())
        assert "<context>" in prompt and "</context>" in prompt
        assert "Current UTC time:" in prompt
        assert "(Europe/Madrid)" in prompt
        assert "User's approximate location: Madrid, Spain" in prompt

    async def test_location_line_absent_when_sharing_disabled(self, db_session):
        """location=NULL is the settings toggle's off state — the block still
        carries the times but must not mention location at all."""
        await self._set_user_context(db_session, "Europe/Madrid", None)
        prompt = await self._send_turn(db_session, _RecordingProvider())
        assert "<context>" in prompt
        assert "User's local time:" in prompt
        assert "location" not in prompt

    async def test_utc_only_when_user_never_reported_anything(self, db_session):
        await self._set_user_context(db_session, None, None)
        prompt = await self._send_turn(db_session, _RecordingProvider())
        assert "Current UTC time:" in prompt
        assert "local time" not in prompt
        assert "location" not in prompt

    async def test_app_help_nudge_present_when_tools_enabled(self, db_session):
        """Default conversations (all tools) tell the model app_help exists
        (IDEAS.md idea 4.3); it must ride along with the context block."""
        prompt = await self._send_turn(db_session, _RecordingProvider())
        assert "app_help" in prompt

    async def test_app_help_nudge_absent_when_tools_disabled(self, db_session):
        """enabled_tools=[] opts out of all tools — nudging toward a tool
        the model cannot call would only produce failed calls."""
        prompt = await self._send_turn(
            db_session, _RecordingProvider(), conversation_patch={"enabled_tools": []}
        )
        assert "app_help" not in prompt


class TestSystemPromptComposition:
    async def _make_service(self, db_session):
        svc = ChatService(db_session)

        async def _empty(*_args, **_kwargs):
            return []

        svc._memories.get_relevant_memories = _empty  # type: ignore[assignment]
        return svc

    async def test_block_appended_after_base_prompt(self, db_session):
        svc = await self._make_service(db_session)
        block = build_dynamic_context_block(timezone="Europe/Madrid", now=_NOW)
        prompt, _stats = await svc._context.build_system_prompt(
            user_id="test@example.com",
            use_memory=False,
            use_knowledge_base=False,
            conversation_system_prompt="You are a pirate.",
            dynamic_context=block,
        )
        assert prompt.startswith("You are a pirate.")
        assert prompt.endswith("</context>")
        assert "Europe/Madrid" in prompt

    async def test_block_alone_needs_no_fallback_prompt(self, db_session):
        """Unlike memories/KB, the block must not drag in the generic
        'You are a helpful AI assistant.' base prompt."""
        svc = await self._make_service(db_session)
        block = build_dynamic_context_block(now=_NOW)
        prompt, _stats = await svc._context.build_system_prompt(
            user_id="test@example.com",
            use_memory=False,
            use_knowledge_base=False,
            dynamic_context=block,
        )
        assert prompt == block

    async def test_absent_when_not_provided(self, db_session):
        svc = await self._make_service(db_session)
        prompt, _stats = await svc._context.build_system_prompt(
            user_id="test@example.com",
            use_memory=False,
            use_knowledge_base=False,
            conversation_system_prompt="Base.",
        )
        assert "<context>" not in prompt
