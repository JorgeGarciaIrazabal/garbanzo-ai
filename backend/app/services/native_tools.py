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
import re
from datetime import datetime
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.services.app_help import search_help
from app.services.memory_service import MemoryService
from app.services.notification_service import NotificationService
from app.services.report_service import ReportService
from app.services.scheduled_action_service import ScheduledActionService

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Tool identifiers
# ---------------------------------------------------------------------------

NATIVE_GARBO_SERVER_ID = "__garbo__"

SCHEDULED_ACTION_TOOL = "scheduled_actions"
MEMORY_TOOL = "memories"
NOTIFICATION_TOOL = "notifications"
APP_HELP_TOOL = "app_help"
CREATE_ROOM_TOOL = "create_room"
SET_STYLE_TOOL = "set_conversation_style"
REPORT_TOOL = "submit_report"
READ_FILE_TOOL = "read_file"
LIST_FILES_TOOL = "list_files"
DELEGATE_WORKFLOW_TOOL = "delegate_workflow"

ALL_NATIVE_TOOLS = (
    SCHEDULED_ACTION_TOOL,
    MEMORY_TOOL,
    NOTIFICATION_TOOL,
    APP_HELP_TOOL,
    CREATE_ROOM_TOOL,
    SET_STYLE_TOOL,
    REPORT_TOOL,
    # In the registry (so it can execute) but only advertised when a folder is
    # attached — see _GATED_TOOLS.
    DELEGATE_WORKFLOW_TOOL,
)

# Folder tools are *client-served*, not registry executors: they're advertised
# only when the desktop client signals it has a folder attached
# (``ChatRequest.has_client_folder``), and when the model calls them the backend
# delegates the read back to that client via ``ClientToolBridge`` — the backend
# never touches the host filesystem. Their descriptors live here (for
# advertising) but their execution is routed in ``chat_service`` (see
# ``folder_tool_descriptors`` / ``_execute_client_folder_tool``).
FOLDER_TOOLS = frozenset({READ_FILE_TOOL, LIST_FILES_TOOL})

# Tools that return an action *proposal* instead of executing. The LLM never
# performs these actions: the executor validates the arguments and returns a
# structured proposal; the frontend renders it as a Confirm/Cancel card and,
# on confirm, calls the same REST endpoints it uses everywhere else (reusing
# auth and keeping the model out of the execution path).
PROPOSAL_TOOLS = (CREATE_ROOM_TOOL, SET_STYLE_TOOL, DELEGATE_WORKFLOW_TOOL)

# Tools that execute in-process but are only *advertised* under a condition,
# so they stay out of the default descriptor list. ``delegate_workflow``
# needs an attached folder to snapshot, so it appears only alongside the
# folder tools (see ``workflow_tool_descriptors``).
_GATED_TOOLS = frozenset({DELEGATE_WORKFLOW_TOOL})

# Appended to the system prompt when app_help is available. Models reliably
# call tools they were told exist; without the nudge, "how do I…" questions
# about the app get hallucinated UI instead of a lookup.
APP_HELP_NUDGE = (
    "You are running inside the Garbanzo AI app. When the user asks how to "
    "use the app — how to do something in it, where a feature or setting "
    "lives, or what a feature is — call the app_help tool and answer from "
    "what it returns instead of guessing."
)

# Appended when a folder is attached. Without it, models either grind through
# dozens of read_file calls on a task that actually needs edits, or claim they
# changed files they have no way to write to.
DELEGATE_WORKFLOW_NUDGE = (
    "The user has attached a folder to this conversation. You can read from it "
    "with list_files/read_file, but you CANNOT modify it. When the user asks "
    "for work that would change files, or that needs many steps of reading and "
    "editing, call delegate_workflow to hand the task to an autonomous agent "
    "instead of attempting it yourself — it starts right away, and the user "
    "reviews every change before it touches their disk. Keep "
    "answering questions and small look-ups with read_file directly."
)


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
                "friend_updates_enabled": {
                    "type": "boolean",
                    "description": "Toggle for friend request/accept notifications (update_preferences only).",
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
            friend_updates_enabled=args.get("friend_updates_enabled"),
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
        "friend_updates_enabled": p.friend_updates_enabled,
    }


