"""Virtual folder metadata and bounded text operations."""

from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

MAX_FILE_BYTES = 10 * 1024 * 1024
MAX_FOLDER_BYTES = 100 * 1024 * 1024
MAX_USER_BYTES = 500 * 1024 * 1024
MAX_FILES = 500
MAX_FOLDERS = 100
MAX_ATTACHED_FOLDERS = 20
MAX_PAGE_CHARS = 12000
MAX_FOLDER_DESCRIPTION = 2000


class FolderName(BaseModel):
    name: str = Field(min_length=1, max_length=200)

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        value = value.strip()
        if not value or any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError("Folder name must contain visible text without control characters.")
        return value


class FolderCreate(FolderName):
    model_config = ConfigDict(extra="forbid")

    description: str = Field(default="", max_length=MAX_FOLDER_DESCRIPTION)

    @field_validator("description")
    @classmethod
    def clean_description(cls, value: str) -> str:
        if "\x00" in value:
            raise ValueError("Folder description cannot contain null characters.")
        return value


class FolderUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=MAX_FOLDER_DESCRIPTION)

    @model_validator(mode="before")
    @classmethod
    def require_changes(cls, value):
        if isinstance(value, dict):
            fields = {"name", "description"}.intersection(value)
            if not fields or any(value[key] is None for key in fields):
                raise ValueError(
                    "Supply name or description as a string; use '' to clear description."
                )
        return value

    @field_validator("name")
    @classmethod
    def clean_name(cls, value: str) -> str:
        return FolderName.clean_name(value)

    @field_validator("description")
    @classmethod
    def clean_description(cls, value: str) -> str:
        return FolderCreate.clean_description(value)


class FolderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    description: str
    created_at: datetime
    updated_at: datetime


class FileOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    folder_id: str
    path: str
    media_type: str
    size_bytes: int
    sha256: str
    revision: int
    created_at: datetime
    updated_at: datetime


class TextCreate(BaseModel):
    path: str = Field(min_length=1, max_length=1024)
    content: str = Field(max_length=MAX_FILE_BYTES)


class TextUpdate(BaseModel):
    content: str = Field(max_length=MAX_FILE_BYTES)
    revision: int = Field(ge=1)


class FileText(BaseModel):
    file: FileOut
    text: str
    offset: int
    next_offset: int | None
    total_chars: int
    editable: bool
