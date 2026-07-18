"""User-facing MCP endpoints: tool discovery + personal server management.

Personal (user-owned) servers live alongside the global ones an admin
registers. A user manages only their own here; global servers are read-only
from this side and configured in the admin portal.
"""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.models.mcp_server import MCPServer
from app.schemas.mcp import (
    MCPServerCreate,
    MCPServerOut,
    MCPServerTestResult,
    MCPServerUpdate,
    MCPToolOut,
)
from app.services.mcp_service import MCPService

router = APIRouter()


def get_mcp_service(db: Annotated[AsyncSession, Depends(get_db)]) -> MCPService:
    return MCPService(db)


async def _get_owned_server_or_404(
    service: MCPService, server_id: str, owner_email: str
) -> MCPServer:
    """Fetch a server owned by ``owner_email``, 404-ing otherwise.

    404 (not 403) on both missing and not-owned so a user can't probe for the
    existence of other users' or global servers.
    """
    server = await service.get_server(server_id)
    if server is None or server.owner_email != owner_email:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="MCP server not found",
        )
    return server


@router.get(
    "/tools",
    response_model=list[MCPToolOut],
    summary="List all available tools from enabled MCP servers",
)
async def list_tools(
    user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> list[MCPToolOut]:
    tools = await service.list_all_tools(enabled_only=True, user_email=user["email"])
    return [MCPToolOut(**t) for t in tools]


# ============================================================================
# Personal MCP servers (owned by the current user)
# ============================================================================


@router.get(
    "/servers",
    response_model=list[MCPServerOut],
    summary="List the current user's personal MCP servers",
)
async def list_my_servers(
    user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> list[MCPServerOut]:
    servers = await service.list_user_servers(user["email"])
    return [MCPServerOut.model_validate(s) for s in servers]


@router.post(
    "/servers",
    response_model=MCPServerOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register a personal MCP server",
)
async def create_my_server(
    data: MCPServerCreate,
    user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> MCPServerOut:
    server = await service.create_server(
        name=data.name,
        transport=data.transport,
        description=data.description,
        url=data.url,
        auth_header=data.auth_header,
        command=data.command,
        args=data.args,
        env=data.env,
        enabled=data.enabled,
        owner_email=user["email"],
        created_by=user["email"],
    )
    return MCPServerOut.model_validate(server)


@router.patch(
    "/servers/{server_id}",
    response_model=MCPServerOut,
    summary="Update one of the current user's personal MCP servers",
)
async def update_my_server(
    server_id: str,
    data: MCPServerUpdate,
    user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> MCPServerOut:
    await _get_owned_server_or_404(service, server_id, user["email"])
    update_fields = data.model_dump(exclude_unset=True)
    server = await service.update_server(server_id, **update_fields)
    if server is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="MCP server not found",
        )
    return MCPServerOut.model_validate(server)


@router.delete(
    "/servers/{server_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete one of the current user's personal MCP servers",
)
async def delete_my_server(
    server_id: str,
    user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> None:
    await _get_owned_server_or_404(service, server_id, user["email"])
    await service.delete_server(server_id)


@router.post(
    "/servers/{server_id}/test-connection",
    response_model=MCPServerTestResult,
    summary="Test that a personal MCP server is reachable",
)
async def test_my_server(
    server_id: str,
    user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> MCPServerTestResult:
    server = await _get_owned_server_or_404(service, server_id, user["email"])
    result = await service.test_connection(server)
    return MCPServerTestResult(**result)
