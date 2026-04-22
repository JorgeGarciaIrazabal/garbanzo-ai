from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class DeviceRegisterRequest(BaseModel):
    token: str = Field(..., min_length=1, max_length=512)
    platform: Literal["android", "ios", "web"] = "android"


class DeviceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    token: str
    platform: str
    created_at: datetime
    updated_at: datetime
