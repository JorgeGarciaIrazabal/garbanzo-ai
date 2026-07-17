from fastapi import APIRouter

from app.core.config import get_settings

router = APIRouter()


@router.get("/health", tags=["health"])
async def health_check() -> dict:
    return {
        "status": "ok",
        "message": "Garbanzo AI backend is running",
        "version": get_settings().app_version,
    }
