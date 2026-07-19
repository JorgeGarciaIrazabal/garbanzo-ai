"""Service for extracting user memories from conversations using LLM."""

import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.conversation import Conversation
from app.models.memory import UserMemory
from app.models.message import Message
from app.schemas.chat import ChatOptions
from app.services.llm_provider import (
    LLMProvider,
    ProviderRegistry,
    resolve_context_length,
)
from app.services.llm_provider import Message as LLMMessage
from app.services.memory_service import MemoryService

logger = logging.getLogger(__name__)

# Default extraction prompt
EXTRACTION_PROMPT = """You are an assistant that extracts memorable facts about a user from their conversation history.

Analyze the conversation messages and identify facts about the user that are worth remembering for future interactions. Focus on:
- Personal preferences (likes, dislikes, favorite things)
- Goals and objectives
- Work or role information
- Skills and expertise
- Important life events or circumstances
- Communication style preferences
- Recurring themes or concerns

Format your response as a JSON array of memory objects, each with a "content" field containing a concise, factual statement about the user.

Example output:
[
  {{"content": "User works as a software engineer specializing in backend development"}},
  {{"content": "User prefers concise, direct answers with code examples"}},
  {{"content": "User is learning Spanish and practices conversation regularly"}}
]

If no memorable facts are found, return an empty array [].

Conversation messages:
{messages}

Extract memories:"""


