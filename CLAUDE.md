# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **New machine?** See [`setup.md`](./setup.md) for a complete list of prerequisites (Flutter, uv, Docker, GStreamer, lld, Ollama, Android SDK, etc.).

## Commands

> **IMPORTANT:** Always use `just` commands. Never run `flutter`, `uvicorn`, `uv`, `pytest`, or `docker compose` directly — the justfile is the single source of truth for all dev tasks. Run `just` with no arguments to list all available recipes.

### Backend (FastAPI)
```bash
just be-dev          # Dev server with hot reload (port 8000)
just be-test         # Run pytest
just be-lint         # ruff check
just be-format       # ruff format
just be-install      # Install/sync backend deps
# Single test: cd backend; uv run pytest tests/path/test_file.py::test_name
```

### Frontend (Flutter)
```bash
just fe-run          # Run on Linux desktop (default)
just fe-run-chrome   # Run on Chrome (browser)
just fe-test         # Unit/widget tests
just fe-lint         # flutter analyze
just fe-build        # Build web → backend/web/ (for prod)
# Single test file: flutter test test/path/widget_test.dart
```

### Infrastructure & Combined
```bash
just dev             # Start everything: Docker + backend (with TTS) + frontend
just dev-deps        # Install Linux audio deps (GStreamer — run once)
just docker-up       # Start all Docker services (PostgreSQL + Faster Whisper STT)
just docker-up-db    # Start only PostgreSQL
just install         # Install all deps (backend + frontend)
just test            # Run backend + frontend unit tests
just db-migrate      # Apply all pending SQL migrations to the dev database
```

> **IMPORTANT:** PostgreSQL must always be started via Docker (`just docker-up` or `just docker-up-db`). Never attempt to start or connect to a host-installed PostgreSQL instance. If `just docker-up` fails because Docker isn't running, start Docker first (`sudo service docker start` in WSL2).

### Database Migrations

This project does **not** use Alembic. Schema is bootstrapped by `Base.metadata.create_all()` on startup (creates missing tables only — never alters existing ones).

When a SQLAlchemy model gains a new column, you must manually migrate existing databases:

1. Add an idempotent SQL file to `backend/migrations/` following the naming pattern `NNN_description.sql` (e.g. `002_add_title.sql`). Always use `ADD COLUMN IF NOT EXISTS`.
2. Run `just db-migrate` — applies every file in order against the dev database.
3. The production database (Docker `postgres-prod`) will be up-to-date automatically the next time `just android` rebuilds the backend image, because `create_all()` creates the table fresh. If the prod DB already exists, run the migration manually:
   ```bash
   docker exec -i garbanzo_ai_postgres_prod psql -U garbanzo -d garbanzo_ai_prod < backend/migrations/NNN_description.sql
   ```

> **IMPORTANT:** Always run `just db-migrate` after pulling changes that modify a SQLAlchemy model. The symptom of a missing migration is an `UndefinedColumnError` from asyncpg.

## Architecture

### Stack
- **Backend:** FastAPI (async) + SQLAlchemy/AsyncPG + PostgreSQL + JWT auth
- **Frontend:** Flutter (web/desktop) + Provider state management
- **LLM:** Ollama (default) via a pluggable provider pattern
- **TTS:** Kokoro (in-process, loaded on backend startup)
- **STT:** Faster Whisper (Docker container, port 8010)
- **Streaming:** Server-Sent Events (SSE) from backend to frontend

### Backend Layout (`backend/app/`)

```
core/       config.py (pydantic-settings), security.py (JWT/bcrypt)
api/v1/     endpoints/ auth.py, chat.py, health.py, stt.py, tts.py, memories.py  →  router.py
models/     SQLAlchemy ORM: User (email PK), Conversation, Message, UserMemory
schemas/    Pydantic I/O: auth.py, chat.py, memory.py
services/   chat_service.py, conversation_service.py, user_service.py
            llm_provider.py (abstract base + ProviderRegistry)
            ollama_provider.py (concrete impl)
            stt_service.py, tts_service.py
            memory_service.py, memory_extraction.py
db/         session.py (AsyncSession, init_db)
jobs/       extract_memories_job.py (daily at 2 AM via APScheduler)
scheduler.py
```

- `main.py` startup sequence: `init_db()` → create test user (if configured) → `TTSService.start_loading()` (background, non-blocking) → `start_scheduler()` (APScheduler).
- Serves Flutter web from `backend/web/` in production.
- All endpoints are under `/api/v1/`. Auth uses `get_current_user` dependency that validates `Authorization: Bearer <token>`.
- Adding a new LLM provider: implement `LLMProvider` ABC in `services/` and register it in `ProviderRegistry`.
- No Alembic/migrations — uses `Base.metadata.create_all()` for auto-schema creation on startup.

### API Endpoints