# ---------------------------------------------------------------------------
# App help tool
# ---------------------------------------------------------------------------

_APP_HELP_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": APP_HELP_TOOL,
        "description": (
            "Look up how to use THIS app (Garbanzo AI) in its built-in user "
            "guide. Use whenever the user asks how to do something in the app, "
            "where a feature or setting lives, or what a feature is — chat, "
            "styles, system prompts, memories, knowledge base, rooms, talk "
            "mode, notifications, scheduled actions, tools, micro-apps, "
            "settings, usage, admin. Returns the most relevant guide "
            "sections; answer from them and say so if nothing relevant comes "
            "back — do not invent UI. "
            "Examples: 'how do I pin a conversation?', 'where do I change the "
            "voice?', 'what are rooms?', 'how do I stop it using my documents?'."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": (
                        "The user's question about the app, e.g. 'how do I "
                        "mute a room'. Keep the feature words — they drive "
                        "the search."
                    ),
                },
            },
            "required": ["query"],
        },
    },
}


async def _execute_app_help(
    *,
    args: dict[str, Any],
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    """Search the built-in user guide. Read-only; db/user unused."""
    query = (args.get("query") or "").strip()
    if not query:
        return {"ok": False, "error": "query is required."}
    results = search_help(query)
    if not results:
        return {
            "ok": True,
            "query": query,
            "results": [],
            "note": (
                "No guide section matched. Tell the user the guide doesn't "
                "cover this rather than guessing."
            ),
        }
    return {"ok": True, "query": query, "results": results}


# ---------------------------------------------------------------------------
# Action-proposal tools (create_room, set_conversation_style)
# ---------------------------------------------------------------------------

_PROPOSAL_NOTE = (
    "This is a PROPOSAL only — nothing has been created or changed yet. The "
    "app is showing the user a confirmation card. Briefly summarize the "
    "proposal and ask them to confirm it there; do not claim the action "
    "happened."
)

# delegate_workflow is NOT confirmed by the user: the app starts the run as
# soon as this returns. The real gate is downstream — the diff is reviewed
# file-by-file before anything is written to disk — so a second "are you sure"
# up front would only add friction. The model must describe it as underway.
_DELEGATE_STARTED_NOTE = (
    "The workflow has STARTED — the app is uploading a copy of the folder and "
    "the agent is now working on it. Tell the user briefly that it's running "
    "and that a card in the chat shows live progress; they'll review the "
    "proposed file changes there when it finishes, and nothing is written to "
    "their disk until they do. Do NOT ask them to confirm anything, and do "
    "NOT claim the files have been changed yet."
)

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

_RESPONSE_MODES = ("always", "mention", "auto", "round_robin")
_THINKING_LEVELS = ("off", "low", "medium", "high")


def _proposal_result(
    kind: str,
    summary: str,
    payload: dict[str, Any],
    note: str = _PROPOSAL_NOTE,
) -> dict[str, Any]:
    return {
        "ok": True,
        "proposal": {"type": kind, "summary": summary, "payload": payload},
        "note": note,
    }


_CREATE_ROOM_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": CREATE_ROOM_TOOL,
        "description": (
            "Propose creating a multi-participant room (group chat with "
            "people and/or AI agents). Use when the user asks to set up a "
            "room, e.g. 'create a room with Ana and a research agent'. This "
            "does NOT create the room: it returns a proposal the user must "
            "confirm in the app. Members are existing account emails; each "
            "agent needs a name and a model."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "name": {
                    "type": "string",
                    "description": "Room name (required).",
                },
                "description": {
                    "type": "string",
                    "description": "Optional short room description.",
                },
                "member_emails": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Emails of people to invite (optional).",
                },
                "agents": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "model": {"type": "string"},
                            "system_prompt": {
                                "type": "string",
                                "description": "Optional persona for the agent.",
                            },
                            "response_mode": {
                                "type": "string",
                                "enum": list(_RESPONSE_MODES),
                                "description": "When the agent replies (default: mention).",
                            },
                            "is_moderator": {"type": "boolean"},
                        },
                        "required": ["name", "model"],
                    },
                    "description": "AI agents to add to the room (optional).",
                },
            },
            "required": ["name"],
        },
    },
}


