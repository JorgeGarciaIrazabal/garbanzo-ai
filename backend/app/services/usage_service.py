"""Aggregate per-user token usage from the messages.meta JSONB column.

Aggregation happens in Python rather than SQL so it works identically on
PostgreSQL (prod) and SQLite (tests). Usage rows per user are bounded by
message volume, which stays small enough for this to be a reasonable trade-off.
"""

from collections import defaultdict
from datetime import UTC, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conversation import Conversation
from app.models.message import Message
from app.schemas.usage import (
    UsageByConversation,
    UsageByDay,
    UsageByModel,
    UsageSummary,
)


def _as_int(value) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


class UsageService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def summary(self, user_email: str, days: int = 30) -> UsageSummary:
        days = max(1, min(days, 365))
        cutoff = datetime.now(UTC) - timedelta(days=days)

        q = (
            select(
                Message.id,
                Message.conversation_id,
                Message.meta,
                Message.created_at,
                Conversation.model,
                Conversation.title,
            )
            .select_from(Message)
            .join(Conversation, Message.conversation_id == Conversation.id)
            .where(
                Conversation.user_id == user_email,
                Message.role == "assistant",
                Message.created_at >= cutoff,
            )
        )
        rows = (await self.db.execute(q)).all()

        total_prompt = 0
        total_generated = 0
        total_messages = 0

        by_model: dict[str, dict[str, int]] = defaultdict(
            lambda: {"tokens_prompt": 0, "tokens_generated": 0, "message_count": 0}
        )
        by_conv: dict[str, dict] = {}
        by_day: dict[str, dict[str, int]] = defaultdict(
            lambda: {"tokens_prompt": 0, "tokens_generated": 0}
        )

        for _msg_id, conv_id, meta, created_at, model, title in rows:
            prompt_t = _as_int((meta or {}).get("tokens_prompt"))
            gen_t = _as_int((meta or {}).get("tokens_generated"))

            total_prompt += prompt_t
            total_generated += gen_t
            total_messages += 1

            model_key = model or "unknown"
            m = by_model[model_key]
            m["tokens_prompt"] += prompt_t
            m["tokens_generated"] += gen_t
            m["message_count"] += 1

            c = by_conv.setdefault(
                conv_id,
                {
                    "conversation_id": conv_id,
                    "title": title,
                    "tokens_prompt": 0,
                    "tokens_generated": 0,
                    "message_count": 0,
                },
            )
            c["tokens_prompt"] += prompt_t
            c["tokens_generated"] += gen_t
            c["message_count"] += 1

            day_key = (
                created_at.astimezone(UTC).date().isoformat()
                if created_at
                else datetime.now(UTC).date().isoformat()
            )
            d = by_day[day_key]
            d["tokens_prompt"] += prompt_t
            d["tokens_generated"] += gen_t

        by_model_list = sorted(
            (UsageByModel(model=name, **stats) for name, stats in by_model.items()),
            key=lambda x: x.tokens_generated,
            reverse=True,
        )
        by_conv_list = sorted(
            (UsageByConversation(**c) for c in by_conv.values()),
            key=lambda x: x.tokens_generated,
            reverse=True,
        )[:20]
        by_day_list = [UsageByDay(date=date, **stats) for date, stats in sorted(by_day.items())]

        return UsageSummary(
            days=days,
            total_tokens_prompt=total_prompt,
            total_tokens_generated=total_generated,
            total_messages=total_messages,
            by_model=by_model_list,
            by_conversation=by_conv_list,
            by_day=by_day_list,
        )
