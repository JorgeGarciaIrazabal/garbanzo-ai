"""Shared ``opencode.json`` builder for every place we spawn opencode.

Both the micro-apps workspace (``microapp_workspace``) and delegated workflow
runs (``workflow_runner``) point opencode at the local Ollama endpoint with the
same provider block; only the tool/permission envelope differs. Keeping the
model list in one module means a newly pulled cloud model is added once.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from app.core.config import Settings

# All Ollama cloud models available in the prod stack. Each must be pulled
# (``ollama pull <name>:cloud``) and the container signed in once — see
# deploy/README.md. The key is the model id opencode sees; the value carries
# its display name. The active model is always merged in, even if not listed.
CLOUD_MODELS = (
    "deepseek-v4.1-flash:cloud",
    "deepseek-v4-flash:cloud",
    "deepseek-v4-pro:cloud",
    "glm-5.3:cloud",
    "glm-5.3-flash:cloud",
    "kimi-k3:cloud",
    "gemma4:cloud",
    "nemotron-3-ultra:cloud",
    "nemotron-3-super:cloud",
    "qwen3.5:cloud",
)

# Default envelope: opencode may edit files, run commands, and fetch. Callers
# tighten this where the run is not user-confirmed.
DEFAULT_PERMISSION = {
    "edit": "allow",
    "shell": "allow",
    "webfetch": "allow",
    "external_directory": "ask",
}

_PERMISSION_ACTIONS = {
    "bash": "shell",
    "task": "subagent",
    "write": "edit",
    "patch": "edit",
    "apply_patch": "edit",
}


def permission_rules(permission: dict | str) -> list[dict[str, str]]:
    """Translate V1 permission maps, retaining wildcard/resource rule order."""
    if isinstance(permission, str):
        return [{"action": "*", "resource": "*", "effect": permission}]
    rules = []
    for action, value in permission.items():
        action = _PERMISSION_ACTIONS.get(action, action)
        for resource, effect in value.items() if isinstance(value, dict) else [("*", value)]:
            if effect not in ("allow", "deny", "ask"):
                raise ValueError(f"Invalid OpenCode permission effect: {effect!r}")
            rules.append({"action": action, "resource": resource, "effect": effect})
    return rules


def tool_permission_rules(tools: dict[str, bool]) -> list[dict[str, str]]:
    """V2 tools are permissions; keep broad denies before exact allows."""
    return [
        {
            "action": _PERMISSION_ACTIONS.get(name, name),
            "resource": "*",
            "effect": "allow" if enabled else "deny",
        }
        for name, enabled in tools.items()
    ]


def build_config(
    settings: Settings,
    *,
    tools: dict[str, bool] | None = None,
    permission: dict[str, str] | None = None,
    instructions: list[str] | None = None,
    mcp: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Build the opencode config dict for a working directory."""
    model = settings.microapps_opencode_model
    bare_model = (model.split("/", 1)[1] if "/" in model else model).split("#", 1)[0]
    models = {name: {"name": name} for name in (bare_model, *CLOUD_MODELS)}
    config: dict[str, Any] = {
        "$schema": "https://opencode.ai/config.json",
        "providers": {
            "ollama": {
                "package": "aisdk:@ai-sdk/openai-compatible",
                "name": "Ollama (local)",
                "settings": {"baseURL": f"{settings.ollama_base_url.rstrip('/')}/v1"},
                "models": models,
            }
        },
        "model": model,
        "permissions": permission_rules(DEFAULT_PERMISSION if permission is None else permission),
        "update": "disable",
    }
    if tools is not None:
        config["permissions"].extend(tool_permission_rules(tools))
    if instructions is not None:
        config["instructions"] = instructions
    if mcp:
        config["mcp"] = {"servers": mcp}
    return config


def write_config(path: Path, config: dict[str, Any], *, overwrite: bool = False) -> bool:
    """Write ``opencode.json`` into ``path`` unless one is already there.

    Returns True when this call created the file. Workflow runs use that to
    decide whether the config is *ours* (and so must be kept out of the diff
    sent back to the user) or the project's own.
    """
    cfg_path = path / "opencode.json"
    if cfg_path.exists() and not overwrite:
        return False
    cfg_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    return True
