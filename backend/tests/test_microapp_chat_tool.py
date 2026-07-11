"""Tests for the native ``micro_app`` chat tool.

The workspace manager and opencode agent are stubbed so no subprocess is
launched: we assert the tool descriptor shape, app/data-file resolution, the
panel signal returned by ``run_micro_app``, and that ChatService routes native
calls and remembers the active (app, file) per conversation.
"""

from __future__ import annotations

import json
from types import SimpleNamespace

import pytest

from app.schemas.chat import ChatResponseChunk
from app.schemas.microapp import MicroAppInfo
from app.services import microapp_chat_tool as mct
from app.services.microapp_chat_tool import (
    MICRO_APP_TOOL,
    NATIVE_SERVER_ID,
    micro_app_descriptor,
    run_micro_app,
)

HOUSE_APP = MicroAppInfo(
    id="house-designer",
    name="House Designer",
    path="house-designer/",
    description="2D/3D floor-plan editor",
    dataDir="houses/",
    dataExt=".house.json",
    suggestions=["Add a window to the living room"],
)
FIRE_APP = MicroAppInfo(
    id="madrid-fire-planner",
    name="Madrid Fire Planner",
    path="madrid-fire-planner/",
    description="Evacuation map",
)


def _make_houses(tmp_path):
    houses = tmp_path / "houses"
    houses.mkdir()
    for name in ("modern-apartment.house.json", "tiny-cabin.house.json"):
        (houses / name).write_text('{"name":"x","floors":[],"version":1}')
    return tmp_path


def test_descriptor_shape_and_enum():
    d = micro_app_descriptor([HOUSE_APP, FIRE_APP])
    assert d is not None
    fn = d["function"]
    assert fn["name"] == MICRO_APP_TOOL
    props = fn["parameters"]["properties"]
    assert "instruction" in props
    assert props["app"]["enum"] == ["house-designer", "madrid-fire-planner"]
    assert fn["parameters"]["required"] == ["instruction"]
    # Apps are enumerated in the description so the model knows what's available.
    assert "house-designer" in fn["description"]
    assert "madrid-fire-planner" in fn["description"]


def test_descriptor_none_without_apps():
    assert micro_app_descriptor([]) is None


def test_resolve_app_explicit_prior_default():
    apps = [FIRE_APP, HOUSE_APP]
    assert mct._resolve_app(apps, "madrid-fire-planner", None).id == "madrid-fire-planner"
    assert mct._resolve_app(apps, None, "house-designer").id == "house-designer"
    # default prefers a data-driven app
    assert mct._resolve_app(apps, None, None).id == "house-designer"


def test_resolve_data_file(tmp_path):
    _make_houses(tmp_path)
    f = mct._resolve_data_file(tmp_path, HOUSE_APP, "tiny-cabin", None)
    assert f == "houses/tiny-cabin.house.json"
    f = mct._resolve_data_file(tmp_path, HOUSE_APP, None, "houses/modern-apartment.house.json")
    assert f == "houses/modern-apartment.house.json"
    # source-only app has no data files
    assert mct._resolve_data_file(tmp_path, FIRE_APP, None, None) is None


class _StubManager:
    """Minimal stand-in for the workspace manager (no subprocesses)."""

    def __init__(self, worktree, *, enabled=True, ready=True, apps=(HOUSE_APP,)):
        self.enabled = enabled
        self._worktree = worktree
        self._ws = SimpleNamespace(slug="jorge", dev_port=8123, opencode_ready=ready)

    async def ensure(self, email):
        return self._ws

    def worktree_path(self, slug):
        return self._worktree


def _stub_agent(*chunks):
    async def fake_stream(workspace, instruction, session_id=None):
        for c in chunks:
            yield c

    return SimpleNamespace(stream_instruction=fake_stream)


@pytest.mark.asyncio
async def test_run_micro_app_house_happy_path(tmp_path, monkeypatch):
    _make_houses(tmp_path)
    monkeypatch.setattr(mct, "manager", _StubManager(tmp_path))
    monkeypatch.setattr(mct, "list_registry_apps", lambda: [HOUSE_APP, FIRE_APP])
    monkeypatch.setattr(
        mct,
        "agent",
        _stub_agent(
            ChatResponseChunk(type="chunk", content="Added a window."),
            ChatResponseChunk(type="done", metadata={}),
        ),
    )

    result = await run_micro_app(
        user_email="jorge@x.com",
        args={"instruction": "add a window", "app": "house-designer", "file": "tiny-cabin"},
        prior_app=None,
        prior_file=None,
    )
    assert result["ok"] is True
    assert result["summary"] == "Added a window."
    assert result["app"] == "house-designer"
    assert result["app_path"] == "house-designer/"
    assert result["file"] == "houses/tiny-cabin.house.json"
    assert result["dev_port"] == 8123


