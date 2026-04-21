from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # App
    app_name: str = "Garbanzo AI"
    debug: bool = False
    host: str = "0.0.0.0"
    port: int = 8000

    # Security
    secret_key: str = "change-this-in-production"
    access_token_expire_minutes: int = 30

    # Database
    database_url: str = "postgresql+asyncpg://garbanzo:garbanzo_dev@localhost:5432/garbanzo_ai"

    # LLM
    llm_provider: str = "ollama"
    ollama_base_url: str = "http://host.docker.internal:11434"

    # Dev test user — set both to auto-create a user on startup
    test_user_email: str = ""
    test_user_password: str = ""

    # Voice services
    faster_whisper_url: str = "http://localhost:8010"  # only used if stt_mode=remote
    stt_mode: str = "local"  # "local" (in-process) or "remote" (Docker)
    stt_model: str = "Systran/faster-distil-whisper-large-v3"
    stt_device: str = "auto"  # "auto", "cpu", or "cuda"
    stt_language: str = "en"
    kokoro_url: str = "http://localhost:8020"  # kept for fallback / external kokoro
    default_tts_voice: str = "af_heart"
    default_tts_speed: float = 1.0

    # Kokoro native model paths (relative to backend/ or absolute)
    kokoro_model_dir: str = "data/kokoro/models/v1_0"
    kokoro_voices_dir: str = "data/kokoro/voices"

    # CORS
    cors_origins: str = "http://localhost:3000,http://localhost:8000"

    # Admin — comma-separated list of emails auto-promoted to is_admin=True on startup
    admin_emails: str = ""

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",")]

    @property
    def admin_emails_list(self) -> list[str]:
        return [
            e.strip().lower()
            for e in self.admin_emails.split(",")
            if e.strip()
        ]


@lru_cache
def get_settings() -> Settings:
    return Settings()
