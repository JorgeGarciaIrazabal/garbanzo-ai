from datetime import datetime
from zoneinfo import ZoneInfo

from pydantic import BaseModel, EmailStr, Field, field_validator


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=6)
    full_name: str | None = Field(None, max_length=100)

    @field_validator("password")
    @classmethod
    def validate_password_length(cls, v: str) -> str:
        if len(v.encode("utf-8")) > 72:
            raise ValueError("Password must not exceed 72 bytes")
        return v


class UserOut(BaseModel):
    email: str
    full_name: str | None = None
    created_at: datetime
    is_admin: bool = False
    is_disabled: bool = False
    default_model: str | None = None
    profile_picture_b64: str | None = None
    timezone: str | None = None
    locale: str | None = None

    model_config = {"from_attributes": True}


class UserInDB(UserOut):
    hashed_password: str


class UserUpdate(BaseModel):
    """Partial update of the authenticated user's profile."""

    full_name: str | None = Field(None, max_length=100)
    email: EmailStr | None = None
    default_model: str | None = Field(None, max_length=100)
    timezone: str | None = Field(None, max_length=64)
    locale: str | None = Field(None, max_length=32)

    @field_validator("timezone")
    @classmethod
    def validate_timezone(cls, v: str | None) -> str | None:
        """Reject zone names the server's zoneinfo doesn't know.

        The value ends up inside every system prompt, so garbage must be
        stopped here rather than silently skipped at render time.
        """
        if v is None:
            return v
        try:
            ZoneInfo(v)
        except Exception as e:
            raise ValueError(f"Unknown IANA timezone: {v!r}") from e
        return v


class PasswordUpdate(BaseModel):
    current_password: str = Field(..., min_length=1)
    new_password: str = Field(..., min_length=6)

    @field_validator("new_password")
    @classmethod
    def validate_password_length(cls, v: str) -> str:
        if len(v.encode("utf-8")) > 72:
            raise ValueError("Password must not exceed 72 bytes")
        return v
