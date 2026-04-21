"""MCP server registry + tool discovery / invocation."""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import time
import uuid
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.mcp_server import MCPServer

logger = logging.getLogger(__name__)


# Simple in-process tool-list cache. {key: (expires_at, value)}
_tools_cache: dict[str, tuple[float, list[dict[str, Any]]]] = {}
_CACHE_TTL_SECONDS = 60.0


def invalidate_tools_cache() -> None:
    """Clear the cached tool list. Call after CRUD on servers."""
    _tools_cache.clear()


class MCPService:
    """Handles CRUD and RPC for MCP servers.

    The service spins up a short-lived ``ClientSession`` per request. MCP
    sessions are stateful but inexpensive to open; caching across requests
    would pin connections and leak subprocesses, so we accept the per-call
    overhead and rely on the 60-second tool-list cache for hot paths.
    """

    def __init__(self, db: AsyncSession):
        self.db = db

    # ------------------------------------------------------------------
    # CRUD
    # ------------------------------------------------------------------

    async def list_servers(self) -> list[MCPServer]:
        result = await self.db.execute(select(MCPServer).order_by(MCPServer.created_at))
        return list(result.scalars().all())

    async def get_server(self, server_id: str) -> MCPServer | None:
        result = await self.db.execute(select(MCPServer).where(MCPServer.id == server_id))
        return result.scalar_one_or_none()

    async def create_server(
        self,
        *,
        name: str,
        transport: str,
        description: str | None = None,
        url: str | None = None,
        auth_header: str | None = None,
        command: str | None = None,
        args: list[str] | None = None,
        env: dict[str, str] | None = None,
        enabled: bool = True,
        created_by: str | None = None,
    ) -> MCPServer:
        server = MCPServer(
            id=str(uuid.uuid4()),
            name=name,
            description=description,
            transport=transport,
            url=url,
            auth_header=auth_header,
            command=command,
            args=args,
            env=env,
            enabled=enabled,
            created_by=created_by,
        )
        self.db.add(server)
        await self.db.commit()
        await self.db.refresh(server)
        invalidate_tools_cache()
        return server

    async def update_server(
        self,
        server_id: str,
        **fields: Any,
    ) -> MCPServer | None:
        server = await self.get_server(server_id)
        if server is None:
            return None
        for key, value in fields.items():
            if value is None and key not in {
                "url",
                "auth_header",
                "command",
                "args",
                "env",
                "description",
            }:
                # Skip "no-op" None for fields where None means "don't change"
                # Keep nullable operational fields (url, command, etc.) — caller
                # can clear them by sending null explicitly. We treat the whole
                # payload as "only keys explicitly present" via the endpoint.
                continue
            if hasattr(server, key):
                setattr(server, key, value)
        await self.db.commit()
        await self.db.refresh(server)
        invalidate_tools_cache()
        return server

    async def delete_server(self, server_id: str) -> bool:
        server = await self.get_server(server_id)
        if server is None:
            return False
        await self.db.delete(server)
        await self.db.commit()
        invalidate_tools_cache()
        return True

    # ------------------------------------------------------------------
    # MCP RPC
    # ------------------------------------------------------------------

    @contextlib.asynccontextmanager
    async def _open_session(self, server: MCPServer):
        """Open a short-lived ``ClientSession`` over the right transport."""
        from mcp import ClientSession, StdioServerParameters
        from mcp.client.sse import sse_client
        from mcp.client.stdio import stdio_client

        if server.transport in ("http", "sse"):
            if not server.url:
                raise ValueError(f"Server {server.id} has no URL configured")
            headers: dict[str, str] | None = None
            if server.auth_header:
                headers = {"Authorization": server.auth_header}
            async with sse_client(server.url, headers=headers) as (read, write):
                async with ClientSession(read, write) as session:
                    await session.initialize()
                    yield session
        elif server.transport == "stdio":
            if not server.command:
                raise ValueError(f"Server {server.id} has no command configured")
            params = StdioServerParameters(
                command=server.command,
                args=list(server.args or []),
                env=dict(server.env or {}) or None,
            )
            async with stdio_client(params) as (read, write):
                async with ClientSession(read, write) as session:
                    await session.initialize()
                    yield session
        else:
            raise ValueError(f"Unknown transport: {server.transport}")

    async def _list_tools_for_server(self, server: MCPServer) -> list[dict[str, Any]]:
        """Return a list of tool dicts for a single server (no caching)."""
        async with self._open_session(server) as session:
            result = await session.list_tools()
            tools: list[dict[str, Any]] = []
            for tool in result.tools:
                tools.append(
                    {
                        "server_id": server.id,
                        "server_name": server.name,
                        "name": tool.name,
                        "description": tool.description or "",
                        "input_schema": tool.inputSchema or {},
                    }
                )
            return tools

    async def test_connection(self, server: MCPServer) -> dict[str, Any]:
        """Open a session, list tools, and return a summary result."""
        try:
            tools = await asyncio.wait_for(
                self._list_tools_for_server(server), timeout=15.0
            )
            return {"ok": True, "tools_count": len(tools), "error": None}
        except Exception as exc:
            logger.warning("MCP test_connection failed for %s: %s", server.id, exc)
            return {"ok": False, "tools_count": 0, "error": str(exc)}

    async def list_all_tools(
        self,
        enabled_only: bool = True,
        use_cache: bool = True,
    ) -> list[dict[str, Any]]:
        """Aggregate tool listings across all (enabled) servers.

        Result is cached for 60 seconds under the key ``"all"``. If a server
        errors during listing, it is skipped but others still return their
        tools.
        """
        cache_key = "all" if enabled_only else "all:inc_disabled"
        now = time.monotonic()
        if use_cache:
            cached = _tools_cache.get(cache_key)
            if cached and cached[0] > now:
                return cached[1]

        servers = await self.list_servers()
        if enabled_only:
            servers = [s for s in servers if s.enabled]

        all_tools: list[dict[str, Any]] = []
        for server in servers:
            try:
                tools = await asyncio.wait_for(
                    self._list_tools_for_server(server), timeout=15.0
                )
                all_tools.extend(tools)
            except Exception as exc:
                logger.warning(
                    "Skipping tools for MCP server %s (%s): %s",
                    server.id,
                    server.name,
                    exc,
                )

        _tools_cache[cache_key] = (now + _CACHE_TTL_SECONDS, all_tools)
        return all_tools

    async def call_tool(
        self,
        server_id: str,
        tool_name: str,
        args: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Invoke a tool on the named server and return a result dict."""
        server = await self.get_server(server_id)
        if server is None:
            return {"ok": False, "error": f"Unknown MCP server: {server_id}"}
        if not server.enabled:
            return {"ok": False, "error": f"MCP server {server.name} is disabled"}

        try:
            async with self._open_session(server) as session:
                result = await session.call_tool(tool_name, args or {})
                content = _extract_tool_content(result)
                is_error = bool(getattr(result, "isError", False))
                return {
                    "ok": not is_error,
                    "content": content,
                    "is_error": is_error,
                }
        except Exception as exc:
            logger.exception("MCP call_tool failed: %s / %s", server.name, tool_name)
            return {"ok": False, "error": str(exc)}


def _extract_tool_content(result: Any) -> Any:
    """Best-effort conversion of an MCP CallToolResult into JSON-friendly data."""
    try:
        content = getattr(result, "content", None)
        if content is None:
            return None

        parts: list[Any] = []
        for item in content:
            if hasattr(item, "text"):
                parts.append(item.text)
            elif hasattr(item, "data"):
                parts.append({"type": getattr(item, "type", "blob"), "data": item.data})
            else:
                # Last resort — try to serialize via pydantic, else repr.
                try:
                    parts.append(item.model_dump())  # type: ignore[attr-defined]
                except Exception:
                    parts.append(repr(item))

        if len(parts) == 1:
            return parts[0]
        return parts
    except Exception as exc:
        logger.debug("Failed to extract tool content: %s", exc)
        return None


def tool_key(server_id: str, tool_name: str) -> str:
    """Canonical identifier for a tool across all servers."""
    return f"{server_id}:{tool_name}"


def split_tool_key(key: str) -> tuple[str, str]:
    """Reverse of :func:`tool_key`."""
    server_id, _, tool_name = key.partition(":")
    return server_id, tool_name


def to_ollama_tools(tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Convert internal tool dicts to Ollama/OpenAI tool schema.

    Tool names are prefixed with the server id to keep them unique across
    servers.  The original ``(server_id, tool_name)`` pair is recoverable via
    :func:`split_tool_key`.
    """
    result: list[dict[str, Any]] = []
    for t in tools:
        key = tool_key(t["server_id"], t["name"])
        parameters = t.get("input_schema") or {"type": "object", "properties": {}}
        if not isinstance(parameters, dict):
            try:
                parameters = json.loads(parameters)
            except Exception:
                parameters = {"type": "object", "properties": {}}
        result.append(
            {
                "type": "function",
                "function": {
                    "name": key,
                    "description": t.get("description") or "",
                    "parameters": parameters,
                },
            }
        )
    return result