async def _execute_create_room(
    *,
    args: dict[str, Any],
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    """Validate and return a create-room proposal. Never touches the DB."""
    name = (args.get("name") or "").strip()
    if not name:
        return {"ok": False, "error": "name is required."}
    if len(name) > 200:
        return {"ok": False, "error": "name must be at most 200 characters."}

    member_emails = args.get("member_emails") or []
    if not isinstance(member_emails, list):
        return {"ok": False, "error": "member_emails must be a list of emails."}
    member_emails = [str(e).strip().lower() for e in member_emails if str(e).strip()]
    invalid = [e for e in member_emails if not _EMAIL_RE.match(e)]
    if invalid:
        return {"ok": False, "error": f"Invalid member emails: {', '.join(invalid)}"}

    agents_in = args.get("agents") or []
    if not isinstance(agents_in, list):
        return {"ok": False, "error": "agents must be a list."}
    agents: list[dict[str, Any]] = []
    for raw in agents_in:
        if not isinstance(raw, dict):
            return {"ok": False, "error": "Each agent must be an object."}
        agent_name = (raw.get("name") or "").strip()
        model = (raw.get("model") or "").strip()
        if not agent_name or not model:
            return {"ok": False, "error": "Each agent needs a name and a model."}
        response_mode = raw.get("response_mode") or "mention"
        if response_mode not in _RESPONSE_MODES:
            return {
                "ok": False,
                "error": f"response_mode must be one of {', '.join(_RESPONSE_MODES)}.",
            }
        agents.append(
            {
                "name": agent_name,
                "model": model,
                "system_prompt": raw.get("system_prompt"),
                "response_mode": response_mode,
                "is_moderator": bool(raw.get("is_moderator", False)),
            }
        )

    parts = [f"Create room '{name}'"]
    if member_emails:
        parts.append(f"with {', '.join(member_emails)}")
    if agents:
        parts.append("and agent(s) " + ", ".join(f"{a['name']} ({a['model']})" for a in agents))
    payload = {
        "name": name,
        "description": (args.get("description") or "").strip() or None,
        "member_emails": member_emails,
        "agents": agents,
    }
    return _proposal_result(CREATE_ROOM_TOOL, " ".join(parts), payload)


_SET_STYLE_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": SET_STYLE_TOOL,
        "description": (
            "Propose changing this conversation's style: the model, the "
            "thinking level, and/or the system prompt. Use when the user "
            "asks to switch model ('use qwen for this chat'), change "
            "reasoning depth ('think harder'), or set a persona for the "
            "conversation. This does NOT apply the change: it returns a "
            "proposal the user must confirm in the app."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "model": {
                    "type": "string",
                    "description": "Model ID to switch this conversation to.",
                },
                "thinking_level": {
                    "type": "string",
                    "enum": list(_THINKING_LEVELS),
                    "description": "Reasoning depth for thinking-capable models.",
                },
                "system_prompt": {
                    "type": "string",
                    "description": "System prompt for this conversation.",
                },
            },
        },
    },
}


