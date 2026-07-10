# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "mcp",
#   "rich",
#   "ollama",
# ]
# ///
"""
MCP stdio server exposing Ollama web_search and web_fetch as tools.

Auth: the Ollama client reads ``OLLAMA_API_KEY`` from the environment and sends
it as a Bearer token. The key is resolved in this order, so no secret has to be
duplicated in the MCP client config:

1. An existing ``OLLAMA_API_KEY`` env var (how prod injects it — the backend
   container sets it, and this subprocess inherits it).
2. ``OLLAMA_API_KEY`` read from the backend ``.env`` file (the dev/IDE case,
   where the var is not exported into the process environment).
"""

from __future__ import annotations

import asyncio
import os
from pathlib import Path
from typing import Any


def _load_api_key_from_env_file() -> None:
    """Populate ``OLLAMA_API_KEY`` from backend/.env if it isn't already set.

    Looks for a ``.env`` next to the backend package root (this file lives at
    ``backend/app/mcp_stdio_servers/web_search.py``) and, as a fallback, in the
    current working directory. A real environment variable always wins, so prod
    (which injects the var) never touches the filesystem.
    """
    if os.environ.get("OLLAMA_API_KEY"):
        return

    candidates = [
        Path(__file__).resolve().parents[2] / ".env",  # backend/.env
        Path.cwd() / ".env",
        Path.cwd() / "backend" / ".env",
    ]
    for env_path in candidates:
        if not env_path.is_file():
            continue
        for raw in env_path.read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            if key.strip() == "OLLAMA_API_KEY":
                os.environ.setdefault("OLLAMA_API_KEY", value.strip().strip("'\""))
                return


_load_api_key_from_env_file()

from ollama import Client  # noqa: E402  (import after the key is in the environment)

try:
  # Preferred high-level API (if available)
  from mcp.server.fastmcp import FastMCP  # type: ignore

  _FASTMCP_AVAILABLE = True
except Exception:
  _FASTMCP_AVAILABLE = False

if not _FASTMCP_AVAILABLE:
  # Fallback to the low-level stdio server API
  from mcp.server import Server  # type: ignore
  from mcp.server.stdio import stdio_server  # type: ignore


client = Client()


def _web_search_impl(query: str, max_results: int = 3) -> dict[str, Any]:
  res = client.web_search(query=query, max_results=max_results)
  return res.model_dump()


def _web_fetch_impl(url: str) -> dict[str, Any]:
  res = client.web_fetch(url=url)
  return res.model_dump()


if _FASTMCP_AVAILABLE:
  app = FastMCP('ollama-search-fetch')

  @app.tool()
  def web_search(query: str, max_results: int = 3) -> dict[str, Any]:
    """
    Perform a web search using Ollama's hosted search API.

    Args:
      query: The search query to run.
      max_results: Maximum results to return (default: 3).

    Returns:
      JSON-serializable dict matching ollama.WebSearchResponse.model_dump()
    """

    return _web_search_impl(query=query, max_results=max_results)

  @app.tool()
  def web_fetch(url: str) -> dict[str, Any]:
    """
    Fetch the content of a web page for the provided URL.

    Args:
      url: The absolute URL to fetch.

    Returns:
      JSON-serializable dict matching ollama.WebFetchResponse.model_dump()
    """

    return _web_fetch_impl(url=url)

  if __name__ == '__main__':
    app.run()

else:
  server = Server('ollama-search-fetch')  # type: ignore[name-defined]

  @server.tool()  # type: ignore[attr-defined]
  async def web_search(query: str, max_results: int = 3) -> dict[str, Any]:
    """
    Perform a web search using Ollama's hosted search API.

    Args:
      query: The search query to run.
      max_results: Maximum results to return (default: 3).
    """

    return await asyncio.to_thread(_web_search_impl, query, max_results)

  @server.tool()  # type: ignore[attr-defined]
  async def web_fetch(url: str) -> dict[str, Any]:
    """
    Fetch the content of a web page for the provided URL.

    Args:
      url: The absolute URL to fetch.
    """

    return await asyncio.to_thread(_web_fetch_impl, url)

  async def _main() -> None:
    async with stdio_server() as (read, write):  # type: ignore[name-defined]
      await server.run(read, write)  # type: ignore[attr-defined]

  if __name__ == '__main__':
    asyncio.run(_main())
