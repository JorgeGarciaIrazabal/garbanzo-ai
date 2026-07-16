"""Pydantic schemas for multi-person chat rooms."""

from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field
from sqlalchemy import inspect as sa_inspect

from app.schemas.chat import AttachmentIn

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
    enabled_tools: list[str] | None = Field(
        None, description="MCP tool whitelist: null=all, []=none, ['srv:tool']=subset"
    )


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
    enabled_tools: list[str] | None = Field(
        None, description="MCP tool whitelist: null=all, []=none, ['srv:tool']=subset"
    )


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
    enabled_tools: list[str] | None = None
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
    # Additive + nullable: the member's display name (``User.full_name``).
    # Old clients ignore it; new clients fall back to ``user_id`` (the email)
    # when it is ``None``.
    full_name: str | None = None
    profile_picture_b64: str | None = None
    # NULL = not muted. A far-future sentinel value means "muted forever" —
    # see ``mute_util.MUTE_FOREVER``. Frontend just compares to "now" to
    # decide whether to render the muted-bell state.
    muted_until: datetime | None = None

    model_config = {"from_attributes": True}

    @classmethod
    def from_model(cls, member: Any) -> "RoomMemberOut":
        """Build from a ``RoomMember`` ORM row, pulling ``full_name`` and
        ``profile_picture_b64`` from the related ``User`` **only if** that
        relationship is already loaded.

        The guard avoids triggering a lazy (sync) IO load on an async session
        for call sites that did not eager-load ``RoomMember.user`` — those
        simply serialize ``full_name`` as ``None``.
        """
        full_name: str | None = None
        profile_picture_b64: str | None = None
        try:
            unloaded = sa_inspect(member).unloaded
        except Exception:  # pragma: no cover - non-ORM input
            unloaded = set()
        if "user" not in unloaded:
            user = getattr(member, "user", None)
            if user is not None:
                full_name = getattr(user, "full_name", None)
                profile_picture_b64 = getattr(user, "profile_picture_b64", None)
        return cls(
            room_id=member.room_id,
            user_id=member.user_id,
            role=member.role,
            joined_at=member.joined_at,
            full_name=full_name,
            profile_picture_b64=profile_picture_b64,
            muted_until=member.muted_until,
        )


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
    # The *viewer's own* mute state, only populated when ``from_model`` is
    # given ``viewer_email`` (the room-list/search endpoints do this so the
    # sidebar can show a muted-bell badge without opening each room). NULL
    # when ``viewer_email`` is omitted or the viewer isn't a member.
    # NULL vs a far-future sentinel means the same thing as on
    # ``RoomMemberOut.muted_until`` (see ``mute_util.MUTE_FOREVER``).
    muted_until: datetime | None = None

    model_config = {"from_attributes": True}

    @classmethod
    def from_model(cls, room: Any, viewer_email: str | None = None) -> "RoomOut":
        muted_until: datetime | None = None
        if viewer_email is not None and room.members is not None:
            for member in room.members:
                if member.user_id == viewer_email:
                    muted_until = member.muted_until
                    break
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
            muted_until=muted_until,
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
            members=[RoomMemberOut.from_model(m) for m in (room.members or [])],
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
    attachments: list[AttachmentIn] = Field(default_factory=list)


class RoomExport(BaseModel):
    """Room export payload for JSON format."""

    room: RoomDetailOut
    messages: list[RoomMessageOut]


# ============================================================================
# WebSocket events
# ============================================================================
#
# These models are the single source of truth for the room WebSocket wire
# format. The endpoint (``rooms_ws.py``), the chat orchestrator
# (``room_chat_service.py``) and the connection manager
# (``room_connection_manager.py``) construct these and serialize them via
# ``model_dump()`` / ``model_dump_json()`` instead of hand-rolled dicts.
#
# CRITICAL: the serialized JSON is a public contract shared with the Flutter
# client. Field names, types and optionality must not drift. The round-trip
# test in ``tests/test_room_ws_events.py`` pins the exact serialized shape of
# every event so accidental drift fails loudly.
#
# Each ``type`` field is a ``Literal`` discriminator with a default value, so
# ``Model(...).model_dump()`` always emits ``{"type": "<name>", ...}`` with the
# discriminator first (Pydantic preserves field-definition order).


class RoomWSMessage(BaseModel):
    """The message object embedded in a server ``message`` event.

    Mirrors the historic ``_message_to_wire`` dict exactly: ``created_at`` is an
    ISO-8601 string (or ``None``), everything else passes through unchanged.
    """

    id: str
    room_id: str
    role: RoomMessageRole
    sender_user_id: str | None = None
    sender_agent_id: str | None = None
    content: str
    meta: dict[str, Any] | None = None
    created_at: str | None = None

    @classmethod
    def from_model(cls, msg: Any) -> "RoomWSMessage":
        return cls(
            id=msg.id,
            room_id=msg.room_id,
            role=msg.role,
            sender_user_id=msg.sender_user_id,
            sender_agent_id=msg.sender_agent_id,
            content=msg.content,
            meta=msg.meta,
            created_at=msg.created_at.isoformat() if msg.created_at else None,
        )


# ---- Server → client events ------------------------------------------------


class RoomMessageEvent(BaseModel):
    """A persisted message (user or agent) was added to the room."""

    type: Literal["message"] = "message"
    message: RoomWSMessage


class RoomStreamStartEvent(BaseModel):
    """An agent is about to stream a reply; clients open a bubble for it."""

    type: Literal["stream_start"] = "stream_start"
    message_id: str
    agent_id: str
    agent_name: str


class RoomChunkEvent(BaseModel):
    """A text delta for the in-flight streaming message."""

    type: Literal["chunk"] = "chunk"
    message_id: str
    agent_id: str
    content: str


class RoomThinkingEvent(BaseModel):
    """A reasoning / thought delta for the in-flight streaming message.

    Note: the canonical type is ``thinking``. The frontend keeps a legacy
    alias for the old ``thinking_chunk`` type, so servers only ever emit
    ``thinking``.
    """

    type: Literal["thinking"] = "thinking"
    message_id: str
    agent_id: str
    content: str


class RoomDoneEvent(BaseModel):
    """The agent finished streaming ``message_id``."""

    type: Literal["done"] = "done"
    message_id: str
    agent_id: str


class RoomToolEvent(BaseModel):
    """A tool execution event (call, result, or progress) for an agent turn."""

    type: Literal["tool"] = "tool"
    message_id: str
    agent_id: str
    tool_call_id: str | None = None
    tool_name: str | None = None
    status: Literal["started", "finished", "result"] = "started"
    duration_ms: int | None = None
    result: dict[str, Any] | None = None


class RoomPresenceEvent(BaseModel):
    """The set of currently-connected user ids (emails) for the room."""

    type: Literal["presence"] = "presence"
    online: list[str]


class RoomTypingEvent(BaseModel):
    """A user's typing indicator, broadcast to the room."""

    type: Literal["typing"] = "typing"
    user_id: str
    typing: bool


class RoomErrorEvent(BaseModel):
    """A per-connection error (invalid JSON, unknown event, post failure)."""

    type: Literal["error"] = "error"
    error: str


# ---- Client → server commands ----------------------------------------------


class RoomPostCommand(BaseModel):
    """Client asks to post a user message to the room."""

    type: Literal["post"] = "post"
    content: str
    attachments: list[AttachmentIn] = Field(default_factory=list)


class RoomTypingCommand(BaseModel):
    """Client broadcasts its own typing state."""

    type: Literal["typing"] = "typing"
    typing: bool = False
