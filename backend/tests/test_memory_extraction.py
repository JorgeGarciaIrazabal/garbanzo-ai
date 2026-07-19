"""Tests for MemoryExtractionService — LLM-based memory extraction from conversations."""

import json
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import hash_password
from app.models.conversation import Conversation
from app.models.message import Message
from app.models.user import User
from app.services.embedding_provider import (
    EmbeddingProvider,
    set_embedding_provider,
)
from app.services.llm_provider import LLMProvider, ProviderRegistry
from app.services.memory_extraction import MemoryExtractionService


@pytest.mark.asyncio
class TestMemoryExtractionServiceFetch:
    async def test_fetch_recent_conversations(self, db_session: AsyncSession):
        """Fetches user's non-deleted conversations from the last N hours."""
        await self._seed_user(db_session, "alice@example.com")
        now = datetime.now(UTC)

        # Recent conversation
        conv1 = Conversation(
            id="conv-1",
            user_id="alice@example.com",
            title="Recent",
            updated_at=now - timedelta(hours=2),
        )
        # Old conversation (outside window)
        conv2 = Conversation(
            id="conv-2",
            user_id="alice@example.com",
            title="Old",
            updated_at=now - timedelta(hours=48),
        )
        # Deleted conversation
        conv3 = Conversation(
            id="conv-3",
            user_id="alice@example.com",
            title="Deleted",
            updated_at=now - timedelta(hours=1),
            is_deleted=True,
        )
        db_session.add_all([conv1, conv2, conv3])
        await db_session.commit()

        svc = MemoryExtractionService(db_session)
        convs = await svc.fetch_recent_conversations("alice@example.com", hours=24, limit=10)

        assert len(convs) == 1
        assert convs[0].id == "conv-1"

    async def test_fetch_conversation_messages(self, db_session: AsyncSession):
        """Fetches messages ordered by creation time."""
        await self._seed_user(db_session, "alice@example.com")
        conv = Conversation(id="conv-1", user_id="alice@example.com", title="Test")
        db_session.add(conv)
        await db_session.commit()

        msg1 = Message(id="m1", conversation_id="conv-1", role="user", content="Hello")
        msg2 = Message(id="m2", conversation_id="conv-1", role="assistant", content="Hi there")
        msg3 = Message(id="m3", conversation_id="conv-1", role="user", content="How are you?")
        db_session.add_all([msg1, msg2, msg3])
        await db_session.commit()

        svc = MemoryExtractionService(db_session)
        messages = await svc.fetch_conversation_messages("conv-1", limit=50)

        assert len(messages) == 3
        assert messages[0].content == "Hello"
        assert messages[1].content == "Hi there"
        assert messages[2].content == "How are you?"

    async def test_format_messages_for_prompt(self, db_session: AsyncSession):
        """Formats messages as 'Role: content' lines."""
        svc = MemoryExtractionService(db_session)
        messages = [
            Message(id="1", conversation_id="c1", role="user", content="Hello"),
            Message(id="2", conversation_id="c1", role="assistant", content="Hi!"),
        ]
        formatted = svc._format_messages_for_prompt(messages)
        assert formatted == "User: Hello\nAssistant: Hi!"

    async def _seed_user(self, db: AsyncSession, email: str):
        db.add(User(email=email, hashed_password=hash_password("pw")))
        await db.commit()


