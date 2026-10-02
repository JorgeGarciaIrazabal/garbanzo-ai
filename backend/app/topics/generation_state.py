"""Process-local generation state shared without importing chat services."""

import asyncio

active_streams: dict[str, asyncio.Event] = {}


def has_active_generation(conversation_id: str) -> bool:
    return conversation_id in active_streams
