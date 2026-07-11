"""Admin portal schemas."""

from datetime import datetime

from pydantic import BaseModel, EmailStr, Field, field_validator


class AdminUserCreate(BaseModel):
    """Payload for admin-only user creation."""

    email: EmailStr
    password: str = Field(..., min_length=6)
    full_name: str | None = Field(None, max_length=100)
    is_admin: bool = Field(False, description="Grant admin privileges on creation")

    @field_validator("password")
    @classmethod
    def validate_password_length(cls, v: str) -> str:
        if len(v.encode("utf-8")) > 72:
            raise ValueError("Password must not exceed 72 bytes")
        return v


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
