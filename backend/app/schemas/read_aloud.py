"""Read-aloud session API payloads."""

from typing import Literal

from pydantic import BaseModel, Field


class CreateReadAloudSession(BaseModel):
    text: str = Field(min_length=1)
    voice_en: str = "alba"
    voice_es: str = "lola"
    language_mode: Literal["auto", "en", "es"] = "auto"
    start_paragraph: int = Field(default=0, ge=0)


class UpdateReadAloudSession(BaseModel):
    state: Literal["playing", "paused", "buffering", "completed"]
    position_ms: int = Field(ge=0)
    update_seq: int = Field(ge=0)
