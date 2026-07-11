"""Speech-to-text API endpoints."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, UploadFile, status

from app.core.config import Settings, get_settings
from app.core.security import get_current_user
from app.schemas.audio import TranscriptionResponse

router = APIRouter()


@router.post(
    "/transcribe",
    response_model=TranscriptionResponse,
    summary="Transcribe audio to text",
)
async def transcribe_audio(
    file: UploadFile,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> TranscriptionResponse:
    audio_bytes = await file.read()
    if not audio_bytes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty audio file")
    try:
        if settings.stt_mode == "remote":
            from app.services.stt_service import RemoteSTTService

            service = RemoteSTTService(base_url=settings.faster_whisper_url)
            return await service.transcribe(
                audio_bytes, file.filename or "audio.wav", language=settings.stt_language
            )

        from app.services.stt_service import STTService

        service = await STTService.get_instance()
        return await service.transcribe(audio_bytes, file.filename or "audio.wav")
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"STT service unavailable: {e}",
        ) from e


@router.get(
    "/health",
    summary="Check STT service health",
)
async def health_check(
    settings: Annotated[Settings, Depends(get_settings)],
) -> dict[str, str]:
    try:
        if settings.stt_mode == "remote":
            from app.services.stt_service import RemoteSTTService

            service = RemoteSTTService(base_url=settings.faster_whisper_url)
            healthy = await service.health_check()
        else:
            from app.services.stt_service import STTService

            await STTService.get_instance()
            healthy = True
    except Exception:
        healthy = False
    return {"status": "ok" if healthy else "unavailable"}
