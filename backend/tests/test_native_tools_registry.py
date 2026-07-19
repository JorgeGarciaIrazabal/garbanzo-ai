"""Sync tests for the native tool registry — kept separate from
``test_native_tools.py`` to avoid the pytest-asyncio warning when sync tests
sit under a module-level ``pytest.mark.asyncio``.
"""

from app.services.native_tools import (
    ALL_NATIVE_TOOLS,
    APP_HELP_TOOL,
    CREATE_ROOM_TOOL,
    FOLDER_TOOLS,
    LIST_FILES_TOOL,
    MEMORY_TOOL,
    NATIVE_GARBO_SERVER_ID,
    NOTIFICATION_TOOL,
    PROPOSAL_TOOLS,
    READ_FILE_TOOL,
    SCHEDULED_ACTION_TOOL,
    SET_STYLE_TOOL,
    folder_tool_descriptors,
    native_tool_descriptors,
    native_tool_lookup,
)


def test_all_native_tools_advertised():
    names = {d["function"]["name"] for d in native_tool_descriptors()}
    assert names == set(ALL_NATIVE_TOOLS)


def test_folder_tools_are_not_registry_natives():
    # Folder tools are client-served, so they're NOT in ALL_NATIVE_TOOLS / the
    # registry — they have their own descriptor accessor, advertised only when
    # a request sets has_client_folder.
    assert not (FOLDER_TOOLS & set(ALL_NATIVE_TOOLS))
    folder_names = {d["function"]["name"] for d in folder_tool_descriptors()}
    assert folder_names == FOLDER_TOOLS == {READ_FILE_TOOL, LIST_FILES_TOOL}


def test_lookup_maps_every_tool_to_garbo_server():
    lookup = native_tool_lookup()
    assert set(lookup) == set(ALL_NATIVE_TOOLS)
    for name, (server_id, tool_name) in lookup.items():
        assert server_id == NATIVE_GARBO_SERVER_ID
        assert tool_name == name


def test_proposal_tools_advertise_as_proposals():
    # The two proposal tools must be in the PROPOSAL_TOOLS tuple so the chat
    # loop knows not to claim the action happened.
    assert CREATE_ROOM_TOOL in PROPOSAL_TOOLS
    assert SET_STYLE_TOOL in PROPOSAL_TOOLS
    # All other native tools are *not* proposals.
    non_proposal = set(ALL_NATIVE_TOOLS) - set(PROPOSAL_TOOLS)
    assert non_proposal == {
        SCHEDULED_ACTION_TOOL,
        MEMORY_TOOL,
        NOTIFICATION_TOOL,
        APP_HELP_TOOL,
        "submit_report",
    }