@pytest.mark.asyncio
class TestMemoryExtractionServiceExtract:
    async def test_extract_memories_returns_parsed_json(self, db_session: AsyncSession):
        """LLM returns valid JSON array; service parses memories correctly."""
        await self._seed_user(db_session, "alice@example.com")
        conv = Conversation(id="conv-1", user_id="alice@example.com", title="Test")
        db_session.add(conv)
        # Add messages to DB
        db_session.add_all(
            [
                Message(id="1", conversation_id="conv-1", role="user", content="I love Python"),
                Message(id="2", conversation_id="conv-1", role="assistant", content="Nice!"),
            ]
        )
        await db_session.commit()

        # Mock the provider
        mock_provider = MagicMock(spec=LLMProvider)
        mock_provider.chat = AsyncMock(
            return_value=json.dumps(
                [
                    {"content": "User loves Python programming"},
                    {"content": "User prefers concise answers"},
                ]
            )
        )
        mock_provider.get_model_context_length = AsyncMock(return_value=8192)

        with patch.object(ProviderRegistry, "get", return_value=mock_provider):
            svc = MemoryExtractionService(db_session, provider_name="ollama")
            memories = await svc.extract_memories_from_conversations(
                user_id="alice@example.com",
                conversations=[conv],
                model="llama3.2",
            )

        assert len(memories) == 2
        assert "User loves Python programming" in memories
        assert "User prefers concise answers" in memories

    async def test_extract_memories_handles_dict_with_memories_key(self, db_session: AsyncSession):
        """LLM sometimes wraps array in {memories: [...]}. Service handles both."""
        await self._seed_user(db_session, "alice@example.com")
        conv = Conversation(id="conv-1", user_id="alice@example.com", title="Test")
        db_session.add(conv)
        db_session.add(Message(id="1", conversation_id="conv-1", role="user", content="test"))
        await db_session.commit()

        mock_provider = MagicMock(spec=LLMProvider)
        mock_provider.chat = AsyncMock(
            return_value=json.dumps(
                {
                    "memories": [
                        {"content": "Wrapped memory one"},
                        {"content": "Wrapped memory two"},
                    ]
                }
            )
        )
        mock_provider.get_model_context_length = AsyncMock(return_value=8192)

        with patch.object(ProviderRegistry, "get", return_value=mock_provider):
            svc = MemoryExtractionService(db_session, provider_name="ollama")
            memories = await svc.extract_memories_from_conversations(
                user_id="alice@example.com",
                conversations=[conv],
            )

        assert len(memories) == 2
        assert memories == ["Wrapped memory one", "Wrapped memory two"]

    async def test_extract_memories_invalid_json_fallback_to_lines(self, db_session: AsyncSession):
        """Invalid JSON falls back to line-by-line parsing."""
        await self._seed_user(db_session, "alice@example.com")
        conv = Conversation(id="conv-1", user_id="alice@example.com", title="Test")
        db_session.add(conv)
        db_session.add(Message(id="1", conversation_id="conv-1", role="user", content="test"))
        await db_session.commit()

        mock_provider = MagicMock(spec=LLMProvider)
        mock_provider.chat = AsyncMock(return_value="Memory one\nMemory two\n\nMemory three")
        mock_provider.get_model_context_length = AsyncMock(return_value=8192)

        with patch.object(ProviderRegistry, "get", return_value=mock_provider):
            svc = MemoryExtractionService(db_session, provider_name="ollama")
            memories = await svc.extract_memories_from_conversations(
                user_id="alice@example.com",
                conversations=[conv],
            )

        assert memories == ["Memory one", "Memory two", "Memory three"]

    async def test_extract_memories_empty_conversations_returns_empty(
        self, db_session: AsyncSession
    ):
        await self._seed_user(db_session, "alice@example.com")
        svc = MemoryExtractionService(db_session, provider_name="ollama")
        memories = await svc.extract_memories_from_conversations("alice@example.com", [])
        assert memories == []

    async def test_extract_memories_llm_error_returns_empty(self, db_session: AsyncSession):
        """LLM failure logs and returns empty list (no crash)."""
        await self._seed_user(db_session, "alice@example.com")
        conv = Conversation(id="conv-1", user_id="alice@example.com", title="Test")
        db_session.add(conv)
        await db_session.commit()

        mock_provider = MagicMock(spec=LLMProvider)
        mock_provider.chat = AsyncMock(side_effect=RuntimeError("Ollama down"))

        with patch.object(ProviderRegistry, "get", return_value=mock_provider):
            svc = MemoryExtractionService(db_session, provider_name="ollama")
            memories = await svc.extract_memories_from_conversations(
                user_id="alice@example.com",
                conversations=[conv],
            )

        assert memories == []

    async def _seed_user(self, db: AsyncSession, email: str):
        db.add(User(email=email, hashed_password=hash_password("pw")))
        await db.commit()


