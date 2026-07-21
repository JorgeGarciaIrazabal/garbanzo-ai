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
    "glm-5.2:cloud",
    "gemma4:cloud",
    "minimax-m3:cloud",
    "nemotron-3-ultra:cloud",
    "kimi-k2.7-code:cloud",
)

# Default envelope: opencode may edit files, run commands, and fetch. Callers
# tighten this where the run is not user-confirmed.
DEFAULT_PERMISSION = {"edit": "allow", "bash": "allow", "webfetch": "allow"}


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
    bare_model = model.split("/", 1)[1] if "/" in model else model
    models = {name: {"name": name} for name in (bare_model, *CLOUD_MODELS)}
    config: dict[str, Any] = {
        "$schema": "https://opencode.ai/config.json",
        "provider": {
            "ollama": {
                "npm": "@ai-sdk/openai-compatible",
                "name": "Ollama (local)",
                "options": {"baseURL": f"{settings.ollama_base_url.rstrip('/')}/v1"},
                "models": models,
            }
        },
        "model": model,
        "permission": dict(permission or DEFAULT_PERMISSION),
    }
    if tools is not None:
        config["tools"] = tools
    if instructions is not None:
        config["instructions"] = instructions
    if mcp:
        config["mcp"] = mcp
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
