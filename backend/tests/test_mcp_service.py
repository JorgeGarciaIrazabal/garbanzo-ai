"""Tests for MCPService — mocked at the SDK boundary."""

import contextlib
from unittest.mock import AsyncMock, MagicMock

import pytest

from app.models.mcp_server import MCPServer
from app.services.mcp_service import (
    MCPService,
    build_tool_payload,
    invalidate_tools_cache,
    split_tool_key,
    to_ollama_tools,
    tool_key,
)

pytestmark = pytest.mark.asyncio


@pytest.fixture(autouse=True)
def _clear_cache():
    invalidate_tools_cache()
    yield
    invalidate_tools_cache()


async def _seed_server(db, **overrides) -> MCPServer:
    server = MCPServer(
        id=overrides.get("id", "srv-1"),
        name=overrides.get("name", "test-server"),
        transport=overrides.get("transport", "sse"),
        url=overrides.get("url", "http://example.invalid/mcp"),
        enabled=overrides.get("enabled", True),
    )
    for k, v in overrides.items():
        setattr(server, k, v)
    db.add(server)
    await db.commit()
    await db.refresh(server)
    return server


def _fake_session(tools):
    """Build a MagicMock that mimics a ClientSession yielding ``tools``."""
    fake_tool_objs = []
    for t in tools:
        obj = MagicMock()
        obj.name = t["name"]
        obj.description = t.get("description", "")
        obj.inputSchema = t.get("input_schema", {})
        fake_tool_objs.append(obj)

    session = MagicMock()
    session.initialize = AsyncMock()
    session.list_tools = AsyncMock(return_value=MagicMock(tools=fake_tool_objs))

    async def _call_tool(name, args):
        content_item = MagicMock()
        content_item.text = f"called:{name}:{args}"
        result = MagicMock()
        result.content = [content_item]
        result.isError = False
        return result

    session.call_tool = AsyncMock(side_effect=_call_tool)
    return session


class _SessionCtx:
    """Async context manager yielding a fake session."""

    def __init__(self, session):
        self.session = session

    async def __aenter__(self):
        return self.session

    async def __aexit__(self, *exc):
        return False


def _patch_open_session(service: MCPService, session):
    """Monkey-patch ``_open_session`` to yield ``session`` unconditionally."""

    @contextlib.asynccontextmanager
    async def _fake(_server):
        yield session

    service._open_session = _fake  # type: ignore[method-assign]


async def test_list_all_tools_caches(db_session):
    service = MCPService(db_session)
    await _seed_server(db_session)

    session = _fake_session([{"name": "echo", "description": "echo", "input_schema": {}}])
    _patch_open_session(service, session)

    tools1 = await service.list_all_tools()
    assert len(tools1) == 1
    assert tools1[0]["name"] == "echo"
    assert tools1[0]["server_id"] == "srv-1"

    # Second call should hit cache — list_tools not called again.
    tools2 = await service.list_all_tools()
    assert tools2 == tools1
    assert session.list_tools.await_count == 1


async def test_list_all_tools_skips_failed_server(db_session):
    service = MCPService(db_session)
    await _seed_server(db_session, id="good", name="good")
    await _seed_server(db_session, id="bad", name="bad")

    good_session = _fake_session([{"name": "ok", "description": "", "input_schema": {}}])

    @contextlib.asynccontextmanager
    async def _fake(server):
        if server.id == "bad":
            raise RuntimeError("boom")
        yield good_session

    service._open_session = _fake  # type: ignore[method-assign]

    tools = await service.list_all_tools(use_cache=False)
    names = {t["server_id"]: t["name"] for t in tools}
    assert names == {"good": "ok"}


async def test_list_all_tools_filters_disabled(db_session):
    service = MCPService(db_session)
    await _seed_server(db_session, id="on", enabled=True)
    await _seed_server(db_session, id="off", enabled=False)

    session = _fake_session([{"name": "t", "description": "", "input_schema": {}}])
    _patch_open_session(service, session)

    tools = await service.list_all_tools(enabled_only=True, use_cache=False)
    assert {t["server_id"] for t in tools} == {"on"}