async def _execute_set_style(
    *,
    args: dict[str, Any],
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    """Validate and return a conversation-style proposal for the current
    conversation (the frontend knows which one it is showing)."""
    model = (args.get("model") or "").strip() or None
    thinking_level = args.get("thinking_level")
    system_prompt = (args.get("system_prompt") or "").strip() or None

    if thinking_level is not None and thinking_level not in _THINKING_LEVELS:
        return {
            "ok": False,
            "error": f"thinking_level must be one of {', '.join(_THINKING_LEVELS)}.",
        }
    if model is None and thinking_level is None and system_prompt is None:
        return {
            "ok": False,
            "error": "Provide at least one of model, thinking_level, or system_prompt.",
        }

    changes = []
    if model:
        changes.append(f"model → {model}")
    if thinking_level:
        changes.append(f"thinking → {thinking_level}")
    if system_prompt:
        changes.append("a new system prompt")
    payload = {
        "model": model,
        "thinking_level": thinking_level,
        "system_prompt": system_prompt,
    }
    return _proposal_result(
        SET_STYLE_TOOL, "Set conversation style: " + ", ".join(changes), payload
    )


# ---------------------------------------------------------------------------
# Submit report tool (bug / feature)
# ---------------------------------------------------------------------------

_REPORT_TYPES = ("bug", "feature")

_REPORT_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": REPORT_TOOL,
        "description": (
            "Submit a bug report or feature request about THIS app (Garbanzo "
            "AI) to its admins, straight from the conversation. Use when the "
            "user reports something broken or asks for a new capability, e.g. "
            "'report a bug: the mic button does nothing on Android' or 'can "
            "you request that talk mode support Portuguese?'. Write a concise "
            "title and a description that captures the details the user gave "
            "(what happened / what they want, steps, platform). Confirm the "
            "title and type with the user first if they are ambiguous. This "
            "files the report immediately — it is not a draft."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "type": {
                    "type": "string",
                    "enum": list(_REPORT_TYPES),
                    "description": "'bug' for something broken, 'feature' for a request.",
                },
                "title": {
                    "type": "string",
                    "description": "Short one-line summary (max 200 chars).",
                },
                "description": {
                    "type": "string",
                    "description": (
                        "Full details: what happened or what is wanted, plus "
                        "any steps, platform, or context the user provided."
                    ),
                },
            },
            "required": ["type", "title", "description"],
        },
    },
}


async def _execute_submit_report(
    *,
    args: dict[str, Any],
    db: AsyncSession,
    user_id: str,
) -> dict[str, Any]:
    """File a bug/feature report and notify admins — same path as the form."""
    type_ = (args.get("type") or "").strip().lower()
    if type_ not in _REPORT_TYPES:
        return {"ok": False, "error": f"type must be one of {', '.join(_REPORT_TYPES)}."}
    title = (args.get("title") or "").strip()
    if not title:
        return {"ok": False, "error": "title is required."}
    if len(title) > 200:
        return {"ok": False, "error": "title must be at most 200 characters."}
    description = (args.get("description") or "").strip()
    if not description:
        return {"ok": False, "error": "description is required."}
    if len(description) > 10000:
        return {"ok": False, "error": "description must be at most 10000 characters."}

    svc = ReportService(db)
    report = await svc.create(user_id=user_id, type_=type_, title=title, description=description)
    await svc.notify_admins(report)
    label = "Bug report" if type_ == "bug" else "Feature request"
    return {
        "ok": True,
        "report": {"id": report.id, "type": type_, "title": title, "status": report.status},
        "note": f"{label} filed and sent to the admins. Confirm this to the user.",
    }


# ---------------------------------------------------------------------------
# Folder tools (read_file, list_files) — client-served (idea 17)
# ---------------------------------------------------------------------------
# These are NOT registry executors: the attached folder lives only on the
# desktop client, so the backend advertises these descriptors (when the request
# sets has_client_folder) and delegates the actual read back to the client via
# ClientToolBridge. See chat_service._execute_client_folder_tool.

_READ_FILE_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": READ_FILE_TOOL,
        "description": (
            "Read a file from the folder the user attached to this "
            "conversation. Use it whenever the user refers to their files, a "
            "document, spreadsheet, PDF, or code in the attached folder. Paths "
            "are relative to the folder root (e.g. 'notes.md', "
            "'data/report.csv'); call list_files first if you don't know the "
            "path. Reads PDF, CSV, spreadsheets, Word/PowerPoint, HTML, and "
            "plain-text/source files. You can only read inside the attached "
            "folder — nothing outside it is accessible."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "File path relative to the attached folder root.",
                },
            },
            "required": ["path"],
        },
    },
}

_LIST_FILES_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": LIST_FILES_TOOL,
        "description": (
            "List the files and sub-folders inside the folder attached to this "
            "conversation. Call it to discover what's available before reading. "
            "Pass a sub-folder path (relative to the folder root) to list that "
            "directory, or omit it to list the root."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": (
                        "Sub-folder path relative to the attached folder root. "
                        "Omit or '.' for the root."
                    ),
                },
            },
            "required": [],
        },
    },
}


