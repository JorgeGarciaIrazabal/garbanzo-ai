"""User-facing MCP endpoints (tool discovery)."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.session import get_db
from app.schemas.mcp import MCPToolOut
from app.services.mcp_service import MCPService

router = APIRouter()


def get_mcp_service(db: Annotated[AsyncSession, Depends(get_db)]) -> MCPService:
    return MCPService(db)


@router.get(
    "/tools",
    response_model=list[MCPToolOut],
    summary="List all available tools from enabled MCP servers",
)
async def list_tools(
    _user: Annotated[dict[str, Any], Depends(get_current_user)],
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> list[MCPToolOut]:
    tools = await service.list_all_tools(enabled_only=True)
    return [MCPToolOut(**t) for t in tools]