def test_coerce_edit():
    # explicit flag wins
    assert mct._coerce_edit(True, "open the house") is True
    assert mct._coerce_edit(False, "add a window") is False
    assert mct._coerce_edit("false", "whatever") is False
    assert mct._coerce_edit("true", "whatever") is True
    # inferred when omitted
    assert mct._coerce_edit(None, "open the house designer") is False
    assert mct._coerce_edit(None, "muéstrame la casa") is False
    assert mct._coerce_edit(None, "add a window to the salón") is True
    assert mct._coerce_edit(None, "make the living room bigger") is True
    # a view verb + a change verb is still an edit
    assert mct._coerce_edit(None, "open it and add a door") is True


@pytest.mark.asyncio
async def test_run_micro_app_open_is_fast(tmp_path, monkeypatch):
    """A pure open must NOT invoke the agent — it returns the panel signal."""
    _make_houses(tmp_path)
    monkeypatch.setattr(mct, "manager", _StubManager(tmp_path))
    monkeypatch.setattr(mct, "list_registry_apps", lambda: [HOUSE_APP])

    def _boom(*a, **k):
        raise AssertionError("agent must not run for a pure open")

    monkeypatch.setattr(mct, "agent", SimpleNamespace(stream_instruction=_boom))

    result = await run_micro_app(
        user_email="jorge@x.com",
        args={"instruction": "open the house designer", "app": "house-designer"},
        prior_app=None,
        prior_file=None,
    )
    assert result["ok"] is True
    assert result["app"] == "house-designer"
    assert result["file"] == "houses/tiny-cabin.house.json"
    assert result["dev_port"] == 8123


@pytest.mark.asyncio
async def test_run_micro_app_source_only(tmp_path, monkeypatch):
    monkeypatch.setattr(mct, "manager", _StubManager(tmp_path))
    monkeypatch.setattr(mct, "list_registry_apps", lambda: [HOUSE_APP, FIRE_APP])
    monkeypatch.setattr(
        mct,
        "agent",
        _stub_agent(ChatResponseChunk(type="chunk", content="Made the map bigger.")),
    )

    result = await run_micro_app(
        user_email="jorge@x.com",
        args={"instruction": "make the map bigger", "app": "madrid-fire-planner"},
        prior_app=None,
        prior_file=None,
    )
    assert result["ok"] is True
    assert result["app"] == "madrid-fire-planner"
    assert result["file"] is None


@pytest.mark.asyncio
async def test_run_micro_app_disabled(tmp_path, monkeypatch):
    monkeypatch.setattr(mct, "manager", _StubManager(tmp_path, enabled=False))
    result = await run_micro_app(
        user_email="jorge@x.com",
        args={"instruction": "hi"},
        prior_app=None,
        prior_file=None,
    )
    assert result["ok"] is False
    assert "not configured" in result["summary"]


@pytest.mark.asyncio
async def test_run_micro_app_agent_error(tmp_path, monkeypatch):
    _make_houses(tmp_path)
    monkeypatch.setattr(mct, "manager", _StubManager(tmp_path))
    monkeypatch.setattr(mct, "list_registry_apps", lambda: [HOUSE_APP])
    monkeypatch.setattr(
        mct,
        "agent",
        _stub_agent(ChatResponseChunk(type="error", error="opencode crashed")),
    )
    result = await run_micro_app(
        user_email="jorge@x.com",
        args={"instruction": "boom"},
        prior_app=None,
        prior_file=None,
    )
    assert result["ok"] is False
    assert "opencode crashed" in result["summary"]


@pytest.mark.asyncio
async def test_chatservice_routes_native_and_remembers_target(monkeypatch):
    from app.services.chat_service import ChatService

    svc = ChatService.__new__(ChatService)  # no DB needed for this path
    ChatService._active_target.clear()

    captured = {}

    async def fake_run(*, user_email, args, prior_app, prior_file):
        captured["prior_app"] = prior_app
        captured["prior_file"] = prior_file
        return {
            "ok": True,
            "summary": "ok",
            "app": "house-designer",
            "file": "houses/a.house.json",
        }

    monkeypatch.setattr("app.services.chat_service.run_micro_app", fake_run)

    conv = SimpleNamespace(id="c1", user_id="jorge@x.com")
    call = {
        "name": MICRO_APP_TOOL,
        "arguments": json.dumps({"instruction": "add a window"}),
    }
    lookup = {MICRO_APP_TOOL: (NATIVE_SERVER_ID, "micro-app")}

    r1 = await svc._execute_tool_call(call, lookup, conv)
    assert r1["ok"] is True
    assert captured["prior_app"] is None  # first call, no memory yet
    # second call should carry the remembered (app, file) forward
    await svc._execute_tool_call(call, lookup, conv)
    assert captured["prior_app"] == "house-designer"
    assert captured["prior_file"] == "houses/a.house.json"
