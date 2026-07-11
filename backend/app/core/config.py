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
    refresh_token_expire_days: int = 30

    # Database
    database_url: str = "postgresql+asyncpg://garbanzo:garbanzo_dev@localhost:5432/garbanzo_ai"

    # LLM
    llm_provider: str = "ollama"
    ollama_base_url: str = "http://host.docker.internal:11434"

    # Default model for new conversations / scheduled actions / background
    # jobs when no explicit model is chosen. Must match a model ID returned
    # by GET /api/v1/chat/models.
    default_model: str = "llama3.2"

    # Context window cap in tokens. The effective window for a conversation
    # is min(model's maximum, this value); it is passed to the provider as
    # num_ctx so the runtime actually allocates that window (Ollama otherwise
    # silently runs at its own default, typically 4096, regardless of the
    # model's maximum). Raising this increases RAM/VRAM use per request.
    llm_context_window: int = 8192

    # Token budgets for context injected into the system prompt. Memory /
    # KB entries beyond the budget are dropped (in list order) so a large
    # memory store or document base can't crowd out the conversation itself.
    memory_token_budget: int = 1000
    kb_token_budget: int = 2000

    # Maximum memories injected per message (most relevant first). The token
    # budget above still applies on top of this count cap.
    memory_top_k: int = 8

    # Tool results larger than this are truncated (with an explicit marker)
    # before being persisted and fed back to the model, so a tool returning
    # megabytes can't blow the context window or the message table.
    tool_result_max_chars: int = 8000

    # Model used for internal classification calls (e.g. the "should this
    # auto-agent jump in?" judge in multi-agent rooms). Override via env var
    # (ROOM_AUTO_JUDGE_MODEL) if a different model is preferred. Must be
    # pulled in the local Ollama instance — pull with
    # ``ollama pull granite4:micro``.
    #
    # Picked via ``backend/scripts/benchmark_auto_judge.py`` against 43
    # labeled scenarios (easy + hard + creative-request edge cases):
    #   granite4:micro  v1_strict  → 90.7% acc · 1.3s · 3 FP / 1 FN  ← chosen
    #   phi4-mini       v1_strict  → 90.7% acc · 1.5s · 0 FP / 4 FN
    #   granite4:micro  v2_balanced→ 88.4% acc · 1.5s · 5 FP / 0 FN
    #   gemma3:4b       v1_strict  → 86.0% acc · 1.1s · 6 FP / 0 FN
    #   llama3.2:3b     v2_balanced→ 83.7% acc · 1.0s · 0 FP / 7 FN
    #   gemma4:e2b / qwen3:*       → broken with Ollama structured output
    #   gemma3:1b                  → too small to follow rules
    #
    # Granite4 was picked over phi4-mini even at the same accuracy because
    # phi4-mini consistently refuses creative-writing requests ("write a
    # story", "tell a joke", roleplay) — the exact pattern users care about.
    # Granite4's failure mode is mild over-eagerness on judgment-call
    # scenarios (3 FP), which is far less frustrating than an agent
    # ignoring an explicit request.
    #
    # The best prompt is model-dependent — see the corresponding prompt
    # block in ``room_chat_service.py`` for the v1_strict copy.
    room_auto_judge_model: str = "granite4:micro"

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

    # Rate limiting for expensive endpoints (chat/TTS/STT), keyed by user.
    # Off by default so dev stays unlimited; 0 disables a single scope.
    rate_limit_enabled: bool = False
    rate_limit_chat_per_minute: int = 20
    rate_limit_tts_per_minute: int = 30
    rate_limit_stt_per_minute: int = 30

    # CORS
    cors_origins: str = "http://localhost:3000,http://localhost:8000"

    # Admin — comma-separated list of emails auto-promoted to is_admin=True on startup
    admin_emails: str = ""

    # Firebase Cloud Messaging (push notifications)
    # Path to the service-account JSON, relative to backend/ or absolute.
    # Leave empty to disable push notifications.
    firebase_credentials_path: str = "firebase-service-account.json"

    # Micro-Apps Agentic Workspace
    # Absolute path to the user's micro-apps monorepo (Vite+React, deployed to
    # GitHub Pages). Empty ⇒ the whole feature is disabled and every
    # /microapps endpoint returns a clear "feature disabled" error.
    microapps_repo_path: str = ""
    # Base TCP port for per-user dev servers. Each user's worktree gets a
    # stable port derived from base + a hash of their slug.
    microapps_dev_port_base: int = 8100
    # Executable used to spawn the headless opencode agent (`opencode serve`).
    microapps_opencode_bin: str = "opencode"
    # Git remote that publish/revert operate against.
    microapps_publish_remote: str = "origin"
    # Directory (relative to the repo root) that holds per-user worktrees.
    microapps_worktrees_dir: str = ".worktrees"
    # Model id passed to opencode's session request, in "provider/name" form.
    # The bare name is also written into the seeded opencode.json under the
    # "ollama" provider.
    microapps_opencode_model: str = "ollama/kimi-k2.7-code:cloud"
    # Git URL used by deployments to clone the repo into MICROAPPS_REPO_PATH on
    # first boot. Setting it also enables the periodic sync job (fetch +
    # fast-forward + rebase of clean worktrees). Leave empty in dev, where the
    # developer manages the repo themselves.
    microapps_git_url: str = ""
    # Minutes between periodic syncs of the deployed repo clone. Only active
    # when microapps_git_url is set; 0 disables the job.
    microapps_pull_interval_minutes: int = 10
    # Serve micro-app dev servers through the backend's authenticated
    # /micro-apps reverse proxy instead of having the client hit the per-user
    # dev port directly. Required behind a single public tunnel (prod); off in
    # dev where the LAN port is reachable.
    microapps_proxy_mode: bool = False

    # Knowledge Base / RAG
    embedding_model: str = "nomic-embed-text"
    embedding_dim: int = 768
    kb_chunk_size: int = 1000  # characters
    kb_chunk_overlap: int = 150  # characters
    kb_top_k: int = 5  # top-K chunks injected per message
    kb_max_file_size_mb: int = 25
    # Minimum fused score for a chunk to be injected — keeps barely-related
    # chunks from polluting the context. With kb_semantic_weight=0.7, 0.35
    # corresponds to ~0.5 cosine similarity when there is no lexical match.
    kb_min_score: float = 0.35
    # Hybrid retrieval fusion: score = w*semantic + (1-w)*lexical, where
    # lexical is Postgres ts_rank_cd normalized to [0,1).
    kb_semantic_weight: float = 0.7
    # When False, ``create_document`` skips the background embedding task.
    # Useful for tests that don't want to exercise the embedder.
    kb_background_embedding: bool = True

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",")]

    @property
    def admin_emails_list(self) -> list[str]:
        return [e.strip().lower() for e in self.admin_emails.split(",") if e.strip()]