class MemoryExtractionService:
    """Handles LLM-based extraction of user memories from conversations."""

    def __init__(self, db: AsyncSession, provider_name: str = "ollama"):
        self.db = db
        self._provider_name = provider_name
        self._memory_service = MemoryService(db)

    def _get_provider(self) -> LLMProvider:
        """Get the LLM provider."""
        provider = ProviderRegistry.get(self._provider_name)
        if provider is None:
            raise ValueError(f"Unknown provider: {self._provider_name}")
        return provider

    async def fetch_recent_conversations(
        self,
        user_id: str,
        hours: int = 24,
        limit: int = 10,
    ) -> list[Conversation]:
        """Fetch user's recent conversations from the last N hours."""
        cutoff = datetime.now(UTC) - timedelta(hours=hours)

        query = (
            select(Conversation)
            .where(
                Conversation.user_id == user_id,
                Conversation.is_deleted == False,  # noqa: E712
                Conversation.updated_at >= cutoff,
            )
            .order_by(Conversation.updated_at.desc())
            .limit(limit)
        )

        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def fetch_conversation_messages(
        self,
        conversation_id: str,
        limit: int = 50,
    ) -> list[Message]:
        """Fetch messages from a conversation."""
        query = (
            select(Message)
            .where(Message.conversation_id == conversation_id)
            .order_by(Message.created_at.asc())
            .limit(limit)
        )

        result = await self.db.execute(query)
        return list(result.scalars().all())

    def _format_messages_for_prompt(self, messages: list[Message]) -> str:
        """Format messages as a string for the LLM prompt."""
        formatted = []
        for msg in messages:
            role = msg.role.capitalize()
            formatted.append(f"{role}: {msg.content}")
        return "\n".join(formatted)

    async def extract_memories_from_conversations(
        self,
        user_id: str,
        conversations: list[Conversation],
        model: str | None = None,
    ) -> list[str]:
        """Use LLM to extract memories from a list of conversations.

        Returns a list of memory content strings.
        """
        model = model or get_settings().default_model
        if not conversations:
            return []

        # Gather all messages from conversations
        all_messages_text = []
        source_conversation_ids = []

        for conv in conversations:
            messages = await self.fetch_conversation_messages(conv.id)
            if messages:
                all_messages_text.append(self._format_messages_for_prompt(messages))
                source_conversation_ids.append(conv.id)

        if not all_messages_text:
            return []

        # Combine all conversation texts
        combined_messages = "\n\n---\n\n".join(all_messages_text)

        # Build the prompt
        prompt = EXTRACTION_PROMPT.format(messages=combined_messages)

        # Create LLM message
        llm_message = LLMMessage(role="user", content=prompt)

        # Call LLM. The prompt bundles a full day of conversation text, so
        # allocate the effective window rather than the runtime default.
        provider = self._get_provider()
        try:
            num_ctx = await resolve_context_length(provider, model)
            response = await provider.chat(
                messages=[llm_message],
                model=model,
                options=ChatOptions(temperature=0.3, max_tokens=1000, num_ctx=num_ctx),
            )
        except Exception as e:
            logger.error("Failed to extract memories: %s", e)
            return []

        # Parse the response as JSON
        import json

        try:
            extracted = json.loads(response.strip())
            if isinstance(extracted, list):
                memories = [
                    item.get("content", "").strip()
                    for item in extracted
                    if isinstance(item, dict) and item.get("content")
                ]
                return memories
            elif isinstance(extracted, dict) and extracted.get("memories"):
                memories = [
                    item.get("content", "").strip()
                    for item in extracted["memories"]
                    if isinstance(item, dict) and item.get("content")
                ]
                return memories
        except json.JSONDecodeError:
            logger.warning("LLM response was not valid JSON: %s", response[:200])
            # Fallback: treat each line as a potential memory
            lines = [line.strip() for line in response.split("\n") if line.strip()]
            return lines[:10]  # Limit to 10 memories

        return []

    async def extract_and_store_memories(
        self,
        user_id: str,
        hours: int = 24,
        model: str | None = None,
    ) -> list[UserMemory]:
        """Extract memories from recent conversations and store them.

        Returns the list of created memory records.
        """
        model = model or get_settings().default_model
        # Fetch recent conversations
        conversations = await self.fetch_recent_conversations(user_id, hours=hours)

        if not conversations:
            logger.info("No recent conversations for user %s", user_id)
            return []

        # Extract memories
        memory_contents = await self.extract_memories_from_conversations(
            user_id=user_id,
            conversations=conversations,
            model=model,
        )

        if not memory_contents:
            logger.info("No memories extracted for user %s", user_id)
            return []

        # Drop near-duplicates of what we already know — daily extraction
        # would otherwise re-learn "user works at Acme" forever.
        memory_contents, embeddings = await self._memory_service.filter_duplicate_candidates(
            user_id, memory_contents
        )
        if not memory_contents:
            logger.info("All extracted memories were duplicates for %s", user_id)
            return []

        # Store memories (link to the most recent conversation)
        source_conv_id = conversations[0].id if conversations else None
        created_memories = []

        for content, embedding in zip(memory_contents, embeddings, strict=True):
            memory = await self._memory_service.create_memory(
                user_id=user_id,
                content=content,
                source_conversation_id=source_conv_id,
                embedding=embedding,
            )
            created_memories.append(memory)

        logger.info(
            "Created %d memories for user %s from %d conversations",
            len(created_memories),
            user_id,
            len(conversations),
        )

        return created_memories

    async def extract_memories_for_all_users(
        self,
        hours: int = 24,
        model: str | None = None,
    ) -> dict[str, list[UserMemory]]:
        """Extract memories for all users with recent activity.

        Returns a dict mapping user_id to their created memories.
        """
        model = model or get_settings().default_model
        # Find all users with recent conversations
        cutoff = datetime.now(UTC) - timedelta(hours=hours)

        query = (
            select(Conversation.user_id)
            .where(
                Conversation.is_deleted == False,  # noqa: E712
                Conversation.updated_at >= cutoff,
            )
            .distinct()
        )

        result = await self.db.execute(query)
        user_ids = result.scalars().all()

        if not user_ids:
            logger.info("No users with recent conversations")
            return {}

        results: dict[str, list[UserMemory]] = {}

        for user_id in user_ids:
            try:
                memories = await self.extract_and_store_memories(
                    user_id=user_id,
                    hours=hours,
                    model=model,
                )
                results[user_id] = memories
            except Exception as e:
                logger.error("Failed to extract memories for user %s: %s", user_id, e)
                results[user_id] = []

        return results