_DELEGATE_WORKFLOW_DESCRIPTOR: dict[str, Any] = {
    "type": "function",
    "function": {
        "name": DELEGATE_WORKFLOW_TOOL,
        "description": (
            "Propose handing a LARGE, multi-step task on the attached folder "
            "to an autonomous coding agent that works on its own for several "
            "minutes. Use this instead of read_file/list_files when the task "
            "would need many reads AND edits across several files — e.g. "
            "'refactor this module', 'add tests for the whole package', "
            "'migrate this project to the new API', 'find and fix every "
            "occurrence of X'. Do NOT use it for questions you can answer by "
            "reading one or two files, or for anything that only needs "
            "reading. Calling this STARTS the work immediately — no "
            "confirmation is asked. The app uploads a copy of the folder, the "
            "agent works on that copy, and the user reviews the resulting "
            "changes before anything is written back to their disk. "
            "Write the instruction as a complete, self-contained brief — the "
            "agent cannot see this conversation."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "instruction": {
                    "type": "string",
                    "description": (
                        "The full brief for the autonomous agent: what to "
                        "change, in which files or areas, and what 'done' "
                        "looks like. Self-contained — it has no access to "
                        "this conversation."
                    ),
                },
                "summary": {
                    "type": "string",
                    "description": (
                        "One short line shown on the confirmation card, e.g. "
                        "'Refactor the parser into three modules'."
                    ),
                },
            },
            "required": ["instruction"],
        },
    },
}


async def _execute_delegate_workflow(
    *,
    args: dict[str, Any],
    db: AsyncSession,  # noqa: ARG001 — proposal tools never touch the DB
    user_id: str,  # noqa: ARG001
) -> dict[str, Any]:
    """Validate and return a delegate-workflow proposal. Starts nothing."""
    instruction = (args.get("instruction") or "").strip()
    if not instruction:
        return {"ok": False, "error": "instruction is required."}
    if len(instruction) > 10000:
        return {"ok": False, "error": "instruction must be at most 10000 characters."}
    summary = (args.get("summary") or "").strip() or instruction[:120]
    return _proposal_result(
        DELEGATE_WORKFLOW_TOOL,
        summary,
        {"instruction": instruction},
        note=_DELEGATE_STARTED_NOTE,
    )


def workflow_tool_descriptors() -> list[dict[str, Any]]:
    """Descriptor for ``delegate_workflow`` (needs an attached folder)."""
    return [_DELEGATE_WORKFLOW_DESCRIPTOR]


def folder_tool_descriptors() -> list[dict[str, Any]]:
    """Descriptors for the client-served folder tools (read_file, list_files).

    Advertised only when a request sets ``has_client_folder``; execution is
    delegated to the desktop client in ``chat_service``.
    """
    return [_READ_FILE_DESCRIPTOR, _LIST_FILES_DESCRIPTOR]


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

_NATIVE_TOOL_REGISTRY: dict[str, tuple[dict[str, Any], Any]] = {
    SCHEDULED_ACTION_TOOL: (_SCHEDULED_ACTIONS_DESCRIPTOR, _execute_scheduled_actions),
    MEMORY_TOOL: (_MEMORY_TOOL_DESCRIPTOR, _execute_memories),
    NOTIFICATION_TOOL: (_NOTIFICATION_TOOL_DESCRIPTOR, _execute_notifications),
    APP_HELP_TOOL: (_APP_HELP_DESCRIPTOR, _execute_app_help),
    CREATE_ROOM_TOOL: (_CREATE_ROOM_DESCRIPTOR, _execute_create_room),
    SET_STYLE_TOOL: (_SET_STYLE_DESCRIPTOR, _execute_set_style),
    REPORT_TOOL: (_REPORT_DESCRIPTOR, _execute_submit_report),
    DELEGATE_WORKFLOW_TOOL: (_DELEGATE_WORKFLOW_DESCRIPTOR, _execute_delegate_workflow),
}


def native_tool_descriptors() -> list[dict[str, Any]]:
    """Descriptors for the always-available native tools.

    Gated tools (``delegate_workflow``) are excluded — they're appended by the
    caller when their precondition holds.
    """
    return [
        desc
        for name, (desc, _executor) in _NATIVE_TOOL_REGISTRY.items()
        if name not in _GATED_TOOLS
    ]


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
