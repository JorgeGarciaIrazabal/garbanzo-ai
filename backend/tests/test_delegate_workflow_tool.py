"""Tests for the delegate_workflow proposal tool (idea 18).

The tool must never *do* anything: it validates and returns a proposal the user
confirms. It also has to stay hidden unless a folder is attached, since a run
works on a snapshot of that folder.
"""

import pytest

from app.services.native_tools import (
    DELEGATE_WORKFLOW_TOOL,
    PROPOSAL_TOOLS,
    execute_native_tool,
    native_tool_descriptors,
    native_tool_lookup,
    workflow_tool_descriptors,
)


def _names(descriptors) -> set[str]:
    return {d["function"]["name"] for d in descriptors}


def test_delegate_workflow_is_a_proposal_tool():
    assert DELEGATE_WORKFLOW_TOOL in PROPOSAL_TOOLS


def test_not_advertised_by_default():
    # Without an attached folder there is nothing to snapshot, so the model
    # must not even see the tool.
    assert DELEGATE_WORKFLOW_TOOL not in _names(native_tool_descriptors())


def test_advertised_via_the_gated_helper():
    assert _names(workflow_tool_descriptors()) == {DELEGATE_WORKFLOW_TOOL}


def test_is_dispatchable_when_advertised():
    assert DELEGATE_WORKFLOW_TOOL in native_tool_lookup()


@pytest.mark.asyncio
async def test_advertised_only_when_a_folder_is_attached(db_session):
    from types import SimpleNamespace

    from app.services.chat_service import ChatService

    svc = ChatService(db_session)
    conversation = SimpleNamespace(id="c", user_id="u@example.com", enabled_tools=None)

    without, _ = await svc._resolve_tools_for_conversation(conversation, has_client_folder=False)
    assert DELEGATE_WORKFLOW_TOOL not in _names(without)

    with_folder, lookup = await svc._resolve_tools_for_conversation(
        conversation, has_client_folder=True
    )
    assert DELEGATE_WORKFLOW_TOOL in _names(with_folder)
    assert lookup[DELEGATE_WORKFLOW_TOOL] == ("__garbo__", DELEGATE_WORKFLOW_TOOL)


@pytest.mark.asyncio
async def test_returns_a_proposal_without_side_effects(db_session):
    result = await execute_native_tool(
        name=DELEGATE_WORKFLOW_TOOL,
        args={
            "instruction": "Split parser.py into lexer, parser and ast modules.",
            "summary": "Split the parser into three modules",
        },
        db=db_session,
        user_id="test@example.com",
    )
    assert result["ok"] is True
    proposal = result["proposal"]
    assert proposal["type"] == DELEGATE_WORKFLOW_TOOL
    assert proposal["summary"] == "Split the parser into three modules"
    assert proposal["payload"]["instruction"].startswith("Split parser.py")
    # The note is what stops the model claiming the work already happened.
    assert "PROPOSAL" in result["note"]

    from sqlalchemy import func, select

    from app.models.workflow_run import WorkflowRun

    count = await db_session.scalar(select(func.count()).select_from(WorkflowRun))
    assert count == 0


@pytest.mark.asyncio
async def test_summary_falls_back_to_the_instruction(db_session):
    result = await execute_native_tool(
        name=DELEGATE_WORKFLOW_TOOL,
        args={"instruction": "Add type hints everywhere."},
        db=db_session,
        user_id="test@example.com",
    )
    assert result["proposal"]["summary"] == "Add type hints everywhere."


@pytest.mark.asyncio
async def test_rejects_a_missing_instruction(db_session):
    result = await execute_native_tool(
        name=DELEGATE_WORKFLOW_TOOL,
        args={"summary": "do something"},
        db=db_session,
        user_id="test@example.com",
    )
    assert result == {"ok": False, "error": "instruction is required."}


@pytest.mark.asyncio
async def test_rejects_an_oversized_instruction(db_session):
    result = await execute_native_tool(
        name=DELEGATE_WORKFLOW_TOOL,
        args={"instruction": "x" * 10001},
        db=db_session,
        user_id="test@example.com",
    )
    assert result["ok"] is False
    assert "10000" in result["error"]
