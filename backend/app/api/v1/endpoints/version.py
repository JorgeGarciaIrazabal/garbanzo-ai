from fastapi import APIRouter

from app.schemas.version import LatestVersionResponse
from app.services import version_service

router = APIRouter()


@router.get("/latest", response_model=LatestVersionResponse)
async def latest_version() -> LatestVersionResponse:
    """Latest GitHub release (cached ~5 min). Feeds the desktop auto-updater."""
    return await version_service.get_latest_release()
