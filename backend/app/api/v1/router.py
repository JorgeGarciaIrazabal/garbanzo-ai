from fastapi import APIRouter

from app.api.v1.endpoints import (
    admin,
    auth,
    chat,
    devices,
    health,
    knowledge_base,
    mcp,
    memories,
    microapps,
    notifications,
    rooms,
    rooms_ws,
    scheduled_actions,
    stt,
    system_prompts,
    tts,
    usage,
)

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(admin.router, prefix="/admin", tags=["admin"])
api_router.include_router(chat.router, prefix="/chat", tags=["chat"])
api_router.include_router(devices.router, prefix="/devices", tags=["devices"])
api_router.include_router(health.router, prefix="", tags=["health"])
api_router.include_router(knowledge_base.router, prefix="/kb", tags=["knowledge-base"])
api_router.include_router(mcp.router, prefix="/mcp", tags=["mcp"])
api_router.include_router(memories.router, prefix="/memories", tags=["memories"])
api_router.include_router(microapps.router, prefix="/microapps", tags=["microapps"])
api_router.include_router(
    notifications.router, prefix="/notifications", tags=["notifications"]
)
api_router.include_router(
    scheduled_actions.router,
    prefix="/scheduled-actions",
    tags=["scheduled-actions"],
)
api_router.include_router(stt.router, prefix="/stt", tags=["stt"])
api_router.include_router(
    system_prompts.router, prefix="/system-prompts", tags=["system-prompts"]
)
api_router.include_router(tts.router, prefix="/tts", tags=["tts"])
api_router.include_router(usage.router, prefix="/usage", tags=["usage"])
api_router.include_router(rooms.router, prefix="/rooms", tags=["rooms"])
api_router.include_router(rooms_ws.router, tags=["rooms-ws"])
