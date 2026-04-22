from fastapi import APIRouter

from app.api.v1.endpoints import (
    admin,
    auth,
    chat,
    devices,
    health,
    mcp,
    memories,
    stt,
    system_prompts,
    tts,
)

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(admin.router, prefix="/admin", tags=["admin"])
api_router.include_router(chat.router, prefix="/chat", tags=["chat"])
api_router.include_router(devices.router, prefix="/devices", tags=["devices"])
api_router.include_router(health.router, prefix="", tags=["health"])
api_router.include_router(mcp.router, prefix="/mcp", tags=["mcp"])
api_router.include_router(memories.router, prefix="/memories", tags=["memories"])
api_router.include_router(stt.router, prefix="/stt", tags=["stt"])
api_router.include_router(
    system_prompts.router, prefix="/system-prompts", tags=["system-prompts"]
)
api_router.include_router(tts.router, prefix="/tts", tags=["tts"])
