"""MCP server & tool schemas."""

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

TransportLiteral = Literal["http", "sse", "stdio"]


class MCPServerCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    description: str | None = None
    transport: TransportLiteral
    # HTTP/SSE
    url: str | None = None
    auth_header: str | None = None
    # stdio
    command: str | None = None
    args: list[str] | None = None
    env: dict[str, str] | None = None
    enabled: bool = True


class MCPServerUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    description: str | None = None
    transport: TransportLiteral | None = None
    url: str | None = None
    auth_header: str | None = None
    command: str | None = None
    args: list[str] | None = None
    env: dict[str, str] | None = None
    enabled: bool | None = None


class MCPServerOut(BaseModel):
    id: str
    name: str
    description: str | None = None
    transport: TransportLiteral
    url: str | None = None
    auth_header: str | None = None
    command: str | None = None
    args: list[str] | None = None
    env: dict[str, str] | None = None
    enabled: bool
    # NULL = global (admin-managed); set = personal to this user.
    owner_email: str | None = None
    created_by: str | None = None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class MCPServerTestResult(BaseModel):
    ok: bool
    tools_count: int = 0
    error: str | None = None


class MCPToolOut(BaseModel):
    server_id: str
    server_name: str
    name: str
    description: str | None = None
    input_schema: dict[str, Any] = Field(default_factory=dict)
