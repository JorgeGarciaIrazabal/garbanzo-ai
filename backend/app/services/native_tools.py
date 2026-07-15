"""Native (in-process) chat tools for scheduled actions, memories, and notifications.

Each tool is described by a descriptor dict (OpenAI/Ollama function format)
and an async executor that takes ``args`` + ``db`` + ``user_id`` and returns a
result dict fed back to the LLM as the tool-call result.

These tools let the chat model directly manage the user's scheduled actions,
memories, and notifications without the user having to leave the conversation.
They work for every user in both dev and prod — no MCP server or admin
registration needed.
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.services.memory_service import MemoryService
from app.services.notification_service import NotificationService
from app.services.scheduled_action_service import ScheduledActionService

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Tool identifiers
# ---------------------------------------------------------------------------

NATIVE_GARBO_SERVER_ID = "__garbo__"

SCHEDULED_ACTION_TOOL = "scheduled_actions"
MEMORY_TOOL = "memories"
NOTIFICATION_TOOL = "notifications"

ALL_NATIVE_TOOLS = (SCHEDULED_ACTION_TOOL, MEMORY_TOOL, NOTIFICATION_TOOL)


# ---------------------------------------------------------------------------
# Scheduled Actions tool
# ---------------------------------------------------------------------------

_SCHEDULED_ACTIONS_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": SCHEDULED_ACTION_TOOL,
        "description": (
            "Create, list, update, delete, or view the user's scheduled actions "
            "(automated prompts that run on a cron schedule or at a specific "
            "datetime). When a scheduled action fires, the backend creates a new "
            "conversation with the prompt, streams an assistant reply, and sends "
            "the user a notification. Use this when the user wants to set up, "
            "review, modify, or remove automated/scheduled tasks. "
            "Actions:\n"
            "- list: Return all the user's scheduled actions.\n"
            "- get: Fetch a single action by id.\n"
            "- create: Create a new scheduled action.\n"
            "- update: Modify an existing action (partial update).\n"
            "- delete: Remove a scheduled action.\n"
            "Examples: 'remind me every Monday at 9am to review the roadmap', "
            "'schedule a daily standup summary at 8am', 'cancel my 5am reminder', "
            "'what scheduled actions do I have?'."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": ["list", "get", "create", "update", "delete"],
                    "description": "The CRUD operation to perform.",
                },
                "action_id": {
                    "type": "string",
                    "description": "ID of the scheduled action (required for get, update, delete).",
                },
                "prompt": {
                    "type": "string",
                    "description": (
                        "The prompt text for the scheduled action (required for "
                        "create, optional for update). This is what the assistant "
                        "will process when the action fires."
                    ),
                },
                "title": {
                    "type": "string",
                    "description": "Short label for the action (optional).",
                },
                "cron_expr": {
                    "type": "string",
                    "description": (
                        "5-field crontab expression for recurring actions, e.g. "
                        "'0 9 * * mon' (every Monday at 9am). Mutually exclusive "
                        "with run_at."
                    ),
                },
                "run_at": {
                    "type": "string",
                    "description": (
                        "ISO 8601 datetime for a one-off action, e.g. "
                        "'2025-12-25T10:00:00Z'. Mutually exclusive with cron_expr."
                    ),
                },
                "model": {
                    "type": "string",
                    "description": "Model ID to use (optional; defaults to the user's default).",
                },
                "system_prompt": {
                    "type": "string",
                    "description": "Custom system prompt for the action (optional).",
                },
                "is_active": {
                    "type": "boolean",
                    "description": "Whether the action is active (for create/update). Default: true.",
                },
            },
            "required": ["action"],
        },
    },
}


async def _execute_scheduled_actions(
    *,
    args: dict[str, Any],
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    """Execute a scheduled-actions CRUD operation."""
    action = args.get("action", "")
    svc = ScheduledActionService(db)

    if action == "list":
        items = await svc.list_for_user(user_id)
        return {
            "ok": True,
            "action": "list",
            "count": len(items),
            "actions": [_scheduled_action_to_dict(a) for a in items],
        }

    if action == "get":
        action_id = args.get("action_id")
        if not action_id:
            return {"ok": False, "error": "action_id is required for 'get'."}
        item = await svc.get(action_id, user_id)
        if item is None:
            return {"ok": False, "error": "Scheduled action not found."}
        return {"ok": True, "action": "get", "action_data": _scheduled_action_to_dict(item)}

    if action == "create":
        cron_expr = args.get("cron_expr")
        run_at_raw = args.get("run_at")
        run_at: datetime | None = None
        if run_at_raw:
            try:
                run_at = datetime.fromisoformat(run_at_raw.replace("Z", "+00:00"))
            except (ValueError, AttributeError) as exc:
                return {"ok": False, "error": f"Invalid run_at datetime: {exc}"}
        if not cron_expr and run_at is None:
            return {"ok": False, "error": "Provide exactly one of cron_expr or run_at."}
        if cron_expr and run_at is not None:
            return {"ok": False, "error": "Provide cron_expr OR run_at, not both."}
        prompt = args.get("prompt")
        if not prompt:
            return {"ok": False, "error": "prompt is required for 'create'."}
        try:
            item = await svc.create(
                user_id=user_id,
                prompt=prompt,
                title=args.get("title"),
                cron_expr=cron_expr,
                run_at=run_at,
                model=args.get("model"),
                system_prompt=args.get("system_prompt"),
                is_active=args.get("is_active", True),
            )
        except ValueError as exc:
            return {"ok": False, "error": str(exc)}

        # Register the APScheduler job so it fires on this running instance.
        try:
            from app.scheduler import register_scheduled_action

            register_scheduled_action(item)
        except Exception:
            logger.exception("Could not register scheduled action job")
        return {"ok": True, "action": "create", "action_data": _scheduled_action_to_dict(item)}

    if action == "update":
        action_id = args.get("action_id")
        if not action_id:
            return {"ok": False, "error": "action_id is required for 'update'."}
        cron_expr = args.get("cron_expr")
        run_at_raw = args.get("run_at")
        run_at: datetime | None = None
        if run_at_raw:
            try:
                run_at = datetime.fromisoformat(run_at_raw.replace("Z", "+00:00"))
            except (ValueError, AttributeError) as exc:
                return {"ok": False, "error": f"Invalid run_at datetime: {exc}"}
        set_cron = "cron_expr" in args
        set_run_at = "run_at" in args
        try:
            item = await svc.update(
                action_id=action_id,
                user_id=user_id,
                title=args.get("title"),
                prompt=args.get("prompt"),
                cron_expr=cron_expr,
                run_at=run_at,
                model=args.get("model"),
                system_prompt=args.get("system_prompt"),
                is_active=args.get("is_active"),
                set_cron=set_cron,
                set_run_at=set_run_at,
            )
        except ValueError as exc:
            return {"ok": False, "error": str(exc)}
        if item is None:
            return {"ok": False, "error": "Scheduled action not found."}

        # Sync the live scheduler job.
        try:
            from app.scheduler import register_scheduled_action, unregister_scheduled_action

            if item.is_active:
                register_scheduled_action(item)
            else:
                unregister_scheduled_action(item.id)
        except Exception:
            logger.exception("Could not sync scheduled action job")
        return {"ok": True, "action": "update", "action_data": _scheduled_action_to_dict(item)}

    if action == "delete":
        action_id = args.get("action_id")
        if not action_id:
            return {"ok": False, "error": "action_id is required for 'delete'."}
        deleted = await svc.delete(action_id, user_id)
        if not deleted:
            return {"ok": False, "error": "Scheduled action not found."}
        # Unregister the scheduler job.
        try:
            from app.scheduler import unregister_scheduled_action

            unregister_scheduled_action(action_id)
        except Exception:
            logger.exception("Could not unregister scheduled action job")
        return {"ok": True, "action": "delete", "action_id": action_id}

    return {"ok": False, "error": f"Unknown action: {action}"}


def _scheduled_action_to_dict(a: Any) -> dict[str, Any]:
    """Serialize a ScheduledAction ORM instance to a plain dict."""
    return {
        "id": a.id,
        "title": a.title,
        "prompt": a.prompt,
        "cron_expr": a.cron_expr,
        "run_at": a.run_at.isoformat() if a.run_at else None,
        "model": a.model,
        "is_active": a.is_active,
        "next_run": a.next_run.isoformat() if a.next_run else None,
        "last_run_at": a.last_run_at.isoformat() if a.last_run_at else None,
        "last_run_status": a.last_run_status,
        "created_at": a.created_at.isoformat() if a.created_at else None,
    }


# ---------------------------------------------------------------------------
# Memories tool
# ---------------------------------------------------------------------------

_MEMORY_TOOL_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": MEMORY_TOOL,
        "description": (
            "Store, list, edit, delete, or search the user's long-term memories. "
            "Memories are persistent facts/preferences about the user that are "
            "automatically injected into future chat context for personalization. "
            "Use this when the user explicitly asks to remember, recall, update, "
            "or forget something about themselves. "
            "Actions (use the 'operation' field):\n"
            "- list: Return all active memories.\n"
            "- get: Fetch a single memory by id.\n"
            "- create: Store a new memory.\n"
            "- update: Edit an existing memory's content or active status.\n"
            "- delete: Deactivate (soft-delete) a memory.\n"
            "Examples: 'remember that I prefer dark mode', 'what do you know about "
            "me?', 'update my timezone memory to PST', 'forget about my old address', "
            "'remind me what memories you have stored'."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "operation": {
                    "type": "string",
                    "enum": ["list", "get", "create", "update", "delete"],
                    "description": "The CRUD operation to perform.",
                },
                "memory_id": {
                    "type": "string",
                    "description": "ID of the memory (required for get, update, delete).",
                },
                "content": {
                    "type": "string",
                    "description": (
                        "The memory content text (required for create, optional for "
                        "update). 1-5000 characters."
                    ),
                },
                "is_active": {
                    "type": "boolean",
                    "description": "Active status (for update). Set false to deactivate.",
                },
                "source_conversation_id": {
                    "type": "string",
                    "description": "Optional: conversation ID this memory originated from (create only).",
                },
            },
            "required": ["operation"],
        },
    },
}


async def _execute_memories(
    *,
    args: dict[str, Any],
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    """Execute a memories CRUD operation."""
    operation = args.get("operation", "")
    svc = MemoryService(db)

    if operation == "list":
        items = await svc.get_active_memories(user_id)
        return {
            "ok": True,
            "operation": "list",
            "count": len(items),
            "memories": [_memory_to_dict(m) for m in items],
        }

    if operation == "get":
        memory_id = args.get("memory_id")
        if not memory_id:
            return {"ok": False, "error": "memory_id is required for 'get'."}
        item = await svc.get_memory(memory_id, user_id)
        if item is None:
            return {"ok": False, "error": "Memory not found."}
        return {"ok": True, "operation": "get", "memory": _memory_to_dict(item)}

    if operation == "create":
        content = args.get("content")
        if not content or not content.strip():
            return {"ok": False, "error": "content is required for 'create'."}
        item = await svc.create_memory(
            user_id=user_id,
            content=content.strip(),
            source_conversation_id=args.get("source_conversation_id"),
        )
        return {"ok": True, "operation": "create", "memory": _memory_to_dict(item)}

    if operation == "update":
        memory_id = args.get("memory_id")
        if not memory_id:
            return {"ok": False, "error": "memory_id is required for 'update'."}
        content = args.get("content")
        if content is not None:
            content = content.strip() if content.strip() else None
        is_active = args.get("is_active")
        if content is None and is_active is None:
            return {"ok": False, "error": "Provide at least one of content or is_active to update."}
        item = await svc.update_memory(
            memory_id=memory_id,
            user_id=user_id,
            content=content,
            is_active=is_active,
        )
        if item is None:
            return {"ok": False, "error": "Memory not found."}
        return {"ok": True, "operation": "update", "memory": _memory_to_dict(item)}

    if operation == "delete":
        memory_id = args.get("memory_id")
        if not memory_id:
            return {"ok": False, "error": "memory_id is required for 'delete'."}
        deactivated = await svc.deactivate_memory(memory_id, user_id)
        if not deactivated:
            return {"ok": False, "error": "Memory not found."}
        return {"ok": True, "operation": "delete", "memory_id": memory_id}

    return {"ok": False, "error": f"Unknown operation: {operation}"}


def _memory_to_dict(m: Any) -> dict[str, Any]:
    """Serialize a UserMemory ORM instance to a plain dict."""
    return {
        "id": m.id,
        "content": m.content,
        "is_active": m.is_active,
        "source_conversation_id": m.source_conversation_id,
        "created_at": m.created_at.isoformat() if m.created_at else None,
    }


# ---------------------------------------------------------------------------
# Notifications tool
# ---------------------------------------------------------------------------

_NOTIFICATION_TOOL_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": NOTIFICATION_TOOL,
        "description": (
            "Look into the user's notifications — list them, check unread count, "
            "mark them as read, or delete them. Also lets the user view and update "
            "their notification preferences. Use this when the user asks about "
            "their notifications, wants to check/clear them, or wants to change "
            "which notification channels are enabled. "
            "Actions (use the 'action' field):\n"
            "- list: Return the user's notifications (most recent first) with unread count.\n"
            "- unread_count: Return just the unread count.\n"
            "- mark_read: Mark a single notification as read (requires notification_id) "
            "or all if no id is given.\n"
            "- mark_all_read: Mark every notification as read.\n"
            "- delete: Delete a single notification (requires notification_id).\n"
            "- get_preferences: Show which notification channels are enabled.\n"
            "- update_preferences: Update notification channel toggles.\n"
            "Examples: 'do I have any unread notifications?', 'mark all my "
            "notifications as read', 'show me my notifications', 'turn off reminder "
            "notifications'."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": [
                        "list",
                        "unread_count",
                        "mark_read",
                        "mark_all_read",
                        "delete",
                        "get_preferences",
                        "update_preferences",
                    ],
                    "description": "The notification operation to perform.",
                },
                "notification_id": {
                    "type": "string",
                    "description": "ID of a specific notification (for mark_read, delete).",
                },
                "chat_responses_enabled": {
                    "type": "boolean",
                    "description": "Toggle for chat response notifications (update_preferences only).",
                },
                "reminders_enabled": {
                    "type": "boolean",
                    "description": "Toggle for reminder notifications (update_preferences only).",
                },
                "system_alerts_enabled": {
                    "type": "boolean",
                    "description": "Toggle for system alert notifications (update_preferences only).",
                },
            },
            "required": ["action"],
        },
    },
}


async def _execute_notifications(
    *,
    args: dict[str, Any],
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    """Execute a notifications operation."""
    action = args.get("action", "")
    svc = NotificationService(db)

    if action == "list":
        items = await svc.list_for_user(user_id)
        unread = await svc.unread_count(user_id)
        return {
            "ok": True,
            "action": "list",
            "count": len(items),
            "unread_count": unread,
            "notifications": [_notification_to_dict(n) for n in items],
        }

    if action == "unread_count":
        count = await svc.unread_count(user_id)
        return {"ok": True, "action": "unread_count", "unread_count": count}

    if action == "mark_read":
        notification_id = args.get("notification_id")
        if notification_id:
            ok = await svc.mark_read(user_id, notification_id)
            if not ok:
                return {"ok": False, "error": "Notification not found."}
            return {"ok": True, "action": "mark_read", "notification_id": notification_id}
        # No id → mark all as read
        count = await svc.mark_all_read(user_id)
        return {"ok": True, "action": "mark_all_read", "count": count}

    if action == "mark_all_read":
        count = await svc.mark_all_read(user_id)
        return {"ok": True, "action": "mark_all_read", "count": count}

    if action == "delete":
        notification_id = args.get("notification_id")
        if not notification_id:
            return {"ok": False, "error": "notification_id is required for 'delete'."}
        ok = await svc.delete(user_id, notification_id)
        if not ok:
            return {"ok": False, "error": "Notification not found."}
        return {"ok": True, "action": "delete", "notification_id": notification_id}

    if action == "get_preferences":
        prefs = await svc.get_preferences(user_id)
        return {"ok": True, "action": "get_preferences", "preferences": _prefs_to_dict(prefs)}

    if action == "update_preferences":
        prefs = await svc.update_preferences(
            user_id,
            chat_responses_enabled=args.get("chat_responses_enabled"),
            reminders_enabled=args.get("reminders_enabled"),
            system_alerts_enabled=args.get("system_alerts_enabled"),
        )
        return {"ok": True, "action": "update_preferences", "preferences": _prefs_to_dict(prefs)}

    return {"ok": False, "error": f"Unknown action: {action}"}


def _notification_to_dict(n: Any) -> dict[str, Any]:
    """Serialize a Notification ORM instance to a plain dict."""
    return {
        "id": n.id,
        "channel": n.channel,
        "title": n.title,
        "body": n.body,
        "is_read": n.is_read,
        "created_at": n.created_at.isoformat() if n.created_at else None,
        "data": n.data,
    }


def _prefs_to_dict(p: Any) -> dict[str, Any]:
    """Serialize NotificationPreferences ORM instance to a plain dict."""
    return {
        "chat_responses_enabled": p.chat_responses_enabled,
        "reminders_enabled": p.reminders_enabled,
        "system_alerts_enabled": p.system_alerts_enabled,
    }


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

_NATIVE_TOOL_REGISTRY: dict[str, tuple[dict[str, Any], Any]] = {
    SCHEDULED_ACTION_TOOL: (_SCHEDULED_ACTIONS_DESCRIPTOR, _execute_scheduled_actions),
    MEMORY_TOOL: (_MEMORY_TOOL_DESCRIPTOR, _execute_memories),
    NOTIFICATION_TOOL: (_NOTIFICATION_TOOL_DESCRIPTOR, _execute_notifications),
}


def native_tool_descriptors() -> list[dict[str, Any]]:
    """Return the Ollama/OpenAI tool descriptors for all native tools."""
    return [desc for desc, _executor in _NATIVE_TOOL_REGISTRY.values()]


def native_tool_lookup() -> dict[str, tuple[str, str]]:
    """Return the function-name → (server_id, tool_name) lookup map."""
    return {name: (NATIVE_GARBO_SERVER_ID, name) for name in _NATIVE_TOOL_REGISTRY}


async def execute_native_tool(
    *,
    name: str,
    args: dict[str, Any],
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    """Dispatch a native tool call by name.

    Returns ``{"ok": False, "error": "..."}`` for unknown tools.
    """
    entry = _NATIVE_TOOL_REGISTRY.get(name)
    if entry is None:
        return {"ok": False, "error": f"Unknown native tool: {name}"}
    _descriptor, executor = entry
    try:
        return await executor(args=args, db=db, user_id=user_id)
    except Exception as exc:
        logger.exception("Native tool '%s' failed", name)
        return {"ok": False, "error": str(exc)}