@pytest.mark.asyncio
class TestMemoryExtractionServiceStore:
    async def test_extract_and_store_creates_memories_with_embeddings(
        self, db_session: AsyncSession
    ):
        """Full flow: fetch convs -> extract -> filter dupes -> store with embeddings."""
        await self._seed_user(db_session, "alice@example.com")
        now = datetime.now(UTC)

        conv = Conversation(
            id="conv-1",
            user_id="alice@example.com",
            title="Work chat",
            updated_at=now,
        )
        db_session.add(conv)
        db_session.add(
            Message(id="m1", conversation_id="conv-1", role="user", content="I work at Acme")
        )
        await db_session.commit()

        # Mock LLM to return one memory
        mock_provider = MagicMock(spec=LLMProvider)
        mock_provider.chat = AsyncMock(
            return_value=json.dumps([{"content": "User works at Acme Corp"}])
        )
        mock_provider.get_model_context_length = AsyncMock(return_value=8192)

        # Mock embedding provider
        mock_embedder = MagicMock(spec=EmbeddingProvider)
        mock_embedder.dim = 384
        mock_embedder.embed = AsyncMock(return_value=[[0.1] * 384])

        # Override the global embedding provider for this test
        set_embedding_provider(mock_embedder)
        try:
            with patch.object(ProviderRegistry, "get", return_value=mock_provider):
                svc = MemoryExtractionService(db_session, provider_name="ollama")
                memories = await svc.extract_and_store_memories(
                    user_id="alice@example.com",
                    hours=24,
                    model="llama3.2",
                )

            assert len(memories) == 1
            assert memories[0].content == "User works at Acme Corp"
            assert memories[0].user_id == "alice@example.com"
            assert memories[0].source_conversation_id == "conv-1"
            assert memories[0].embedding is not None
        finally:
            set_embedding_provider(None)

    async def test_extract_and_store_filters_duplicates(self, db_session: AsyncSession):
        """Existing memories (exact or semantic) are not re-created."""
        await self._seed_user(db_session, "alice@example.com")

        # Pre-create a memory
        from app.services.memory_service import MemoryService

        mem_svc = MemoryService(db_session)
        await mem_svc.create_memory("alice@example.com", "User works at Acme")

        now = datetime.now(UTC)
        conv = Conversation(id="conv-1", user_id="alice@example.com", title="Chat", updated_at=now)
        db_session.add(conv)
        db_session.add(
            Message(id="m1", conversation_id="conv-1", role="user", content="I work at Acme")
        )
        await db_session.commit()

        # LLM extracts the same fact again
        mock_provider = MagicMock(spec=LLMProvider)
        mock_provider.chat = AsyncMock(return_value=json.dumps([{"content": "User works at Acme"}]))
        mock_provider.get_model_context_length = AsyncMock(return_value=8192)

        mock_embedder = MagicMock(spec=EmbeddingProvider)
        mock_embedder.dim = 384
        mock_embedder.embed = AsyncMock(return_value=[[0.1] * 384])

        set_embedding_provider(mock_embedder)
        try:
            with patch.object(ProviderRegistry, "get", return_value=mock_provider):
                svc = MemoryExtractionService(db_session, provider_name="ollama")
                memories = await svc.extract_and_store_memories(
                    user_id="alice@example.com",
                    hours=24,
                )

            assert memories == []  # Duplicate filtered out
        finally:
            set_embedding_provider(None)

    async def test_extract_and_store_no_conversations_returns_empty(self, db_session: AsyncSession):
        await self._seed_user(db_session, "alice@example.com")

        mock_provider = MagicMock(spec=LLMProvider)
        mock_provider.chat = AsyncMock(return_value=json.dumps([]))

        with patch.object(ProviderRegistry, "get", return_value=mock_provider):
            svc = MemoryExtractionService(db_session, provider_name="ollama")
            memories = await svc.extract_and_store_memories("alice@example.com", hours=24)
            assert memories == []

    async def _seed_user(self, db: AsyncSession, email: str):
        db.add(User(email=email, hashed_password=hash_password("pw")))
        await db.commit()


