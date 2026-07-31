"""Regression tests for the standalone Ollama web-search MCP server."""

from pathlib import Path

import pytest

from app.mcp_stdio_servers.web_search import app

BACKEND_ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.asyncio
async def test_registers_search_and_fetch_tools():
    tools = await app.list_tools()

    assert {tool.name for tool in tools} == {"web_fetch", "web_search"}


def test_inline_environment_stays_on_compatible_mcp_major():
    script = (BACKEND_ROOT / "app/mcp_stdio_servers/web_search.py").read_text()
    pyproject = (BACKEND_ROOT / "pyproject.toml").read_text()

    assert '"mcp>=1,<2"' in script
    assert '"mcp>=1.0,<2"' in pyproject
