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
STT_LANGUAGE=auto        # server default when a request omits `language`; "auto"
                         # detects per clip, or force an ISO code (e.g. "en").
                         # POST /stt/transcribe's per-request `language` field
                         # always overrides this for that request (idea 13).
FASTER_WHISPER_URL=http://localhost:8010  # only used if stt_mode=remote

DEFAULT_TTS_VOICE=af_heart
DEFAULT_TTS_SPEED=1.0
KOKORO_MODEL_DIR=data/kokoro/models/v1_0
KOKORO_VOICES_DIR=data/kokoro/voices

ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=30

# Persist unexpected authenticated backend/chat failures as admin-triaged bug
# reports. Set false to keep these failures in logs only.
AUTO_ERROR_REPORTS=true

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

# Reverse geocoding for opt-in coarse location (dynamic <context> block).
# Default is the public instance; self-host to keep coordinates on-prem.
NOMINATIM_URL=https://nominatim.openstreetmap.org

# Firebase Cloud Messaging (push notifications)
FIREBASE_CREDENTIALS_PATH=firebase-service-account.json

# Desktop auto-updater (idea 19)
GITHUB_REPO=JorgeGarciaIrazabal/garbanzo-ai  # owner/name whose Releases feed
                                             # GET /api/v1/version/latest
# APP_VERSION — reported by GET /api/v1/health. Not set by hand: deploys bake
# the release tag in via the Docker build arg (scripts/deploy.sh); defaults to
# "0.0.0-dev" outside a release image.

# Multi-agent room auto-judge model (must be pulled in local Ollama)
ROOM_AUTO_JUDGE_MODEL=granite4:micro

# Micro-apps agentic workspace (dev points at a locally-managed repo)
MICROAPPS_REPO_PATH=/abs/path/to/micro-apps
MICROAPPS_OPENCODE_MODEL=ollama/kimi-k2.7-code:cloud
# Deployment-only (set via deploy/docker-compose.yml, not backend/.env):
#   MICROAPPS_GIT_URL      — clone URL; also enables the periodic sync job
#   MICROAPPS_PROXY_MODE   — serve the panel via the backend /micro-apps proxy
# Deploy-script-only (read from deploy/.env by scripts/deploy.sh on the host):
#   CHANGELOG_OPENCODE_MODEL — opencode model that writes CHANGELOG.md on deploy
#                              (unset → opencode's own default; `opencode models`)
```

> Prod secrets (ngrok authtoken/domain, prod DB password, SECRET_KEY, git/SSH
> settings) live in `deploy/.env` — see `deploy/.env.example`.
