"""V2 configuration, project restrictions and process compatibility checks."""

import json
from types import SimpleNamespace
from unittest.mock import Mock

import httpx
import pytest

from app.core.config import Settings
from app.services import opencode_process, workflow_runner
from app.services.opencode_config import build_config, permission_rules


def test_native_provider_and_ordered_permissions():
    config = build_config(
        Settings(microapps_opencode_model="ollama/custom#high"),
        tools={"server_*": False, "server_search": True},
    )
    assert "provider" not in config and "tools" not in config
    provider = config["providers"]["ollama"]
    assert provider["package"] == "aisdk:@ai-sdk/openai-compatible"
    assert provider["settings"]["baseURL"].endswith("/v1")
    assert "custom" in provider["models"]
    assert config["permissions"][-2:] == [
        {"action": "server_*", "resource": "*", "effect": "deny"},
        {"action": "server_search", "resource": "*", "effect": "allow"},
    ]
    assert permission_rules({"bash": {"*": "ask", "git status *": "allow"}, "task": "deny"}) == [
        {"action": "shell", "resource": "*", "effect": "ask"},
        {"action": "shell", "resource": "git status *", "effect": "allow"},
        {"action": "subagent", "resource": "*", "effect": "deny"},
    ]


def test_project_legacy_config_keeps_restrictions_when_mcp_injected(tmp_path, monkeypatch):
    config = {
        "model": "project/custom",
        "provider": {
            "project": {
                "npm": "@ai-sdk/openai-compatible",
                "options": {"baseURL": "http://custom/v1"},
            }
        },
        "tools": {"project_search": False},
        "permission": {"bash": {"*": "deny", "git status *": "allow"}, "project_search": "deny"},
        "mcp": {"old": {"type": "local", "command": ["old"], "enabled": False, "timeout": 3210}},
    }
    original_provider = config["provider"]
    path = tmp_path / "opencode.json"
    path.write_text(json.dumps(config))
    monkeypatch.setattr(workflow_runner, "absorb_into_baseline", lambda *_: None)
    workflow_runner.seed_opencode_config(
        tmp_path,
        Settings(),
        mcp={"project": {"type": "local", "command": ["new"], "disabled": False}},
        tools={"project_*": False, "project_search": True},
    )
    converted = json.loads(path.read_text())
    assert converted["provider"] == original_provider
    assert converted["model"] == "project/custom"
    assert "permission" not in converted and "tools" not in converted
    assert converted["permissions"][-1] == {
        "action": "project_search",
        "resource": "*",
        "effect": "deny",
    }
    assert converted["permissions"][-2] == {
        "action": "shell",
        "resource": "git status *",
        "effect": "allow",
    }
    assert converted["mcp"]["servers"]["old"]["disabled"] is True
    assert converted["mcp"]["servers"]["old"]["timeout"] == {"catalog": 3210, "execution": 3210}
    assert converted["policies"] == [
        {"action": "tool.use", "resource": "project_*:*", "effect": "deny"},
        {"action": "tool.use", "resource": "project_search:*", "effect": "allow"},
    ]


def test_native_project_permissions_are_not_replaced(tmp_path, monkeypatch):
    rules = [{"action": "edit", "resource": "secret/*", "effect": "deny"}]
    path = tmp_path / "opencode.json"
    path.write_text(json.dumps({"permissions": rules}))
    monkeypatch.setattr(workflow_runner, "absorb_into_baseline", lambda *_: None)
    workflow_runner.seed_opencode_config(tmp_path, Settings())
    assert json.loads(path.read_text())["permissions"][-1] == rules[0]
    once = path.read_text()
    workflow_runner.seed_opencode_config(tmp_path, Settings())
    assert path.read_text() == once


@pytest.mark.parametrize(
    "legacy", [{"tools": {"apply_patch": False}}, {"permission": {"apply_patch": "deny"}}]
)
def test_legacy_patch_denial_overrides_injected_defaults(tmp_path, monkeypatch, legacy):
    path = tmp_path / "opencode.json"
    path.write_text(json.dumps(legacy))
    monkeypatch.setattr(workflow_runner, "absorb_into_baseline", lambda *_: None)
    workflow_runner.seed_opencode_config(tmp_path, Settings())
    config = json.loads(path.read_text())
    edit_rules = [rule for rule in config["permissions"] if rule["action"] == "edit"]
    assert edit_rules[-1] == {"action": "edit", "resource": "*", "effect": "deny"}
    assert "permission" not in config and "tools" not in config


def test_readiness_checks_status_auth_and_version(monkeypatch):
    monkeypatch.setattr(opencode_process, "OPENCODE_READY_RETRIES", 2)
    monkeypatch.setattr(opencode_process.time, "sleep", lambda *_: None)
    get = Mock(
        side_effect=[
            httpx.Response(503, request=httpx.Request("GET", "http://agent")),
            httpx.Response(
                200, json={"version": "2.1.4"}, request=httpx.Request("GET", "http://agent")
            ),
        ]
    )
    monkeypatch.setattr(opencode_process.httpx, "get", get)
    assert opencode_process.wait_ready("http://agent", SimpleNamespace(poll=lambda: None))
    assert get.call_count == 2
    assert get.call_args.args == ("http://agent/api/info",)
    assert get.call_args.kwargs["auth"] == opencode_process.OPENCODE_AUTH
    get.side_effect = None
    get.return_value = httpx.Response(
        200, json={"version": "1.18.30"}, request=httpx.Request("GET", "http://agent")
    )
    with pytest.raises(RuntimeError, match="Incompatible"):
        opencode_process.wait_ready("http://agent", SimpleNamespace(poll=lambda: None))


def test_spawn_rejects_v1_before_launch(monkeypatch):
    monkeypatch.setattr(
        opencode_process.subprocess, "run", lambda *a, **kw: SimpleNamespace(stdout="1.18.30")
    )
    popen = Mock()
    monkeypatch.setattr(opencode_process.subprocess, "Popen", popen)
    with pytest.raises(RuntimeError, match="just opencode-install"):
        opencode_process.default_spawn(["opencode", "serve"], "/tmp", {})
    popen.assert_not_called()
