"""Job executed by APScheduler for a user-defined scheduled action."""

from __future__ import annotations

import logging

from app.core.config import get_settings
from app.db.session import async_session_maker
from app.services.chat_service import ChatService
from app.services.conversation_service import ConversationService
from app.services.fcm_service import send_to_user
from app.services.scheduled_action_service import (
    ScheduledActionService,
    compute_next_run,
)

logger = logging.getLogger(__name__)


async def run_scheduled_action(action_id: str) -> None:
    """Execute a single scheduled action by ID.

    Creates a new conversation seeded with the action's prompt, streams the
    assistant reply, notifies the user, and records the run result.
    """
    logger.info("Running scheduled action %s", action_id)
    async with async_session_maker() as db:
        actions_svc = ScheduledActionService(db)
        action = await actions_svc.get_any(action_id)
        if action is None:
            logger.warning("Scheduled action %s disappeared before running", action_id)
            return
        if not action.is_active:
            logger.info("Scheduled action %s is inactive; skipping", action_id)
            return

        user_id = action.user_id
        prompt_text = action.prompt
        title = action.title or (prompt_text[:50] + ("..." if len(prompt_text) > 50 else ""))

        convs = ConversationService(db)
        conversation = await convs.create(
            user_id=user_id,
            title=f"⏰ {title}",
            model=action.model or get_settings().default_model,
            system_prompt=action.system_prompt,
        )

        chat = ChatService(db)
        status_label = "success"
        last_assistant_excerpt = ""
        try:
            async for chunk in chat.send_message(
                conversation_id=conversation.id,
                user_id=user_id,
                content=prompt_text,
            ):
                if chunk.content and not chunk.is_thinking:
                    last_assistant_excerpt += chunk.content
                if chunk.is_finished and chunk.metadata and chunk.metadata.get("error"):
                    status_label = "error"
        except Exception:
            logger.exception("Scheduled action %s failed to stream", action_id)
            status_label = "error"

        next_run = None
        if action.cron_expr:
            try:
                next_run = compute_next_run(action.cron_expr, None)
            except Exception:
                logger.exception("Could not compute next_run for %s", action_id)

        await actions_svc.record_run(
            action_id=action_id,
            status_label=status_label,
            next_run=next_run,
        )

        # Fire a notification that deep-links to the new conversation.
        body = (last_assistant_excerpt or prompt_text).strip()
        if len(body) > 200:
            body = body[:200] + "…"
        try:
            await send_to_user(
                db,
                user_id,
                title=title or "Scheduled reminder",
                body=body,
                channel="reminders",
                data={
                    "conversation_id": conversation.id,
                    "scheduled_action_id": action_id,
                },
            )
        except Exception:
            logger.exception("Failed to send notification for scheduled action %s", action_id)

    logger.info("Scheduled action %s finished (%s)", action_id, status_label)
