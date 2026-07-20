"""Tests for the delegate_workflow tool (idea 18).

The tool must never *do* anything itself: it validates and hands back a payload
the app acts on. It stays hidden unless a folder is attached, since a run works
on a snapshot of that folder. The prompt-wording tests are regressions from a
real run where the model claimed it could not write files.
"""

import pytest

from app.services.native_tools import (
    _DELEGATE_WORKFLOW_DESCRIPTOR,
    DELEGATE_WORKFLOW_NUDGE,
    DELEGATE_WORKFLOW_TOOL,
    PROPOSAL_TOOLS,
    client_folder_nudge,
    execute_native_tool,
    native_tool_descriptors,
    native_tool_lookup,
    workflow_tool_descriptors,
)


def _names(descriptors) -> set[str]:
    return {d["function"]["name"] for d in descriptors}


def test_delegate_workflow_is_a_proposal_tool():
    assert DELEGATE_WORKFLOW_TOOL in PROPOSAL_TOOLS


def test_nudge_frames_writing_as_possible():
    """Regression: the model told the user it couldn't write to their files.

    An earlier nudge led with "you CANNOT modify it", and models parroted that
    instead of delegating. The capability has to be the salient claim and the
    refusal has to be ruled out explicitly.
    """
    nudge = DELEGATE_WORKFLOW_NUDGE
    assert "CAN change the user's files" in nudge
    assert "Never say you are unable to" in nudge
    assert DELEGATE_WORKFLOW_TOOL in nudge
    # No bare "you cannot/can't <do something to> files" framing survives.
    lowered = nudge.lower()
    assert "you cannot modify" not in lowered
    assert "you can't" not in lowered
    # And it must not reintroduce an up-front confirmation.
    assert "Do not ask for permission" in nudge


def test_nudge_names_the_attached_folder():
    """Regression: asked about "this folder", the model replied "I can't
    access your local folders" and asked the user to paste the contents.

    It only knew *that* a folder was attached, never which one — so the
    client sends the folder's base name and the prompt states it.
    """
    named = client_folder_nudge("000")
    assert "'000'" in named
    assert "ATTACHED" in named
    assert "Never claim you cannot access the user's local files" in named
    # Degrades cleanly when the client didn't send a label.
    assert client_folder_nudge(None) == DELEGATE_WORKFLOW_NUDGE
    assert client_folder_nudge("") == DELEGATE_WORKFLOW_NUDGE


def test_tool_description_leads_with_writing():
    description = _DELEGATE_WORKFLOW_DESCRIPTOR["function"]["description"]
    # A model scanning tool descriptions for "how do I write a file" has to
    # land on this one.
    assert description.startswith("Write to the folder")
    assert "ONLY way to create, edit, or delete" in description
    assert "single new file" in description  # not just big refactors


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
    # Unlike the other proposal tools, this one is NOT user-confirmed: the app
    # starts the run as soon as the tool returns, so the note must tell the
    # model to say it's underway — never to ask for a confirmation that no
    # longer exists — while still not claiming any file was changed.
    note = result["note"]
    assert "STARTED" in note
    assert "Do NOT ask them to confirm" in note
    assert "confirm" not in note.replace("Do NOT ask them to confirm", "")

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
