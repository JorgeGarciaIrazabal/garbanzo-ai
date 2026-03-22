from fastapi import APIRouter

from app.api.v1.endpoints import auth, chat, health, memories, stt, tts

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(chat.router, prefix="/chat", tags=["chat"])
api_router.include_router(health.router, prefix="", tags=["health"])
api_router.include_router(memories.router, prefix="/memories", tags=["memories"])
api_router.include_router(stt.router, prefix="/stt", tags=["stt"])
api_router.include_router(tts.router, prefix="/tts", tags=["tts"])
