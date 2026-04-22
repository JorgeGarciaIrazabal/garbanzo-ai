from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class KnowledgeDocumentOut(BaseModel):
    id: str
    filename: str
    mime_type: str
    file_size: int
    status: Literal["pending", "processing", "ready", "failed"]
    chunk_count: int
    error_message: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class KnowledgeDocumentList(BaseModel):
    items: list[KnowledgeDocumentOut] = Field(default_factory=list)
    total: int = 0


class KnowledgeChunkMatch(BaseModel):
    document_id: str
    document_filename: str
    content: str
    score: float


class KnowledgeSearchResponse(BaseModel):
    query: str
    matches: list[KnowledgeChunkMatch]
