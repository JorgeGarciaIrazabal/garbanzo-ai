from datetime import datetime

from pydantic import BaseModel


class ReleaseAsset(BaseModel):
    name: str
    download_url: str
    size: int


class LatestVersionResponse(BaseModel):
    """Latest GitHub release, as consumed by the desktop auto-updater."""

    version: str  # tag with any leading "v" stripped, e.g. "1.0.4"
    tag_name: str
    name: str | None = None
    body: str | None = None  # release notes (markdown)
    published_at: datetime | None = None
    html_url: str
    assets: list[ReleaseAsset]
