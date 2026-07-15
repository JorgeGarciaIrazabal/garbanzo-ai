# Environment Variables (backend `.env`)

Settings are defined in `backend/app/core/config.py` (pydantic-settings). Keep
this file current: new env vars get documented here in the same commit (and in
`deploy/.env.example` if prod needs them).

```
SECRET_KEY=                      # Required — JWT signing key
DATABASE_URL=postgresql+asyncpg://garbanzo:garbanzo_dev@localhost:5432/garbanzo_ai

LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://localhost:11434   # host.docker.internal when in Docker

# STT: "local" (in-process faster-whisper) or "remote" (Docker container)
STT_MODE=local
STT_MODEL=Systran/faster-distil-whisper-large-v3
STT_DEVICE=auto          # "auto", "cpu", or "cuda"
STT_LANGUAGE=en
FASTER_WHISPER_URL=http://localhost:8010  # only used if stt_mode=remote

DEFAULT_TTS_VOICE=af_heart
DEFAULT_TTS_SPEED=1.0
KOKORO_MODEL_DIR=data/kokoro/models/v1_0
KOKORO_VOICES_DIR=data/kokoro/voices

ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=30

# Dev helpers
TEST_USER_EMAIL=          # Optional — auto-creates test user on startup
TEST_USER_PASSWORD=

# Admin promotion at startup (comma-separated emails)
ADMIN_EMAILS=

# Knowledge Base / RAG
EMBEDDING_MODEL=nomic-embed-text
EMBEDDING_DIM=768
KB_CHUNK_SIZE=1000
KB_CHUNK_OVERLAP=150
KB_TOP_K=5
KB_MAX_FILE_SIZE_MB=25
KB_BACKGROUND_EMBEDDING=true

# Firebase Cloud Messaging (push notifications)
FIREBASE_CREDENTIALS_PATH=firebase-service-account.json

# Multi-agent room auto-judge model (must be pulled in local Ollama)
ROOM_AUTO_JUDGE_MODEL=granite4:micro

# Micro-apps agentic workspace (dev points at a locally-managed repo)
MICROAPPS_REPO_PATH=/abs/path/to/micro-apps
MICROAPPS_OPENCODE_MODEL=ollama/kimi-k2.7-code:cloud
# Deployment-only (set via deploy/docker-compose.yml, not backend/.env):
#   MICROAPPS_GIT_URL      — clone URL; also enables the periodic sync job
#   MICROAPPS_PROXY_MODE   — serve the panel via the backend /micro-apps proxy
```

> Prod secrets (ngrok authtoken/domain, prod DB password, SECRET_KEY, git/SSH
> settings) live in `deploy/.env` — see `deploy/.env.example`.
