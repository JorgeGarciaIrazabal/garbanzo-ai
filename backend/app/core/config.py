from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


def _split_csv(raw: str) -> list[str]:
    return [p.strip() for p in raw.split(",")]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # App / security / database — see docs/environment.md
    app_name: str = "Garbanzo AI"
    app_version: str = "0.0.0-dev"  # GET /api/v1/health; baked via APP_VERSION build arg
    debug: bool = False
    host: str = "0.0.0.0"
    port: int = 8000
    auto_error_reports: bool = True  # persist unexpected failures as admin bug reports
    github_repo: str = "JorgeGarciaIrazabal/garbanzo-ai"  # for GET /api/v1/version/latest
    secret_key: str = "change-this-in-production"
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 30
    database_url: str = "postgresql+asyncpg://garbanzo:garbanzo_dev@localhost:5432/garbanzo_ai"

    # LLM / context — see docs/environment.md
    llm_provider: str = "ollama"
    ollama_base_url: str = "http://host.docker.internal:11434"
    default_model: str = "glm-5.3-flash:cloud"
    memory_extraction_model: str = "glm-5.3:cloud"
    scheduled_action_model: str = "glm-5.3:cloud"
    llm_context_window: int = 100000  # min(model max, this) passed as num_ctx
    memory_token_budget: int = 4000  # dropped beyond budget, see docs/environment.md
    kb_token_budget: int = 8000
    memory_top_k: int = 20
    tool_result_max_chars: int = 32000  # truncated with marker before persistence
    room_auto_judge_model: str = "granite4:micro"  # see benchmark notes in docs/environment.md
    llm_image_max_dim: int = 1024  # downscaled before storage/vision model

    # Dev / location
    test_user_email: str = ""
    test_user_password: str = ""
    nominatim_url: str = "https://nominatim.openstreetmap.org"

    # Voice (STT/TTS) — see docs/environment.md
    faster_whisper_url: str = "http://localhost:8010"  # only if stt_mode=remote
    stt_mode: str = "local"  # local or remote
    stt_model: str = "Systran/faster-whisper-small"  # multilingual, not distil-large-v3
    stt_device: str = "auto"  # auto | cpu | cuda
    stt_language: str = "auto"  # auto or ISO code; per-request overrides
    stt_beam_size: int = 1
    stt_vad_max_duration: float = 10.0
    kokoro_url: str = "http://localhost:8020"
    default_tts_voice: str = "af_heart"
    default_tts_speed: float = 1.0
    tts_device: Literal["auto", "cpu", "cuda"] = "auto"
    kokoro_model_dir: str = "data/kokoro/models/v1_0"
    kokoro_voices_dir: str = "data/kokoro/voices"

    # Rate limiting (0 disables scope) — see docs/environment.md
    rate_limit_enabled: bool = False
    rate_limit_chat_per_minute: int = 20
    rate_limit_tts_per_minute: int = 30
    rate_limit_stt_per_minute: int = 30
    rate_limit_system_prompt_generate_per_minute: int = 10

    # CORS / admin / FCM
    cors_origins: str = "http://localhost:3000,http://localhost:8000"
    admin_emails: str = ""  # comma-separated, auto-promoted on startup
    firebase_credentials_path: str = "firebase-service-account.json"

    # Micro-apps workspace — see docs/environment.md
    microapps_repo_path: str = ""
    microapps_dev_port_base: int = 8100
    microapps_opencode_bin: str = "opencode"
    microapps_publish_remote: str = "origin"
    microapps_worktrees_dir: str = ".worktrees"
    microapps_opencode_model: str = "ollama/glm-5.3:cloud"
    microapps_git_url: str = ""
    microapps_pull_interval_minutes: int = 10
    microapps_proxy_mode: bool = False  # serve via backend /micro-apps proxy

    # Knowledge Base / RAG — see docs/environment.md
    embedding_model: str = "nomic-embed-text"
    embedding_dim: int = 768
    kb_chunk_size: int = 1000
    kb_chunk_overlap: int = 150
    kb_top_k: int = 10
    kb_max_file_size_mb: int = 25
    kb_min_score: float = 0.35  # hybrid fused score gate
    kb_semantic_weight: float = 0.7  # score = w*semantic + (1-w)*lexical
    kb_background_embedding: bool = True

    # Topic context — see docs/environment.md
    topic_context_enabled: bool = True
    topic_context_token_budget: int = 12000
    topic_curator_provider: str = "ollama"
    topic_curator_model: str = ""
    topic_curator_thinking: Literal["off", "low", "medium", "high"] = "medium"
    topic_realtime_model: str = ""
    topic_context_privacy_mode: Literal["local_only", "cloud_allowed"] = "local_only"
    topic_consolidation_interval_minutes: int = 60
    topic_bootstrap_timeout_seconds: float = 12.0
    topic_consolidation_concurrency: int = 2
    topic_realtime_batch_size: int = 100

    @property
    def cors_origins_list(self) -> list[str]:
        return _split_csv(self.cors_origins)

    @property
    def admin_emails_list(self) -> list[str]:
        return [e.lower() for e in _split_csv(self.admin_emails) if e]


_PLACEHOLDER_SECRETS = frozenset(
    {"", "change-this-in-production", "changeme", "change-me", "secret", "your-secret-key"}
)


def validate_startup_config(settings: "Settings") -> tuple[list[str], list[str]]:
    """Return (fatal, warnings). Fatal blocked when not debug."""
    fatal: list[str] = []
    warns: list[str] = []

    def _fatal_or_warn(msg: str) -> None:
        (fatal if not settings.debug else warns).append(msg)

    if settings.secret_key.strip().lower() in _PLACEHOLDER_SECRETS:
        _fatal_or_warn("SECRET_KEY is unset or a known placeholder — set a real key in .env")
    elif len(settings.secret_key) < 32:
        warns.append("SECRET_KEY is shorter than 32 characters — consider a longer random key")

    if settings.microapps_proxy_mode and not settings.microapps_repo_path:
        warns.append(
            "MICROAPPS_PROXY_MODE is on but MICROAPPS_REPO_PATH is empty — the /micro-apps proxy has nothing to serve"
        )
    return fatal, warns


def feature_summary(settings: "Settings") -> list[str]:
    """One line per optional feature for the startup log."""

    def flag(enabled: bool) -> str:
        return "enabled " if enabled else "disabled"

    llm_line = f"llm            : {settings.llm_provider} @ {settings.ollama_base_url} (default model: {settings.default_model})"
    stt_line = f"stt            : {flag(True)} (mode: {settings.stt_mode})"
    rows: list[tuple[str, bool, str]] = [
        ("push (FCM)     ", Path(settings.firebase_credentials_path).is_file(), ""),
        (
            "micro-apps     ",
            bool(settings.microapps_repo_path),
            " (proxy mode)" if settings.microapps_proxy_mode else "",
        ),
        ("microapps sync ", bool(settings.microapps_git_url), ""),
        ("test user      ", bool(settings.test_user_email and settings.test_user_password), ""),
    ]
    lines = [llm_line, stt_line]
    for label, enabled, suffix in rows:
        lines.append(f"{label}: {flag(enabled)}{suffix}")
    lines.append(f"admin emails   : {len(settings.admin_emails_list)} configured")
    lines.append(f"error reports  : {flag(settings.auto_error_reports)}")
    return lines


@lru_cache
def get_settings() -> Settings:
    return Settings()
