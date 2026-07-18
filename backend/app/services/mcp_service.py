"""MCP server registry + tool discovery / invocation."""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
import re
import time
import uuid
from typing import Any

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.mcp_server import MCPServer

logger = logging.getLogger(__name__)


# Env vars forwarded from the backend's own process environment into stdio MCP
# subprocesses. The MCP SDK otherwise strips everything but a minimal safe set
# (HOME/PATH/…), which would hide credentials that first-party stdio servers
# need — notably the websearch server's OLLAMA_API_KEY, injected into the prod
# container. Kept to a small allowlist so we don't leak SECRET_KEY/DB creds to
# every registered server. A server row's own ``env`` still overrides these.
_STDIO_ENV_PASSTHROUGH = ("OLLAMA_API_KEY", "OLLAMA_BASE_URL")


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

    async def list_global_servers(self) -> list[MCPServer]:
        """Global (admin-managed) servers — ``owner_email IS NULL``."""
        result = await self.db.execute(
            select(MCPServer).where(MCPServer.owner_email.is_(None)).order_by(MCPServer.created_at)
        )
        return list(result.scalars().all())

    async def list_user_servers(self, owner_email: str) -> list[MCPServer]:
        """A single user's personal servers."""
        result = await self.db.execute(
            select(MCPServer)
            .where(MCPServer.owner_email == owner_email)
            .order_by(MCPServer.created_at)
        )
        return list(result.scalars().all())

    async def _servers_visible_to(self, user_email: str | None) -> list[MCPServer]:
        """Servers whose tools a caller may use.

        ``user_email`` set → global servers plus that user's personal ones.
        ``user_email`` None (e.g. multi-user rooms) → global servers only.
        """
        if user_email is None:
            return await self.list_global_servers()
        result = await self.db.execute(
            select(MCPServer)
            .where(or_(MCPServer.owner_email.is_(None), MCPServer.owner_email == user_email))
            .order_by(MCPServer.created_at)
        )
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
        owner_email: str | None = None,
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
            owner_email=owner_email,
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
        from mcp.client.stdio import get_default_environment, stdio_client

        if server.transport in ("http", "sse"):
            if not server.url:
                raise ValueError(f"Server {server.id} has no URL configured")
            headers: dict[str, str] | None = None
            if server.auth_header:
                headers = {"Authorization": server.auth_header}
            async with (
                sse_client(server.url, headers=headers) as (read, write),
                ClientSession(read, write) as session,
            ):
                await session.initialize()
                yield session
        elif server.transport == "stdio":
            if not server.command:
                raise ValueError(f"Server {server.id} has no command configured")
            # Start from the SDK's safe default env, forward our allowlisted
            # vars from this process, then let the server row's own env win.
            child_env = get_default_environment()
            for name in _STDIO_ENV_PASSTHROUGH:
                value = os.environ.get(name)
                if value:
                    child_env[name] = value
            child_env.update(server.env or {})
            params = StdioServerParameters(
                command=server.command,
                args=list(server.args or []),
                env=child_env,
            )
            async with (
                stdio_client(params) as (read, write),
                ClientSession(read, write) as session,
            ):
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
            tools = await asyncio.wait_for(self._list_tools_for_server(server), timeout=15.0)
            return {"ok": True, "tools_count": len(tools), "error": None}
        except Exception as exc:
            logger.warning("MCP test_connection failed for %s: %s", server.id, exc)
            return {"ok": False, "tools_count": 0, "error": str(exc)}

    async def list_all_tools(
        self,
        enabled_only: bool = True,
        use_cache: bool = True,
        *,
        user_email: str | None = None,
    ) -> list[dict[str, Any]]:
        """Aggregate tool listings across the servers visible to a caller.

        ``user_email`` set → global servers plus that user's personal ones.
        ``user_email`` None (e.g. multi-user rooms) → global servers only.

        Result is cached for 60 seconds, keyed per scope so one user's
        personal servers never leak into another's cached list. If a server
        errors during listing, it is skipped but others still return their
        tools.
        """
        scope = "global" if user_email is None else f"user:{user_email}"
        cache_key = scope if enabled_only else f"{scope}:inc_disabled"
        now = time.monotonic()
        if use_cache:
            cached = _tools_cache.get(cache_key)
            if cached and cached[0] > now:
                return cached[1]

        servers = await self._servers_visible_to(user_email)
        if enabled_only:
            servers = [s for s in servers if s.enabled]

        all_tools: list[dict[str, Any]] = []
        for server in servers:
            try:
                tools = await asyncio.wait_for(self._list_tools_for_server(server), timeout=15.0)
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


_NAME_SAFE_RE = re.compile(r"[^a-zA-Z0-9_-]")
_MAX_FUNCTION_NAME_LEN = 64


def _sanitize_name(value: str) -> str:
    """Coerce ``value`` to the OpenAI/Ollama function-name charset."""
    cleaned = _NAME_SAFE_RE.sub("_", value).strip("_")
    return cleaned or "tool"


def build_tool_payload(
    tools: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], dict[str, tuple[str, str]]]:
    """Convert internal tool dicts to Ollama/OpenAI tool schema.

    Returns ``(ollama_tools, lookup)`` where ``lookup`` maps the function
    name advertised to the LLM back to ``(server_id, tool_name)``.

    Function names are sanitized to the OpenAI tool-name charset
    ``[a-zA-Z0-9_-]`` and capped at 64 chars. Collisions across servers are
    disambiguated by prefixing with a sanitized server name.
    """
    lookup: dict[str, tuple[str, str]] = {}
    ollama_tools: list[dict[str, Any]] = []

    for t in tools:
        owner = (t["server_id"], t["name"])
        base = _sanitize_name(t["name"])[:_MAX_FUNCTION_NAME_LEN]
        name = base
        if name in lookup and lookup[name] != owner:
            srv = _sanitize_name(t.get("server_name") or t["server_id"])[:20]
            name = f"{srv}__{base}"[:_MAX_FUNCTION_NAME_LEN]
            counter = 2
            while name in lookup and lookup[name] != owner:
                suffix = f"__{counter}"
                name = base[: _MAX_FUNCTION_NAME_LEN - len(suffix)] + suffix
                counter += 1
        lookup[name] = owner

        parameters = t.get("input_schema") or {"type": "object", "properties": {}}
        if not isinstance(parameters, dict):
            try:
                parameters = json.loads(parameters)
            except Exception:
                parameters = {"type": "object", "properties": {}}
        ollama_tools.append(
            {
                "type": "function",
                "function": {
                    "name": name,
                    "description": t.get("description") or "",
                    "parameters": parameters,
                },
            }
        )
    return ollama_tools, lookup


def to_ollama_tools(tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Backwards-compatible wrapper returning only the Ollama tool list."""
    return build_tool_payload(tools)[0]
