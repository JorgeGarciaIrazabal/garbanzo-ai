"""Tests for MCP stdio path resolution.

Regression guard for a real, silent failure: the ``websearch`` server is
registered with a path relative to the backend root
(``uv run app/mcp_stdio_servers/web_search.py``). That resolves for the
in-process chat client, whose cwd *is* the backend root, but opencode launches
its MCP servers with the run's workdir as cwd — so the server failed to start
and the model quietly fell back to opencode's built-in ``websearch``
(DuckDuckGo) instead of the configured Ollama web_search.
"""

import os

from app.services.mcp_service import resolve_stdio_paths


def test_relative_script_path_is_made_absolute():
    resolved = resolve_stdio_paths("uv", ["run", "app/mcp_stdio_servers/web_search.py"])
    assert resolved[0] == "run"
    assert os.path.isabs(resolved[1])
    assert resolved[1].endswith("app/mcp_stdio_servers/web_search.py")
    # And it must point at something that actually exists.
    assert os.path.exists(resolved[1])


def test_package_names_are_left_alone():
    """A uvx/npx package name is not a path and must survive untouched."""
    args = ["mcp-server-time", "--local-timezone", "Europe/Madrid"]
    assert resolve_stdio_paths("uvx", args) == args


def test_flags_are_left_alone():
    assert resolve_stdio_paths("x", ["--foo", "-b"]) == ["--foo", "-b"]


def test_absolute_paths_are_left_alone():
    args = ["run", "/already/absolute/server.py"]
    assert resolve_stdio_paths("uv", args) == args


def test_missing_relative_path_is_passed_through():
    """Not every relative arg is one of our scripts; unresolvable ones stay put."""
    args = ["run", "some/other/tool.py"]
    assert resolve_stdio_paths("uv", args) == args


def test_none_args_is_empty():
    assert resolve_stdio_paths("uv", None) == []
