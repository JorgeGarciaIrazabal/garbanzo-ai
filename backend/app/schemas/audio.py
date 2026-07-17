from pydantic import BaseModel, Field


class TranscriptionResponse(BaseModel):
    text: str = Field(..., description="Transcribed text")
    language: str | None = Field(None, description="Detected language")
    duration: float | None = Field(None, description="Audio duration in seconds")


class SpeechRequest(BaseModel):
    text: str = Field(..., min_length=1, description="Text to synthesize")
    voice: str = Field(default="af_heart", description="Voice ID")
    speed: float = Field(default=1.0, ge=0.5, le=2.0, description="Speaking speed")
    response_format: str = Field(default="mp3", description="Audio format (mp3, wav, opus)")
    language: str | None = Field(
        default=None,
        description=(
            'Target ISO language code (e.g. "es"), or "auto"/omitted for no '
            "effect. When set and `voice` doesn't speak that language, the "
            "language's default voice is used instead — lets callers follow "
            "a detected/preferred language without knowing voice IDs "
            "(idea 13)."
        ),
    )


class VoiceInfo(BaseModel):
    id: str = Field(..., description="Voice identifier")
    name: str = Field(..., description="Human-readable voice name")
    language: str = Field(..., description="Voice language (display name)")
    lang_code: str = Field(..., description='ISO 639-1 language code (e.g. "en", "es")')


class VoiceList(BaseModel):
    voices: list[VoiceInfo] = Field(..., description="Available voices")
