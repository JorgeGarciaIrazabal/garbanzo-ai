from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, EmailStr

ShareKind = Literal["style", "prompt"]


class ShareCreate(BaseModel):
    kind: ShareKind
    item_id: str
    recipient_email: EmailStr


class SharedItemOut(BaseModel):
    id: str
    sender_email: str
    recipient_email: str
    kind: ShareKind
    payload: dict[str, Any]
    created_at: datetime

    model_config = {"from_attributes": True}


class ShareAcceptOut(BaseModel):
    """What accepting a share created in the recipient's account."""

    kind: ShareKind

    # The new copy's id: a style id or a prompt template id.
    created_id: str
