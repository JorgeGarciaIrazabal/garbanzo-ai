"""Service for system prompt templates and user default prompts."""

import logging
import uuid
from collections.abc import AsyncIterator

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models.system_prompt import SystemPromptTemplate
from app.models.user import User
from app.schemas.chat import ChatOptions
from app.services.llm_provider import ChatChunk, Message, ProviderRegistry

logger = logging.getLogger(__name__)


BUILTIN_TEMPLATES: list[dict[str, str]] = [
    {
        "name": "Coding Assistant",
        "description": "Focused, pragmatic software engineering helper.",
        "content": (
            "You are a senior software engineer. Give concise, correct, "
            "production-quality answers. Prefer minimal, idiomatic code. "
            "Explain tradeoffs briefly when relevant. When asked to write code, "
            "return only the code unless an explanation is requested."
        ),
    },
    {
        "name": "Writing Coach",
        "description": "Helps improve clarity, tone, and structure of writing.",
        "content": (
            "You are a thoughtful writing coach. Help the user improve their "
            "writing by suggesting clearer phrasing, better structure, and "
            "stronger openings/closings. Keep the author's voice. When asked "
            "to edit, show the revised version and a short note on what changed."
        ),
    },
    {
        "name": "Funny Friend",
        "description": "Casual, witty companion for light conversation.",
        "content": (
            "You are a witty, warm friend. Keep replies casual, playful, and "
            "genuinely engaged. Use light humor and callbacks where they fit. "
            "Be supportive, never mean-spirited. Keep it concise."
        ),
    },
    {
        "name": "Emotional Expert",
        "description": "Empathetic listener and emotional support guide.",
        "content": (
            "You are a compassionate, non-judgmental listener. Acknowledge "
            "feelings before offering perspective. Ask gentle follow-up "
            "questions. Never give medical diagnoses; suggest seeking a "
            "professional when appropriate. Keep the focus on the user's "
            "experience."
        ),
    },
    {
        "name": "Socratic Tutor",
        "description": "Teaches by asking guiding questions.",
        "content": (
            "You are a Socratic tutor. Rather than giving direct answers, "
            "ask guiding questions that help the user reason to the answer "
            "themselves. Confirm understanding after each step. Only give "
            "the full answer if explicitly asked."
        ),
    },
    {
        "name": "Brainstorm Partner",
        "description": "Generates varied ideas quickly.",
        "content": (
            "You are a creative brainstorming partner. Generate a wide range "
            "of ideas quickly — quantity over quality in the first pass. "
            "Group related ideas, flag the most promising ones, and suggest "
            "next steps for exploration."
        ),
    },
]


class SystemPromptService:
    """CRUD + defaults for system prompts and templates."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def seed_builtin_templates(self) -> int:
        """Insert any missing builtin templates. Returns count created."""
        existing_names = set(
            (
                await self.db.execute(
                    select(SystemPromptTemplate.name).where(
                        SystemPromptTemplate.is_builtin == True  # noqa: E712
                    )
                )
            )
            .scalars()
            .all()
        )

        created = 0
        for tpl in BUILTIN_TEMPLATES:
            if tpl["name"] in existing_names:
                continue
            self.db.add(
                SystemPromptTemplate(
                    id=str(uuid.uuid4()),
                    user_id=None,
                    name=tpl["name"],
                    description=tpl["description"],
                    content=tpl["content"],
                    is_builtin=True,
                )
            )
            created += 1

        if created:
            await self.db.commit()
            logger.info("Seeded %d builtin system prompt templates", created)
        return created

    async def list_templates(self, user_id: str) -> list[SystemPromptTemplate]:
        """Return templates visible to this user (builtins + their own)."""
        result = await self.db.execute(
            SystemPromptTemplate.visible_to(user_id).order_by(
                SystemPromptTemplate.is_builtin.desc(),
                SystemPromptTemplate.created_at.asc(),
            )
        )
        return list(result.scalars().all())

    async def get_template(self, template_id: str, user_id: str) -> SystemPromptTemplate | None:
        result = await self.db.execute(
            SystemPromptTemplate.visible_to(user_id).where(SystemPromptTemplate.id == template_id)
        )
        return result.scalar_one_or_none()

    async def create_template(
        self,
        user_id: str,
        name: str,
        content: str,
        description: str | None = None,
    ) -> SystemPromptTemplate:
        template = SystemPromptTemplate(
            id=str(uuid.uuid4()),
            user_id=user_id,
            name=name,
            description=description,
            content=content,
            is_builtin=False,
        )
        self.db.add(template)
        await self.db.commit()
        await self.db.refresh(template)
        return template

    async def update_template(
        self,
        template_id: str,
        user_id: str,
        name: str | None = None,
        description: str | None = None,
        content: str | None = None,
    ) -> SystemPromptTemplate | None:
        template = await self.get_template(template_id, user_id)
        if not template or template.is_builtin or template.user_id != user_id:
            return None

        if name is not None:
            template.name = name
        if description is not None:
            template.description = description
        if content is not None:
            template.content = content

        await self.db.commit()
        await self.db.refresh(template)
        return template

    async def delete_template(self, template_id: str, user_id: str) -> bool:
        template = await self.get_template(template_id, user_id)
        if not template or template.is_builtin or template.user_id != user_id:
            return False
        await self.db.delete(template)
        await self.db.commit()
        return True

    async def get_user_default_prompt(self, user_id: str) -> str | None:
        result = await self.db.execute(
            select(User.default_system_prompt).where(User.email == user_id)
        )
        return result.scalar_one_or_none()

    async def set_user_default_prompt(self, user_id: str, prompt: str | None) -> str | None:
        result = await self.db.execute(select(User).where(User.email == user_id))
        user = result.scalar_one_or_none()
        if not user:
            return None
        user.default_system_prompt = prompt or None
        await self.db.commit()
        return user.default_system_prompt

    # ---- AI-assisted generation -------------------------------------------

    _META_PROMPT_INITIAL = """\
