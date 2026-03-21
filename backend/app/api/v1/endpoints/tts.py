"""Text-to-speech API endpoints."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import Response

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.schemas.audio import SpeechRequest, VoiceList
from app.services.tts_service import TTSService

router = APIRouter()


@router.post(
    "/speak",
    summary="Synthesize speech from text",
)
async def speak(
    data: SpeechRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> Response:
    service = TTSService(base_url=settings.kokoro_url)
    try:
        audio_bytes = await service.speak(
            text=data.text,
            voice=data.voice,
            speed=data.speed,
            response_format=data.response_format,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"TTS service unavailable: {e}",
        ) from e
    return Response(content=audio_bytes, media_type="audio/mpeg")


@router.get(
    "/voices",
    response_model=VoiceList,
    summary="List available voices",
)
async def list_voices(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> VoiceList:
    service = TTSService(base_url=settings.kokoro_url)
    return VoiceList(voices=service.list_voices())


@router.get(
    "/health",
    summary="Check TTS service health",
)
async def health_check(
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, str]:
    service = TTSService(base_url=settings.kokoro_url)
    healthy = await service.health_check()
    return {"status": "ok" if healthy else "unavailable"}
