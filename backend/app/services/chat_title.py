"""Conversation auto-titling: generate a short title from the first exchange."""

import logging
import re

from app.schemas.chat import ChatOptions
from app.services.llm_provider import LLMProvider
from app.services.llm_provider import Message as LLMMessage

logger = logging.getLogger(__name__)

_TITLE_PROMPT = (
    "Write a short title (3-5 words) for this conversation. "
    "Reply with ONLY the title — no quotes, no trailing punctuation, "
    "no explanation.\n\nUser: {user}\nAssistant: {assistant}"
)


def _clean_generated_title(raw: str) -> str:
    """Normalize an LLM-generated title to a single clean line."""
    text = raw.strip()
    # Defensive: some models inline reasoning despite the prompt.
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL).strip()
    first_line = next((ln.strip() for ln in text.splitlines() if ln.strip()), "")
    return first_line.strip("\"'`#* ").rstrip(".!,:;")[:60]


async def generate_conversation_title(
    provider: LLMProvider, model: str, user_text: str, assistant_text: str
) -> str:
    """Generate a 3-5 word conversation title; returns "" on empty output."""
    prompt = _TITLE_PROMPT.format(user=user_text[:500], assistant=assistant_text[:500])
    raw = await provider.chat(
        messages=[LLMMessage(role="user", content=prompt)],
        model=model,
        options=ChatOptions(temperature=0.3, max_tokens=30),
    )
    return _clean_generated_title(raw)


async def generate_and_persist_title(
    provider: LLMProvider,
    conversation_id: str,
    model: str,
    user_text: str,
    assistant_text: str,
) -> None:
    """Background task: generate and persist a title with its own session."""
    try:
        title = await generate_conversation_title(provider, model, user_text, assistant_text)
        if not title:
            return
        from app.db.session import async_session_maker
        from app.models.conversation import Conversation

        async with async_session_maker() as db:
            conversation = await db.get(Conversation, conversation_id)
            if conversation is not None:
                conversation.title = title
                await db.commit()
        logger.info("Auto-titled conversation %s: %r", conversation_id, title)
    except Exception as e:
        logger.warning("Title generation failed for %s: %s", conversation_id, e)