You are a system-prompt engineer. The user describes what they want an AI assistant to do, and you write the system prompt that will shape its behavior.

Write a single, self-contained system prompt with the following structure (omit any section if the user's intent doesn't call for it):

1. **Persona**: One sentence defining who the assistant is.
2. **Tone**: How it should sound (concise, formal, playful, etc.).
3. **Constraints**: Rules, boundaries, or things to avoid.
4. **Output format**: If the user wants a specific response style (bullet points, code only, tables, etc.).

Guidelines:
- Write the prompt directly (second person "You are …"), not as a description of the prompt.
- Do NOT wrap the output in code fences or quotation marks.
- Do NOT include a preamble like "Here is the prompt:" — output only the prompt text.
- Keep it under 500 words unless the intent demands more detail.
- Be specific and concrete; avoid vague instructions like "be helpful".

User's intent:
{intent}
"""

    _META_PROMPT_REFINE = """\
You are a system-prompt engineer. The user has an existing system prompt and wants to refine it based on feedback.

Apply the feedback while preserving the overall structure and intent. Output ONLY the revised system prompt — no preamble, no code fences, no explanation.

Current system prompt:
{existing_prompt}

User's feedback:
{feedback}
"""

    async def generate_system_prompt(
        self,
        intent: str,
        existing_prompt: str | None = None,
        feedback: str | None = None,
        model: str | None = None,
    ) -> AsyncIterator[ChatChunk]:
        """Stream an AI-generated system prompt using the LLM provider.

        When ``existing_prompt`` + ``feedback`` are provided, the LLM revises
        the existing prompt rather than generating from scratch.
        """
        provider = ProviderRegistry.get(get_settings().llm_provider)
        if provider is None:
            raise RuntimeError("No LLM provider registered")
        llm_model = model or get_settings().default_model

        if existing_prompt and feedback:
            meta_prompt = self._META_PROMPT_REFINE.format(
                existing_prompt=existing_prompt,
                feedback=feedback,
            )
        elif existing_prompt and feedback is None:
            # Existing prompt without feedback — treat as a continuation/refine
            # with implicit "improve this" feedback.
            meta_prompt = self._META_PROMPT_REFINE.format(
                existing_prompt=existing_prompt,
                feedback="Improve this system prompt while keeping its intent.",
            )
        else:
            meta_prompt = self._META_PROMPT_INITIAL.format(intent=intent)

        messages = [Message(role="system", content=meta_prompt)]

        async for chunk in provider.stream_chat(
            messages=messages,
            model=llm_model,
            options=ChatOptions(temperature=0.7),
        ):
            yield chunk


async def seed_builtin_templates_task() -> None:
    """Run at startup to ensure builtin templates exist."""
    from app.db.session import async_session_maker

    async with async_session_maker() as db:
        svc = SystemPromptService(db)
        try:
            await svc.seed_builtin_templates()
        except Exception as e:
            logger.warning("Failed to seed builtin templates: %s", e)
