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

    # CORS
    cors_origins: str = "http://localhost:3000,http://localhost:8000"

    # Admin — comma-separated list of emails auto-promoted to is_admin=True on startup
    admin_emails: str = ""

    # Firebase Cloud Messaging (push notifications)
    # Path to the service-account JSON, relative to backend/ or absolute.
    # Leave empty to disable push notifications.
    firebase_credentials_path: str = "firebase-service-account.json"

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
        return [
            e.strip().lower()
            for e in self.admin_emails.split(",")
            if e.strip()
        ]


@lru_cache
def get_settings() -> Settings:
    return Settings()
