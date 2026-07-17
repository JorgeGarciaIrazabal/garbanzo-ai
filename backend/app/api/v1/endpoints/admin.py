"""Admin portal endpoints.

All routes on this router require an authenticated admin user.
"""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.security import get_current_admin_user, hash_password
from app.db.session import get_db
from app.models.user import User
from app.schemas.admin import (
    AdminUserCreate,
    AdminUserOut,
    AdminUserUpdate,
    AvailableModelOut,
    AvailableModelUpdate,
)
from app.schemas.mcp import (
    MCPServerCreate,
    MCPServerOut,
    MCPServerTestResult,
    MCPServerUpdate,
)
from app.schemas.report import ReportOut, ReportStatus, ReportStatusUpdate
from app.services.chat_service import ChatService
from app.services.mcp_service import MCPService
from app.services.model_management_service import ModelManagementService
from app.services.report_service import ReportService
from app.services.user_service import UserService

router = APIRouter(dependencies=[Depends(get_current_admin_user)])


def get_user_service(db: Annotated[AsyncSession, Depends(get_db)]) -> UserService:
    return UserService(db)


def get_mcp_service(db: Annotated[AsyncSession, Depends(get_db)]) -> MCPService:
    return MCPService(db)


def get_model_management_service(
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ModelManagementService:
    return ModelManagementService(db)


def get_report_service(db: Annotated[AsyncSession, Depends(get_db)]) -> ReportService:
    return ReportService(db)


# ============================================================================
# Users
# ============================================================================


@router.post(
    "/users",
    response_model=AdminUserOut,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new user (admin only)",
)
async def create_user(
    data: AdminUserCreate,
    users: Annotated[UserService, Depends(get_user_service)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _admin: Annotated[dict[str, Any], Depends(get_current_admin_user)],
) -> AdminUserOut:
    email = data.email.lower()
    existing = await users.get_by_email(email)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    user = await users.create(
        email=email,
        hashed_password=hash_password(data.password),
        full_name=data.full_name,
    )
    if data.is_admin:
        user.is_admin = True
    await db.commit()
    await db.refresh(user)
    return AdminUserOut.model_validate(user)


@router.get("/users", response_model=list[AdminUserOut], summary="List all users")
async def list_users(
    db: Annotated[AsyncSession, Depends(get_db)],
    _admin: Annotated[dict[str, Any], Depends(get_current_admin_user)],
) -> list[AdminUserOut]:
    result = await db.execute(select(User).order_by(User.created_at))
    return [AdminUserOut.model_validate(u) for u in result.scalars().all()]


@router.patch(
    "/users/{email}",
    response_model=AdminUserOut,
    summary="Update a user's admin/disabled flags",
)
async def update_user(
    email: str,
    data: AdminUserUpdate,
    users: Annotated[UserService, Depends(get_user_service)],
    db: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[dict[str, Any], Depends(get_current_admin_user)],
) -> AdminUserOut:
    target = email.lower()
    user = await users.get_by_email(target)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")

    # Prevent the admin from locking themselves out.
    if target == admin["email"].lower():
        if data.is_admin is False:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Admins cannot revoke their own admin status",
            )
        if data.is_disabled is True:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Admins cannot disable their own account",
            )

    if data.is_admin is not None:
        user.is_admin = data.is_admin
    if data.is_disabled is not None:
        user.is_disabled = data.is_disabled

    await db.commit()
    await db.refresh(user)
    return AdminUserOut.model_validate(user)


# ============================================================================
# MCP Servers
# ============================================================================