# Secret values that are obviously placeholders and must never reach prod.
_PLACEHOLDER_SECRETS = frozenset(
    {
        "",
        "change-this-in-production",
        "changeme",
        "change-me",
        "secret",
        "your-secret-key",
    }
)


def validate_startup_config(settings: "Settings") -> tuple[list[str], list[str]]:
    """Check settings for boot-time problems.

    Returns ``(fatal, warnings)`` message lists. Fatal issues are ones the
    caller should refuse to start on when ``settings.debug`` is False —
    catching them at boot beats a placeholder JWT key silently signing
    tokens in prod.
    """
    fatal: list[str] = []
    warns: list[str] = []

    if settings.secret_key.strip().lower() in _PLACEHOLDER_SECRETS:
        msg = "SECRET_KEY is unset or a known placeholder — set a real key in .env"
        (warns if settings.debug else fatal).append(msg)
    elif len(settings.secret_key) < 32:
        warns.append("SECRET_KEY is shorter than 32 characters — consider a longer random key")

    if settings.microapps_proxy_mode and not settings.microapps_repo_path:
        warns.append(
            "MICROAPPS_PROXY_MODE is on but MICROAPPS_REPO_PATH is empty — "
            "the /micro-apps proxy has nothing to serve"
        )

    return fatal, warns


def feature_summary(settings: "Settings") -> list[str]:
    """One line per optional feature, for the startup log."""
    from pathlib import Path

    def flag(enabled: bool) -> str:
        return "enabled " if enabled else "disabled"

    return [
        f"llm            : {settings.llm_provider} @ {settings.ollama_base_url} "
        f"(default model: {settings.default_model})",
        f"stt            : {flag(True)} (mode: {settings.stt_mode})",
        f"push (FCM)     : {flag(Path(settings.firebase_credentials_path).is_file())}",
        f"micro-apps     : {flag(bool(settings.microapps_repo_path))}"
        + (" (proxy mode)" if settings.microapps_proxy_mode else ""),
        f"microapps sync : {flag(bool(settings.microapps_git_url))}",
        f"test user      : {flag(bool(settings.test_user_email and settings.test_user_password))}",
        f"admin emails   : {len(settings.admin_emails_list)} configured",
    ]


@lru_cache
def get_settings() -> Settings:
    return Settings()