| Group | Endpoints |
|-------|-----------|
| Auth | `POST /auth/login`, `POST /auth/register` |
| Chat | `GET/POST /chat/conversations`, `POST /chat/conversations/{id}/chat` (SSE stream), `DELETE /chat/conversations/{id}/chat` (cancel stream) |
| Models | `GET /chat/models` |
| STT | `POST /stt/transcribe`, `GET /stt/health` |
| TTS | `POST /tts/speak`, `POST /tts/speak/stream`, `GET /tts/voices`, `GET /tts/health` |
| Memories | `POST /memories`, `GET /memories`, `GET/PATCH/DELETE /memories/{id}` |
| Health | `GET /health` |

All prefixed with `/api/v1/`.

### Frontend Layout (`lib/`)

```
main.dart           AuthGate: checks stored token → routes to Login or ChatPage
core/
  api_client.dart   Singleton HTTP client; resolves base URL; stores token in SharedPreferences
  auth_service.dart Singleton; login/register/logout; returns AuthResult
features/chat/
  models/           ChatMessage, Conversation, ChatAttachment, ModelInfo, ChatResponseChunk
  providers/        ChatProvider (ChangeNotifier), ModelProvider (ChangeNotifier)
  services/         chat_service.dart (CRUD + SSE streaming), audio_service.dart (STT/TTS)
  utils/            text_cleaner.dart (strips markdown/emojis before TTS)
  widgets/          ChatPage, ChatInputWidget, ChatMessageWidget, ConversationListWidget, …
features/memory/
  providers/        MemoryProvider
  pages/            MemoryPage (CRUD UI for user memories)
features/settings/
  providers/        SettingsProvider (voice, theme, auto-play toggles)
  widgets/          SettingsDrawer
pages/              LoginPage, RegisterPage
```

### Chat Message Flow

1. `ChatProvider.sendMessage()` optimistically adds user message, then calls `ChatService.streamChatResponse()`
2. `ChatService` POSTs to `/api/v1/chat/conversations/{id}/chat` with `Accept: text/event-stream`
3. Backend `ChatService` builds message history, calls `LLMProvider.stream_chat()`, yields SSE chunks
4. Chunk types: `chunk` (content), `thinking` (reasoning), `done` (metadata), `error`
5. `ChatProvider` accumulates content, upserts the assistant message live, then reloads conversation on `done`

### State Management

Two providers per `ChatPage` tree:
- **`ModelProvider`** — available models + selected model. Kept separate so model selection survives conversation switches.
- **`ChatProvider`** — conversations list, current conversation + messages, streaming state. Receives `onModelChanged` callback from `ModelProvider`.

Additional providers: `MemoryProvider` (user memories CRUD), `SettingsProvider` (voice, theme, persisted prefs).

### SSE Streaming Protocol

Each server event: `data: {"type":"chunk","content":"...","metadata":null}\n\n`
Terminal event: `data: {"type":"done","content":null,"metadata":{...}}\n\n`
Client parses lines, strips `data: ` prefix, skips `[DONE]` sentinel.

### Database Notes

- `Conversation.model` defaults to `"llama3.2"` — must match a model ID returned by `GET /api/v1/chat/models`.
- `Conversation.use_memory` (boolean) controls whether user memories are injected into LLM context.
- `Message.meta` is JSONB and stores token counts, generation timing, and thinking block content.
- `UserMemory` stores extracted/manual user memories with `content`, `source_conversation_id`, `is_active`.
- Conversations use soft delete (`is_deleted=True`), not hard delete.

### Auth Token Storage

Flutter stores the JWT in `SharedPreferences` under key `auth_token`. `ApiClient` reads it for every authenticated request.

### API Base URL Resolution (Flutter)

1. Compile-time `--dart-define=API_BASE_URL=...` (takes priority)
2. Debug mode → `http://localhost:8000`
3. Web release → relative to current origin

### Docker Services (`docker-compose.yml`)

- **PostgreSQL** — port 5432, credentials `garbanzo:garbanzo_dev`, database `garbanzo_ai`
- **Faster Whisper Server** — port 8010, CPU-based STT via `fedirz/faster-whisper-server`

Kokoro TTS runs in-process in the backend (not as a Docker service).

### Environment Variables (backend `.env`)

```
SECRET_KEY=           # Required — JWT signing key
DATABASE_URL=postgresql+asyncpg://garbanzo:garbanzo_dev@localhost:5432/garbanzo_ai
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://localhost:11434   # host.docker.internal when in Docker
FASTER_WHISPER_URL=http://localhost:8010
TEST_USER_EMAIL=      # Optional — auto-creates test user on startup
TEST_USER_PASSWORD=
ACCESS_TOKEN_EXPIRE_MINUTES=30
```

## E2E Testing

See `/e2e-testing` skill (`/e2e-testing` slash command). Uses Dart MCP to launch the app and Marionette MCP to drive UI interactions via the Flutter VM service URI.

- Always use `just be-dev` to start the backend before E2E tests.
- Flutter web integration tests (`-d chrome`) are not supported. Use `-d linux` (desktop).
- For E2E with a fixed port web server use `just fe-run-test-server`.