@pytest.mark.asyncio
class TestMemoryExtractionServiceAllUsers:
    async def test_extract_memories_for_all_users_processes_each(self, db_session: AsyncSession):
        """Finds all users with recent conversations and processes each."""
        await self._seed_users(
            db_session, ["alice@example.com", "bob@example.com", "carol@example.com"]
        )
        now = datetime.now(UTC)

        # Alice has recent convo
        conv_a = Conversation(id="a1", user_id="alice@example.com", title="A", updated_at=now)
        # Bob has recent convo
        conv_b = Conversation(id="b1", user_id="bob@example.com", title="B", updated_at=now)
        # Carol has NO recent convo (old)
        conv_c = Conversation(
            id="c1", user_id="carol@example.com", title="C", updated_at=now - timedelta(hours=48)
        )

        db_session.add_all([conv_a, conv_b, conv_c])
        # Add messages to recent conversations
        db_session.add_all(
            [
                Message(id="m1", conversation_id="a1", role="user", content="Hello"),
                Message(id="m2", conversation_id="b1", role="user", content="Hi"),
            ]
        )
        await db_session.commit()

        mock_provider = MagicMock(spec=LLMProvider)
        mock_provider.chat = AsyncMock(return_value=json.dumps([{"content": "Extracted memory"}]))
        mock_provider.get_model_context_length = AsyncMock(return_value=8192)

        mock_embedder = MagicMock(spec=EmbeddingProvider)
        mock_embedder.dim = 384
        mock_embedder.embed = AsyncMock(return_value=[[0.1] * 384])

        set_embedding_provider(mock_embedder)
        try:
            with patch.object(ProviderRegistry, "get", return_value=mock_provider):
                svc = MemoryExtractionService(db_session, provider_name="ollama")
                results = await svc.extract_memories_for_all_users(hours=24, model="llama3.2")

            assert "alice@example.com" in results
            assert "bob@example.com" in results
            assert "carol@example.com" not in results  # No recent convo

            assert len(results["alice@example.com"]) == 1
            assert len(results["bob@example.com"]) == 1
        finally:
            set_embedding_provider(None)

    async def test_extract_memories_for_all_users_continues_on_error(
        self, db_session: AsyncSession
    ):
        """One user's failure doesn't stop processing other users."""
        await self._seed_users(db_session, ["alice@example.com", "bob@example.com"])
        now = datetime.now(UTC)

        conv_a = Conversation(id="a1", user_id="alice@example.com", title="A", updated_at=now)
        conv_b = Conversation(id="b1", user_id="bob@example.com", title="B", updated_at=now)
        db_session.add_all([conv_a, conv_b])
        # Add messages
        db_session.add_all(
            [
                Message(id="m1", conversation_id="a1", role="user", content="Hello"),
                Message(id="m2", conversation_id="b1", role="user", content="Hi"),
            ]
        )
        await db_session.commit()

        # Alice's extraction succeeds, Bob's fails
        call_count = 0

        async def flaky_chat(*args, **kwargs):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return json.dumps([{"content": "Alice memory"}])
            raise RuntimeError("Bob's LLM down")

        mock_provider = MagicMock(spec=LLMProvider)
        mock_provider.chat = flaky_chat
        mock_provider.get_model_context_length = AsyncMock(return_value=8192)

        mock_embedder = MagicMock(spec=EmbeddingProvider)
        mock_embedder.dim = 384
        mock_embedder.embed = AsyncMock(return_value=[[0.1] * 384])

        set_embedding_provider(mock_embedder)
        try:
            with patch.object(ProviderRegistry, "get", return_value=mock_provider):
                svc = MemoryExtractionService(db_session, provider_name="ollama")
                results = await svc.extract_memories_for_all_users(hours=24)

            assert "alice@example.com" in results
            assert len(results["alice@example.com"]) == 1
            assert "bob@example.com" in results
            assert results["bob@example.com"] == []  # Failed user gets empty list
        finally:
            set_embedding_provider(None)

        assert "alice@example.com" in results
        assert len(results["alice@example.com"]) == 1
        assert "bob@example.com" in results
        assert results["bob@example.com"] == []  # Failed user gets empty list

    async def _seed_users(self, db: AsyncSession, emails: list[str]):
        for e in emails:
            db.add(User(email=e, hashed_password=hash_password("pw")))
        await db.commit()