async def test_call_tool_dispatches(db_session):
    service = MCPService(db_session)
    server = await _seed_server(db_session)

    session = _fake_session([{"name": "echo", "description": "", "input_schema": {}}])
    _patch_open_session(service, session)

    result = await service.call_tool(server.id, "echo", {"x": 1})
    assert result["ok"] is True
    session.call_tool.assert_awaited_once_with("echo", {"x": 1})


async def test_call_tool_unknown_server(db_session):
    service = MCPService(db_session)
    result = await service.call_tool("does-not-exist", "t", {})
    assert result["ok"] is False
    assert "Unknown" in result["error"]


async def test_call_tool_disabled_server(db_session):
    service = MCPService(db_session)
    server = await _seed_server(db_session, enabled=False)
    result = await service.call_tool(server.id, "t", {})
    assert result["ok"] is False
    assert "disabled" in result["error"]


async def test_tool_key_roundtrip():
    assert tool_key("srv", "foo") == "srv:foo"
    assert split_tool_key("srv:foo") == ("srv", "foo")


async def test_to_ollama_tools_shape():
    tools = [
        {
            "server_id": "srv",
            "server_name": "name",
            "name": "list_files",
            "description": "list",
            "input_schema": {"type": "object", "properties": {"path": {"type": "string"}}},
        }
    ]
    converted = to_ollama_tools(tools)
    assert converted == [
        {
            "type": "function",
            "function": {
                "name": "list_files",
                "description": "list",
                "parameters": {
                    "type": "object",
                    "properties": {"path": {"type": "string"}},
                },
            },
        }
    ]


async def test_build_tool_payload_returns_lookup():
    """The payload builder must return a lookup that round-trips back to
    the original (server_id, tool_name) pair so the chat service can resolve
    the call."""
    server_id = "abc-123"
    tools = [
        {
            "server_id": server_id,
            "server_name": "time",
            "name": "get_current_time",
            "description": "",
            "input_schema": {"type": "object", "properties": {}},
        }
    ]
    payload, lookup = build_tool_payload(tools)
    fn_name = payload[0]["function"]["name"]
    assert fn_name == "get_current_time"
    assert lookup[fn_name] == (server_id, "get_current_time")


async def test_build_tool_payload_names_match_openai_charset():
    """Function names must comply with ``^[a-zA-Z0-9_-]{1,64}$`` — colons,
    spaces, dots etc. are stripped. Otherwise the model silently drops
    the suffix and we end up calling a non-existent tool."""
    import re

    tools = [
        {
            "server_id": "uuid-with-hyphens-and:colons",
            "server_name": "weird name!",
            "name": "do.thing/now",
            "description": "",
            "input_schema": {},
        }
    ]
    payload, lookup = build_tool_payload(tools)
    fn_name = payload[0]["function"]["name"]
    assert re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", fn_name)
    assert lookup[fn_name] == (
        "uuid-with-hyphens-and:colons",
        "do.thing/now",
    )


async def test_build_tool_payload_disambiguates_collisions():
    """Two servers exposing the same tool name get distinct function names
    and the lookup remains consistent."""
    tools = [
        {
            "server_id": "srv-a",
            "server_name": "alpha",
            "name": "search",
            "description": "",
            "input_schema": {},
        },
        {
            "server_id": "srv-b",
            "server_name": "beta",
            "name": "search",
            "description": "",
            "input_schema": {},
        },
    ]
    payload, lookup = build_tool_payload(tools)
    names = [t["function"]["name"] for t in payload]
    assert names[0] != names[1]
    assert len(lookup) == 2
    assert lookup[names[0]] == ("srv-a", "search")
    assert lookup[names[1]] == ("srv-b", "search")


async def test_build_tool_payload_caps_long_names():
    """Names longer than 64 chars are truncated."""
    long_name = "a" * 200
    tools = [
        {
            "server_id": "srv",
            "server_name": "s",
            "name": long_name,
            "description": "",
            "input_schema": {},
        }
    ]
    payload, lookup = build_tool_payload(tools)
    fn_name = payload[0]["function"]["name"]
    assert len(fn_name) <= 64
    assert lookup[fn_name] == ("srv", long_name)
