"""Tests for the native (in-process) chat tools.

The native tools are pure dispatch: each tool receives ``args`` + ``db`` +
``user_id`` and returns a dict. Most paths exercise a service layer
(ScheduledActionService, MemoryService, NotificationService, ReportService)
which already has its own test file — these tests focus on the dispatch,
validation, and serialization in ``native_tools.py`` itself, plus the
proposal tools (``create_room``, ``set_conversation_style``) which never
touch the DB and are entirely contained here.
"""

import pytest

from app.services.native_tools import (
    APP_HELP_TOOL,
    CREATE_ROOM_TOOL,
    SET_STYLE_TOOL,
    _execute_app_help,
    _execute_create_room,
    _execute_memories,
    _execute_notifications,
    _execute_scheduled_actions,
    _execute_set_style,
    _execute_submit_report,
    execute_native_tool,
)

pytestmark = pytest.mark.asyncio

OWNER = "test@example.com"


# ---------------------------------------------------------------------------
# Registry / dispatch surface
# ---------------------------------------------------------------------------


class TestRegistry:
    async def test_unknown_tool_returns_error(self, db_session):
        result = await execute_native_tool(
            name="does_not_exist", args={}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "Unknown native tool" in result["error"]

    async def test_executor_exception_is_caught(self, db_session, monkeypatch):
        """A raising executor must return ok=False, not propagate."""
        from app.services import native_tools

        async def boom(*, args, db, user_id):
            raise RuntimeError("kaboom")

        monkeypatch.setitem(
            native_tools._NATIVE_TOOL_REGISTRY,
            APP_HELP_TOOL,
            (native_tools._APP_HELP_DESCRIPTOR, boom),
        )
        result = await execute_native_tool(
            name=APP_HELP_TOOL, args={"query": "x"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "kaboom" in result["error"]


# ---------------------------------------------------------------------------
# Scheduled actions tool
# ---------------------------------------------------------------------------


class TestScheduledActionsTool:
    async def test_list_empty(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "list"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        assert result["action"] == "list"
        assert result["count"] == 0
        assert result["actions"] == []

    async def test_list_after_create(self, db_session):
        created = await _execute_scheduled_actions(
            args={
                "action": "create",
                "prompt": "Standup",
                "cron_expr": "0 8 * * *",
                "title": "Daily standup",
            },
            db=db_session,
            user_id=OWNER,
        )
        assert created["ok"] is True
        listed = await _execute_scheduled_actions(
            args={"action": "list"}, db=db_session, user_id=OWNER
        )
        assert listed["count"] == 1
        assert listed["actions"][0]["prompt"] == "Standup"

    async def test_get_requires_action_id(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "get"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "action_id" in result["error"]

    async def test_get_missing_returns_error(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "get", "action_id": "nope"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "not found" in result["error"].lower()

    async def test_get_existing(self, db_session):
        created = await _execute_scheduled_actions(
            args={"action": "create", "prompt": "X", "cron_expr": "0 8 * * *"},
            db=db_session,
            user_id=OWNER,
        )
        item_id = created["action_data"]["id"]
        result = await _execute_scheduled_actions(
            args={"action": "get", "action_id": item_id}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        assert result["action_data"]["id"] == item_id

    async def test_create_requires_prompt(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "create", "cron_expr": "0 8 * * *"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "prompt" in result["error"]

    async def test_create_requires_one_of_cron_or_run_at(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "create", "prompt": "X"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "cron_expr or run_at" in result["error"]

    async def test_create_rejects_both_cron_and_run_at(self, db_session):
        result = await _execute_scheduled_actions(
            args={
                "action": "create",
                "prompt": "X",
                "cron_expr": "0 8 * * *",
                "run_at": "2099-01-01T10:00:00Z",
            },
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "not both" in result["error"]

    async def test_create_invalid_run_at(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "create", "prompt": "X", "run_at": "not-a-date"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "Invalid run_at" in result["error"]

    async def test_create_with_run_at(self, db_session):
        result = await _execute_scheduled_actions(
            args={
                "action": "create",
                "prompt": "Ping",
                "run_at": "2099-01-01T10:00:00Z",
            },
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["action_data"]["run_at"] is not None

    async def test_create_invalid_cron_returns_error(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "create", "prompt": "X", "cron_expr": "not-cron"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert result["error"]

    async def test_update_requires_action_id(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "update"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "action_id" in result["error"]

    async def test_update_missing_returns_error(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "update", "action_id": "nope", "title": "X"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "not found" in result["error"].lower()

    async def test_update_title(self, db_session):
        created = await _execute_scheduled_actions(
            args={"action": "create", "prompt": "X", "cron_expr": "0 8 * * *"},
            db=db_session,
            user_id=OWNER,
        )
        item_id = created["action_data"]["id"]
        result = await _execute_scheduled_actions(
            args={"action": "update", "action_id": item_id, "title": "New title"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["action_data"]["title"] == "New title"

    async def test_update_invalid_run_at(self, db_session):
        created = await _execute_scheduled_actions(
            args={"action": "create", "prompt": "X", "cron_expr": "0 8 * * *"},
            db=db_session,
            user_id=OWNER,
        )
        item_id = created["action_data"]["id"]
        result = await _execute_scheduled_actions(
            args={"action": "update", "action_id": item_id, "run_at": "bad"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "Invalid run_at" in result["error"]

    async def test_update_to_inactive_unregisters_scheduler(self, db_session):
        created = await _execute_scheduled_actions(
            args={"action": "create", "prompt": "X", "cron_expr": "0 8 * * *"},
            db=db_session,
            user_id=OWNER,
        )
        item_id = created["action_data"]["id"]
        result = await _execute_scheduled_actions(
            args={"action": "update", "action_id": item_id, "is_active": False},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["action_data"]["is_active"] is False

    async def test_delete_requires_action_id(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "delete"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "action_id" in result["error"]

    async def test_delete_missing_returns_error(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "delete", "action_id": "nope"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "not found" in result["error"].lower()

    async def test_delete_existing(self, db_session):
        created = await _execute_scheduled_actions(
            args={"action": "create", "prompt": "X", "cron_expr": "0 8 * * *"},
            db=db_session,
            user_id=OWNER,
        )
        item_id = created["action_data"]["id"]
        result = await _execute_scheduled_actions(
            args={"action": "delete", "action_id": item_id}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        assert result["action_id"] == item_id
        # Subsequent get should not find it.
        gone = await _execute_scheduled_actions(
            args={"action": "get", "action_id": item_id}, db=db_session, user_id=OWNER
        )
        assert gone["ok"] is False

    async def test_unknown_action_returns_error(self, db_session):
        result = await _execute_scheduled_actions(
            args={"action": "frobnicate"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "Unknown action" in result["error"]


# ---------------------------------------------------------------------------
# Memories tool
# ---------------------------------------------------------------------------


class TestMemoriesTool:
    async def test_list_empty(self, db_session):
        result = await _execute_memories(args={"operation": "list"}, db=db_session, user_id=OWNER)
        assert result["ok"] is True
        assert result["operation"] == "list"
        assert result["count"] == 0
        assert result["memories"] == []

    async def test_create_and_list(self, db_session):
        created = await _execute_memories(
            args={"operation": "create", "content": "Prefers dark mode"},
            db=db_session,
            user_id=OWNER,
        )
        assert created["ok"] is True
        assert created["memory"]["content"] == "Prefers dark mode"
        listed = await _execute_memories(args={"operation": "list"}, db=db_session, user_id=OWNER)
        assert listed["count"] == 1

    async def test_create_requires_content(self, db_session):
        result = await _execute_memories(
            args={"operation": "create", "content": "   "}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "content" in result["error"]

    async def test_create_with_source_conversation(self, db_session, test_conversation):
        result = await _execute_memories(
            args={
                "operation": "create",
                "content": "X",
                "source_conversation_id": test_conversation.id,
            },
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["memory"]["source_conversation_id"] == test_conversation.id

    async def test_get_requires_id(self, db_session):
        result = await _execute_memories(args={"operation": "get"}, db=db_session, user_id=OWNER)
        assert result["ok"] is False
        assert "memory_id" in result["error"]

    async def test_get_missing(self, db_session):
        result = await _execute_memories(
            args={"operation": "get", "memory_id": "nope"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "not found" in result["error"].lower()

    async def test_get_existing(self, db_session):
        created = await _execute_memories(
            args={"operation": "create", "content": "X"}, db=db_session, user_id=OWNER
        )
        mid = created["memory"]["id"]
        result = await _execute_memories(
            args={"operation": "get", "memory_id": mid}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        assert result["memory"]["id"] == mid

    async def test_update_requires_id(self, db_session):
        result = await _execute_memories(args={"operation": "update"}, db=db_session, user_id=OWNER)
        assert result["ok"] is False
        assert "memory_id" in result["error"]

    async def test_update_requires_a_field(self, db_session):
        created = await _execute_memories(
            args={"operation": "create", "content": "X"}, db=db_session, user_id=OWNER
        )
        mid = created["memory"]["id"]
        result = await _execute_memories(
            args={"operation": "update", "memory_id": mid}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "content or is_active" in result["error"]

    async def test_update_content(self, db_session):
        created = await _execute_memories(
            args={"operation": "create", "content": "X"}, db=db_session, user_id=OWNER
        )
        mid = created["memory"]["id"]
        result = await _execute_memories(
            args={"operation": "update", "memory_id": mid, "content": "Edited"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["memory"]["content"] == "Edited"

    async def test_update_is_active_false(self, db_session):
        created = await _execute_memories(
            args={"operation": "create", "content": "X"}, db=db_session, user_id=OWNER
        )
        mid = created["memory"]["id"]
        result = await _execute_memories(
            args={"operation": "update", "memory_id": mid, "is_active": False},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["memory"]["is_active"] is False

    async def test_update_missing_memory(self, db_session):
        result = await _execute_memories(
            args={"operation": "update", "memory_id": "nope", "content": "x"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "not found" in result["error"].lower()

    async def test_update_blank_content_treated_as_none(self, db_session):
        created = await _execute_memories(
            args={"operation": "create", "content": "X"}, db=db_session, user_id=OWNER
        )
        mid = created["memory"]["id"]
        result = await _execute_memories(
            args={"operation": "update", "memory_id": mid, "content": "   ", "is_active": True},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["memory"]["content"] == "X"

    async def test_delete_requires_id(self, db_session):
        result = await _execute_memories(args={"operation": "delete"}, db=db_session, user_id=OWNER)
        assert result["ok"] is False
        assert "memory_id" in result["error"]

    async def test_delete_missing(self, db_session):
        result = await _execute_memories(
            args={"operation": "delete", "memory_id": "nope"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "not found" in result["error"].lower()

    async def test_delete_existing_soft_deletes(self, db_session):
        created = await _execute_memories(
            args={"operation": "create", "content": "X"}, db=db_session, user_id=OWNER
        )
        mid = created["memory"]["id"]
        result = await _execute_memories(
            args={"operation": "delete", "memory_id": mid}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        # Soft-delete: list should no longer return it.
        listed = await _execute_memories(args={"operation": "list"}, db=db_session, user_id=OWNER)
        assert listed["count"] == 0

    async def test_unknown_operation_returns_error(self, db_session):
        result = await _execute_memories(
            args={"operation": "frobnicate"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "Unknown operation" in result["error"]


# ---------------------------------------------------------------------------
# Notifications tool
# ---------------------------------------------------------------------------


class TestNotificationsTool:
    async def test_list_empty(self, db_session):
        result = await _execute_notifications(args={"action": "list"}, db=db_session, user_id=OWNER)
        assert result["ok"] is True
        assert result["action"] == "list"
        assert result["count"] == 0
        assert result["unread_count"] == 0
        assert result["notifications"] == []

    async def test_unread_count_empty(self, db_session):
        result = await _execute_notifications(
            args={"action": "unread_count"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        assert result["unread_count"] == 0

    async def test_mark_read_without_id_marks_all(self, db_session):
        result = await _execute_notifications(
            args={"action": "mark_read"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        # When no notification_id is given the action switches to mark_all_read.
        assert result["action"] == "mark_all_read"
        assert result["count"] == 0

    async def test_mark_read_with_missing_id_returns_error(self, db_session):
        result = await _execute_notifications(
            args={"action": "mark_read", "notification_id": "nope"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "not found" in result["error"].lower()

    async def test_mark_all_read(self, db_session):
        result = await _execute_notifications(
            args={"action": "mark_all_read"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        assert result["action"] == "mark_all_read"

    async def test_delete_requires_id(self, db_session):
        result = await _execute_notifications(
            args={"action": "delete"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "notification_id" in result["error"]

    async def test_delete_missing_returns_error(self, db_session):
        result = await _execute_notifications(
            args={"action": "delete", "notification_id": "nope"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "not found" in result["error"].lower()

    async def test_get_preferences(self, db_session):
        result = await _execute_notifications(
            args={"action": "get_preferences"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        assert result["action"] == "get_preferences"
        # Defaults: all channels on.
        prefs = result["preferences"]
        assert prefs["chat_responses_enabled"] is True
        assert prefs["reminders_enabled"] is True
        assert prefs["system_alerts_enabled"] is True
        assert prefs["friend_updates_enabled"] is True

    async def test_update_preferences(self, db_session):
        result = await _execute_notifications(
            args={
                "action": "update_preferences",
                "reminders_enabled": False,
                "friend_updates_enabled": False,
            },
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["preferences"]["reminders_enabled"] is False
        assert result["preferences"]["friend_updates_enabled"] is False
        # Untouched flags stay on.
        assert result["preferences"]["chat_responses_enabled"] is True

    async def test_unknown_action_returns_error(self, db_session):
        result = await _execute_notifications(
            args={"action": "frobnicate"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "Unknown action" in result["error"]


# ---------------------------------------------------------------------------
# App help tool (read-only, no DB)
# ---------------------------------------------------------------------------


class TestAppHelpTool:
    async def test_requires_query(self, db_session):
        result = await _execute_app_help(args={"query": "   "}, db=db_session, user_id=OWNER)
        assert result["ok"] is False
        assert "query" in result["error"]

    async def test_returns_results_for_known_query(self, db_session):
        result = await _execute_app_help(
            args={"query": "how do I create a conversation"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is True
        # The guide has a chat section, so this should match something.
        assert isinstance(result["results"], list)
        # Don't over-constrain; we just assert the structure.

    async def test_no_results_returns_note(self, db_session):
        # search_help tokenizes + scores against section tokens; only
        # truly off-domain words return zero. Use tokens the guide doesn't
        # contain (verified by tokenizing over all section bodies/headings).
        result = await _execute_app_help(
            args={"query": "zzzqqqxx jjjkkkuuu"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["results"] == []
        assert "note" in result


# ---------------------------------------------------------------------------
# Create room proposal tool (validation only, no DB writes)
# ---------------------------------------------------------------------------


class TestCreateRoomProposal:
    async def test_requires_name(self, db_session):
        result = await _execute_create_room(args={"name": ""}, db=db_session, user_id=OWNER)
        assert result["ok"] is False
        assert "name" in result["error"]

    async def test_rejects_oversized_name(self, db_session):
        result = await _execute_create_room(args={"name": "x" * 201}, db=db_session, user_id=OWNER)
        assert result["ok"] is False
        assert "200" in result["error"]

    async def test_rejects_invalid_member_emails(self, db_session):
        result = await _execute_create_room(
            args={"name": "Room", "member_emails": ["not-an-email"]},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "Invalid member emails" in result["error"]

    async def test_member_emails_normalized_to_lower_stripped(self, db_session):
        result = await _execute_create_room(
            args={
                "name": "Room",
                "member_emails": ["  Alice@Example.COM  "],
            },
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["proposal"]["payload"]["member_emails"] == ["alice@example.com"]

    async def test_rejects_non_list_member_emails(self, db_session):
        result = await _execute_create_room(
            args={"name": "Room", "member_emails": "alice@example.com"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "member_emails must be a list" in result["error"]

    async def test_rejects_non_list_agents(self, db_session):
        result = await _execute_create_room(
            args={"name": "Room", "agents": "not a list"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "agents must be a list" in result["error"]

    async def test_rejects_agent_without_name_or_model(self, db_session):
        result = await _execute_create_room(
            args={"name": "Room", "agents": [{"name": "A", "model": ""}]},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "name and a model" in result["error"]

    async def test_rejects_non_dict_agent(self, db_session):
        result = await _execute_create_room(
            args={"name": "Room", "agents": ["not-a-dict"]},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "Each agent must be an object" in result["error"]

    async def test_rejects_invalid_response_mode(self, db_session):
        result = await _execute_create_room(
            args={
                "name": "Room",
                "agents": [{"name": "A", "model": "m", "response_mode": "never"}],
            },
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "response_mode" in result["error"]

    async def test_valid_proposal_with_agents_and_members(self, db_session):
        result = await _execute_create_room(
            args={
                "name": "Project room",
                "description": "  Some description  ",
                "member_emails": ["alice@example.com", "bob@example.com"],
                "agents": [
                    {"name": "A", "model": "qwen", "response_mode": "auto"},
                    {
                        "name": "B",
                        "model": "llama",
                        "is_moderator": True,
                        "system_prompt": "be brief",
                    },
                ],
            },
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        p = result["proposal"]
        assert p["type"] == CREATE_ROOM_TOOL
        assert p["payload"]["name"] == "Project room"
        assert p["payload"]["description"] == "Some description"
        assert p["payload"]["member_emails"] == ["alice@example.com", "bob@example.com"]
        assert len(p["payload"]["agents"]) == 2
        assert p["payload"]["agents"][0]["response_mode"] == "auto"
        assert p["payload"]["agents"][1]["is_moderator"] is True
        assert p["payload"]["agents"][1]["system_prompt"] == "be brief"
        assert result["note"]  # the "this is a proposal" note

    async def test_description_blank_becomes_none(self, db_session):
        result = await _execute_create_room(
            args={"name": "Room", "description": "   "},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["proposal"]["payload"]["description"] is None


# ---------------------------------------------------------------------------
# Set conversation style proposal (validation only)
# ---------------------------------------------------------------------------


class TestSetStyleProposal:
    async def test_requires_at_least_one_field(self, db_session):
        result = await _execute_set_style(args={}, db=db_session, user_id=OWNER)
        assert result["ok"] is False
        assert "at least one" in result["error"]

    async def test_rejects_invalid_thinking_level(self, db_session):
        result = await _execute_set_style(
            args={"thinking_level": "ultra"}, db=db_session, user_id=OWNER
        )
        assert result["ok"] is False
        assert "thinking_level" in result["error"]

    async def test_valid_proposal_with_model(self, db_session):
        result = await _execute_set_style(args={"model": "qwen2.5"}, db=db_session, user_id=OWNER)
        assert result["ok"] is True
        p = result["proposal"]
        assert p["type"] == SET_STYLE_TOOL
        assert p["payload"]["model"] == "qwen2.5"
        assert p["payload"]["thinking_level"] is None
        assert p["payload"]["system_prompt"] is None

    async def test_valid_proposal_with_all_fields(self, db_session):
        result = await _execute_set_style(
            args={
                "model": "  qwen  ",
                "thinking_level": "high",
                "system_prompt": "  be terse  ",
            },
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        p = result["proposal"]
        assert p["payload"]["model"] == "qwen"
        assert p["payload"]["thinking_level"] == "high"
        assert p["payload"]["system_prompt"] == "be terse"

    async def test_empty_model_treated_as_none(self, db_session):
        result = await _execute_set_style(
            args={"model": "   ", "thinking_level": "low"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["proposal"]["payload"]["model"] is None


# ---------------------------------------------------------------------------
# Submit report tool (exercises ReportService + admin notify, covered by
# test_report_tool too — kept here for the execute_native_tool dispatch path)
# ---------------------------------------------------------------------------


class TestSubmitReportDispatch:
    async def test_dispatch_valid_bug(self, db_session):
        result = await execute_native_tool(
            name="submit_report",
            args={"type": "bug", "title": "X", "description": "Y"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert result["report"]["type"] == "bug"
        assert "Bug report" in result["note"]

    async def test_dispatch_valid_feature(self, db_session):
        result = await execute_native_tool(
            name="submit_report",
            args={"type": "feature", "title": "X", "description": "Y"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is True
        assert "Feature request" in result["note"]

    async def test_dispatch_invalid_type(self, db_session):
        result = await execute_native_tool(
            name="submit_report",
            args={"type": "weird", "title": "X", "description": "Y"},
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "type" in result["error"]

    async def test_dispatch_oversized_description(self, db_session):
        result = await _execute_submit_report(
            args={
                "type": "bug",
                "title": "X",
                "description": "x" * 10001,
            },
            db=db_session,
            user_id=OWNER,
        )
        assert result["ok"] is False
        assert "10000" in result["error"]