@router.get(
    "/mcp-servers",
    response_model=list[MCPServerOut],
    summary="List MCP servers",
)
async def list_mcp_servers(
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> list[MCPServerOut]:
    servers = await service.list_servers()
    return [MCPServerOut.model_validate(s) for s in servers]


@router.post(
    "/mcp-servers",
    response_model=MCPServerOut,
    status_code=status.HTTP_201_CREATED,
    summary="Register a new MCP server",
)
async def create_mcp_server(
    data: MCPServerCreate,
    service: Annotated[MCPService, Depends(get_mcp_service)],
    admin: Annotated[dict[str, Any], Depends(get_current_admin_user)],
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
        created_by=admin["email"],
    )
    return MCPServerOut.model_validate(server)


@router.patch(
    "/mcp-servers/{server_id}",
    response_model=MCPServerOut,
    summary="Update an MCP server",
)
async def update_mcp_server(
    server_id: str,
    data: MCPServerUpdate,
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> MCPServerOut:
    update_fields = data.model_dump(exclude_unset=True)
    server = await service.update_server(server_id, **update_fields)
    if server is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="MCP server not found",
        )
    return MCPServerOut.model_validate(server)


@router.delete(
    "/mcp-servers/{server_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete an MCP server",
)
async def delete_mcp_server(
    server_id: str,
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> None:
    ok = await service.delete_server(server_id)
    if not ok:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="MCP server not found",
        )


@router.post(
    "/mcp-servers/{server_id}/test-connection",
    response_model=MCPServerTestResult,
    summary="Test that an MCP server is reachable",
)
async def test_mcp_connection(
    server_id: str,
    service: Annotated[MCPService, Depends(get_mcp_service)],
) -> MCPServerTestResult:
    server = await service.get_server(server_id)
    if server is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="MCP server not found",
        )
    result = await service.test_connection(server)
    return MCPServerTestResult(**result)


# ============================================================================
# Model Management
# ============================================================================


@router.get(
    "/models",
    response_model=list[AvailableModelOut],
    summary="List all models with their admin-controlled visibility",
)
async def list_models(
    service: Annotated[ModelManagementService, Depends(get_model_management_service)],
    _admin: Annotated[dict[str, Any], Depends(get_current_admin_user)],
) -> list[AvailableModelOut]:
    rows = await service.list_db_models()
    return [
        AvailableModelOut(
            model_id=row.model_id,
            is_enabled=row.is_enabled,
            is_new=False,
            updated_at=row.updated_at,
        )
        for row in rows
    ]


@router.post(
    "/models/sync",
    response_model=list[AvailableModelOut],
    summary="Sync models from the live LLM provider into the database",
)
async def sync_models(
    service: Annotated[ModelManagementService, Depends(get_model_management_service)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _admin: Annotated[dict[str, Any], Depends(get_current_admin_user)],
) -> list[AvailableModelOut]:
    """Discover all models currently available from the configured LLM provider
    and create rows in the ``available_models`` table for any new ones.

    Existing rows keep their ``is_enabled`` status.  The merged response
    includes live provider metadata (name, description, context_length)
    alongside the DB state so the admin UI can display a complete picture.
    """
    settings = get_settings()
    chat_service = ChatService(db, provider_name=settings.llm_provider)
    provider_models = await chat_service.list_available_models()
    merged = await service.upsert_from_provider(provider_models)
    await db.commit()
    return [
        AvailableModelOut(
            model_id=m["model_id"],
            is_enabled=m["is_enabled"],
            is_new=m["is_new"],
            updated_at=m.get("updated_at"),
        )
        for m in merged
    ]


# ============================================================================
# Reports (bug/feature triage)
# ============================================================================


@router.get(
    "/reports",
    response_model=list[ReportOut],
    summary="List all user-submitted reports, optionally filtered by status",
)
async def list_reports(
    service: Annotated[ReportService, Depends(get_report_service)],
    status_filter: Annotated[ReportStatus | None, Query(alias="status")] = None,
) -> list[ReportOut]:
    reports = await service.list_all(status=status_filter)
    return [ReportOut.model_validate(r) for r in reports]


@router.patch(
    "/reports/{report_id}",
    response_model=ReportOut,
    summary="Update a report's triage status",
)
async def update_report(
    report_id: str,
    data: ReportStatusUpdate,
    service: Annotated[ReportService, Depends(get_report_service)],
) -> ReportOut:
    report = await service.update_status(report_id, data.status)
    if report is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report not found")
    return ReportOut.model_validate(report)


@router.patch(
    "/models",
    response_model=AvailableModelOut,
    summary="Enable or disable a model for all users",
)
async def update_model(
    data: AvailableModelUpdate,
    service: Annotated[ModelManagementService, Depends(get_model_management_service)],
    db: Annotated[AsyncSession, Depends(get_db)],
    _admin: Annotated[dict[str, Any], Depends(get_current_admin_user)],
) -> AvailableModelOut:
    row = await service.set_enabled(data.model_id, data.is_enabled)
    await db.commit()
    await db.refresh(row)
    return AvailableModelOut(
        model_id=row.model_id,
        is_enabled=row.is_enabled,
        is_new=False,
        updated_at=row.updated_at,
    )
