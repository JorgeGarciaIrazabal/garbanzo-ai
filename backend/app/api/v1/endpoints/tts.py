"""Text-to-speech API endpoints."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import Response, StreamingResponse

from app.core.rate_limit import rate_limit
from app.core.security import get_current_user
from app.schemas.audio import SpeechRequest, VoiceList
from app.services.tts_service import TTSService

router = APIRouter()

_CONTENT_TYPES = {
    "mp3": "audio/mpeg",
    "opus": "audio/opus",
    "wav": "audio/wav",
    "pcm": "audio/pcm",
}


@router.post(
    "/speak",
    summary="Synthesize speech from text",
    dependencies=[Depends(rate_limit("tts"))],
)
async def speak(
    data: SpeechRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
) -> Response:
    service = await TTSService.get_instance()
    try:
        audio_bytes = await service.speak(
            text=data.text,
            voice=data.voice,
            speed=data.speed,
            response_format=data.response_format,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"TTS generation failed: {e}",
        ) from e
    content_type = _CONTENT_TYPES.get(data.response_format, "audio/mpeg")
    return Response(content=audio_bytes, media_type=content_type)


@router.post(
    "/speak/stream",
    summary="Stream synthesized speech audio",
    dependencies=[Depends(rate_limit("tts"))],
)
async def speak_stream(
    data: SpeechRequest,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
) -> StreamingResponse:
    service = await TTSService.get_instance()
    content_type = _CONTENT_TYPES.get(data.response_format, "audio/mpeg")
    return StreamingResponse(
        service.stream_speak(
            text=data.text,
            voice=data.voice,
            speed=data.speed,
            response_format=data.response_format,
        ),
        media_type=content_type,
        headers={
            "X-Accel-Buffering": "no",
            "Cache-Control": "no-cache",
            "Transfer-Encoding": "chunked",
        },
    )


@router.get(
    "/voices",
    response_model=VoiceList,
    summary="List available voices",
)
async def list_voices(
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
) -> VoiceList:
    service = await TTSService.get_instance()
    return VoiceList(voices=service.list_voices())


@router.get(
    "/health",
    summary="Check TTS service health",
)
async def health_check() -> dict[str, str]:
    try:
        await TTSService.get_instance()
        return {"status": "ok"}
    except Exception:
        return {"status": "unavailable"}
