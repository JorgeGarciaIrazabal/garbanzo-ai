"""Speech-to-text API endpoints."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Form, HTTPException, UploadFile, status

from app.core.config import Settings, get_settings
from app.core.rate_limit import rate_limit
from app.core.security import get_current_user
from app.schemas.audio import TranscriptionResponse

router = APIRouter()


@router.post(
    "/transcribe",
    response_model=TranscriptionResponse,
    summary="Transcribe audio to text",
    dependencies=[Depends(rate_limit("stt"))],
)
async def transcribe_audio(
    file: UploadFile,
    current_user: Annotated[dict[str, Any], Depends(get_current_user)],
    settings: Annotated[Settings, Depends(get_settings)],
    language: Annotated[
        str | None,
        Form(
            description=(
                'ISO language code (e.g. "en"), "auto", or omitted — '
                "both of the latter auto-detect the spoken language."
            )
        ),
    ] = None,
) -> TranscriptionResponse:
    audio_bytes = await file.read()
    if not audio_bytes:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Empty audio file")
    effective_language = language or settings.stt_language
    try:
        if settings.stt_mode == "remote":
            from app.services.stt_service import RemoteSTTService

            service = RemoteSTTService(base_url=settings.faster_whisper_url)
            return await service.transcribe(
                audio_bytes, file.filename or "audio.wav", language=effective_language
            )

        from app.services.stt_service import STTService

        service = await STTService.get_instance()
        return await service.transcribe(
            audio_bytes, file.filename or "audio.wav", language=effective_language
        )
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
