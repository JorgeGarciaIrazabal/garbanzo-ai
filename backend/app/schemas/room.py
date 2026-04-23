"""Pydantic schemas for multi-person chat rooms."""

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field

# ============================================================================
# Agents
# ============================================================================


ResponseMode = Literal["mention", "always", "round_robin", "auto"]


class RoomAgentCreate(BaseModel):
    """Create or add an agent to a room."""

    name: str = Field(..., min_length=1, max_length=100)
    avatar: str | None = Field(None, max_length=20, description="Emoji or short glyph")
    provider: str = Field(default="ollama", max_length=50)
    model: str = Field(..., min_length=1, max_length=100)
    system_prompt: str | None = None
    response_mode: ResponseMode = "mention"
    turn_order: int = Field(default=0, ge=0)
    is_active: bool = True
    is_moderator: bool = False


class RoomAgentUpdate(BaseModel):
    """Partial update for an existing room agent."""

    name: str | None = Field(None, min_length=1, max_length=100)
    avatar: str | None = Field(None, max_length=20)
    provider: str | None = Field(None, max_length=50)
    model: str | None = Field(None, max_length=100)
    system_prompt: str | None = None
    response_mode: ResponseMode | None = None
    turn_order: int | None = Field(None, ge=0)
    is_active: bool | None = None
    is_moderator: bool | None = None


class RoomAgentOut(BaseModel):
    id: str
    room_id: str
    name: str
    avatar: str | None = None
    provider: str
    model: str
    system_prompt: str | None = None
    response_mode: ResponseMode
    turn_order: int
    is_active: bool
    is_moderator: bool
    created_at: datetime

    model_config = {"from_attributes": True}


# ============================================================================
# Members
# ============================================================================


MemberRole = Literal["owner", "member"]


class RoomMemberAdd(BaseModel):
    """Invite / add a user to a room."""

    user_id: str = Field(..., description="User email")
    role: MemberRole = "member"


class RoomMemberUpdate(BaseModel):
    role: MemberRole


class RoomMemberOut(BaseModel):
    room_id: str
    user_id: str
    role: MemberRole
    joined_at: datetime

    model_config = {"from_attributes": True}


# ============================================================================
# Rooms
# ============================================================================


RoomMode = Literal["chat", "debate"]


class RoomCreate(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: str | None = None
    is_public: bool = False
    max_agent_turn_depth: int = Field(default=3, ge=1, le=10)
    mode: RoomMode = "chat"
    member_emails: list[str] = Field(
        default_factory=list,
        description="Additional user emails to add as members on creation",
    )


class RoomUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=200)
    description: str | None = None
    is_public: bool | None = None
    max_agent_turn_depth: int | None = Field(None, ge=1, le=10)
    mode: RoomMode | None = None
    owner_id: str | None = Field(
        None, description="Transfer ownership to this user (must already be a member)"
    )


class RoomOut(BaseModel):
    id: str
    name: str
    description: str | None = None
    owner_id: str
    is_public: bool
    max_agent_turn_depth: int
    mode: RoomMode
    created_at: datetime
    updated_at: datetime
    member_count: int = 0
    agent_count: int = 0

    model_config = {"from_attributes": True}

    @classmethod
    def from_model(cls, room: Any) -> "RoomOut":
        return cls(
            id=room.id,
            name=room.name,
            description=room.description,
            owner_id=room.owner_id,
            is_public=room.is_public,
            max_agent_turn_depth=room.max_agent_turn_depth,
            mode=room.mode,
            created_at=room.created_at,
            updated_at=room.updated_at,
            member_count=len(room.members) if room.members is not None else 0,
            agent_count=len(room.agents) if room.agents is not None else 0,
        )


class RoomDetailOut(RoomOut):
    members: list[RoomMemberOut] = Field(default_factory=list)
    agents: list[RoomAgentOut] = Field(default_factory=list)

    @classmethod
    def from_model(cls, room: Any) -> "RoomDetailOut":
        return cls(
            id=room.id,
            name=room.name,
            description=room.description,
            owner_id=room.owner_id,
            is_public=room.is_public,
            max_agent_turn_depth=room.max_agent_turn_depth,
            mode=room.mode,
            created_at=room.created_at,
            updated_at=room.updated_at,
            member_count=len(room.members) if room.members is not None else 0,
            agent_count=len(room.agents) if room.agents is not None else 0,
            members=[RoomMemberOut.model_validate(m) for m in (room.members or [])],
            agents=[RoomAgentOut.model_validate(a) for a in (room.agents or [])],
        )


class RoomList(BaseModel):
    items: list[RoomOut]
    total: int
    page: int = 1
    page_size: int = 20


# ============================================================================
# Messages
# ============================================================================


RoomMessageRole = Literal["user", "assistant", "system", "tool_call", "tool_result"]


class RoomMessageOut(BaseModel):
    id: str
    room_id: str
    role: RoomMessageRole
    sender_user_id: str | None = None
    sender_agent_id: str | None = None
    content: str
    meta: dict[str, Any] | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class RoomMessageList(BaseModel):
    items: list[RoomMessageOut]
    total: int
    page: int = 1
    page_size: int = 50


class RoomChatPost(BaseModel):
    """A user-originated message posted via REST (WebSocket is preferred)."""

    content: str = Field(..., min_length=1)


class RoomExport(BaseModel):
    """Room export payload for JSON format."""

    room: RoomDetailOut
    messages: list[RoomMessageOut]
