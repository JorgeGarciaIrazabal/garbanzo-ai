"""Admin portal schemas."""

from datetime import datetime

from pydantic import BaseModel, Field


class AdminUserOut(BaseModel):
    """A user row returned in the admin user list."""

    email: str
    full_name: str | None = None
    created_at: datetime
    is_admin: bool = False
    is_disabled: bool = False

    model_config = {"from_attributes": True}


class AdminUserUpdate(BaseModel):
    """Mutable admin-controlled user fields. All optional — only supplied
    fields are updated."""

    is_admin: bool | None = Field(None, description="Grant/revoke admin")
    is_disabled: bool | None = Field(None, description="Disable/re-enable login")
