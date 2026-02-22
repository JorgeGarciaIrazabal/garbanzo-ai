from functools import lru_cache
from typing import List

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

    # CORS
    cors_origins: str = "http://localhost:3000,http://localhost:8000"

    @property
    def cors_origins_list(self) -> List[str]:
        return [origin.strip() for origin in self.cors_origins.split(",")]


@lru_cache()
def get_settings() -> Settings:
    return Settings()
