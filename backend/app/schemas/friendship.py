from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field

FriendshipStatus = Literal["pending", "accepted", "blocked"]


class FriendRequestCreate(BaseModel):
    email: EmailStr = Field(..., description="Email of the user to befriend")


class FriendshipOut(BaseModel):
    id: str
    requester_email: str
    addressee_email: str
    status: FriendshipStatus
    created_at: datetime

    model_config = {"from_attributes": True}


class FriendOut(BaseModel):
    """One accepted friend, from the viewer's perspective."""

    email: str
    full_name: str | None = None
    friendship_id: str
    since: datetime


class FriendsListOut(BaseModel):
    """Everything the Friends page needs in one call."""

    friends: list[FriendOut]
    incoming_requests: list[FriendshipOut]
    outgoing_requests: list[FriendshipOut]

    # Users the viewer blocked. Blocks *against* the viewer never appear.
    blocked: list[FriendOut] = []
