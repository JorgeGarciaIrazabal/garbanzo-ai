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
just be-upgrade      # Upgrade backend deps
just be-run          # Production server (port 8000)
# Single test: cd backend; uv run pytest tests/path/test_file.py::test_name
```

### Frontend (Flutter)
```bash
just fe-run              # Run on Linux desktop (default)
just fe-run-chrome       # Run on Chrome (browser)
just fe-run-ngrok URL    # Run against an ngrok backend URL
just fe-test             # Unit/widget tests
just fe-integration-test # Run integration_test/app_test.dart on Linux
just fe-test-all         # Unit + integration tests
just fe-lint             # flutter analyze
just fe-build            # Build web → backend/web/ (for prod)
just fe-clean            # Clean Flutter build files
# Single test file: flutter test test/path/widget_test.dart
```

### Infrastructure & Combined
```bash
just dev             # Start Docker + backend + frontend on Android (real device or emulator)
just dev-web         # Start Docker + backend + frontend in Chrome for web development
just dev-deps        # Install Linux audio deps (GStreamer — run once)
just docker-up       # Start all Docker services (PostgreSQL + Faster Whisper STT)
just docker-up-db    # Start only PostgreSQL
just install         # Install all deps (backend + frontend)
just test            # Run backend + frontend unit tests
```

### Deployment
```bash
just deploy          # Deploy local main: web build → backend image → prod stack → APK
just deploy-status   # Prod compose ps + local & public health checks
just deploy-logs     # Tail prod logs (optionally: backend | postgres | ngrok)
just deploy-restart  # Restart prod services (keeps data)
just deploy-down     # Stop the prod stack (keeps volumes/data)
```

> **IMPORTANT:** PostgreSQL must always be started via Docker (`just docker-up` or `just docker-up-db`). Never attempt to start or connect to a host-installed PostgreSQL instance. If `just docker-up` fails because Docker isn't running, start Docker first (`sudo service docker start` in WSL2).

### Database Migrations

This project does **not** use Alembic. Schema comes from two automatic steps at backend startup (`init_db()`):

1. `Base.metadata.create_all()` — creates missing tables (never alters existing ones).
2. `run_migrations()` (`backend/app/db/migrations.py`) — applies `backend/migrations/*.sql` in filename order, once each, tracked in a `schema_migrations` table.

When a SQLAlchemy model gains a new column, add an idempotent SQL file to `backend/migrations/` following the naming pattern `NNN_description.sql` (e.g. `012_add_title.sql`). Always use `ADD COLUMN IF NOT EXISTS`. That's it — every database (dev and prod) picks it up on the next backend start. A failing migration intentionally crashes the backend at startup so it never serves a half-migrated schema.

## Deployment

One command ships web + backend + Android simultaneously — see `deploy/README.md` for first-time setup (ngrok authtoken/domain, credentials, SSH key) and operations (rollback, psql, data recovery).

### `just deploy` (`scripts/deploy.sh`)
1. Snapshots the **local `main` branch** into a temp git worktree (works from any branch with a dirty tree).
2. Builds Flutter web into the worktree → `docker build garbanzo-backend:latest` + `:<short-sha>` (web baked in; no secrets in the image).
3. `docker compose up -d` on `deploy/docker-compose.yml` (project `garbanzo-prod`, env from gitignored `deploy/.env`).
4. Waits for local health (`127.0.0.1:8001`) and public health (`https://$NGROK_DOMAIN`).
5. Builds the APK with the ngrok URL baked in and versionCode = `git rev-list --count main` → `dist/garbanzo-ai-<sha>.apk`.

### Prod stack (`deploy/docker-compose.yml`, project `garbanzo-prod`)
- **postgres** (pgvector, own volume, no host port) + **ollama** (`ollama/ollama`, own `ollama_data` volume, no host port — fully containerized, not the host Ollama install) + **backend** (image `garbanzo-backend`, 127.0.0.1:8001 for smoke tests) + **ngrok** (`ngrok/ngrok` container tunneling the static domain to `backend:8000`, auto-restarting).
- Fully isolated from dev: separate compose project, database, network, volumes.
- On first deploy, pull the models the app needs into the `ollama` container (see `deploy/README.md`) — the volume starts empty. Cloud models (`*:cloud`) need a one-time `ollama signin` inside the container; the credential persists in `ollama_data`.
- Models (Kokoro/Whisper) persist in the `hf_cache` volume; Firebase creds are mounted read-only.
- Micro-apps in prod: repo cloned into the `microapps_repo` volume (`MICROAPPS_GIT_URL`), synced periodically by an APScheduler job, served through the backend's authenticated `/micro-apps` reverse proxy (`MICROAPPS_PROXY_MODE=true`), publishing over a read-only-mounted host SSH key.

## Architecture

### Stack
- **Backend:** FastAPI (async) + SQLAlchemy/AsyncPG + PostgreSQL (pgvector) + JWT auth
- **Frontend:** Flutter (web/desktop/Android) + Provider state management + Freezed data classes
- **LLM:** Ollama (default) via a pluggable provider pattern
- **TTS:** Kokoro (in-process, loaded on backend startup)
- **STT:** Faster Whisper (in-process local by default; remote Docker fallback on port 8010)
- **Streaming:** Server-Sent Events (SSE) from backend to frontend
- **Push Notifications:** Firebase Cloud Messaging (FCM) via `fcm_service.py`
- **Scheduler:** APScheduler for daily memory extraction + user-defined scheduled actions
- **Knowledge Base:** pgvector-based semantic search (`nomic-embed-text` embeddings)
- **Rooms:** Multi-agent chat rooms with WebSocket transport (`rooms_ws.py`)

### Backend Layout (`backend/app/`)

```
core/          config.py (pydantic-settings), security.py (JWT/bcrypt)
api/v1/        endpoints/
               auth.py, admin.py, chat.py, devices.py, health.py,
               knowledge_base.py, mcp.py, memories.py, notifications.py,
               rooms.py, rooms_ws.py, scheduled_actions.py, stt.py,
               system_prompts.py, tts.py, usage.py
               →  router.py
models/        SQLAlchemy ORM:
               User, Conversation, Message, UserMemory,
               SystemPromptTemplate, MCPServer, DeviceToken,
               Notification, NotificationPreferences, ScheduledAction,
               KnowledgeDocument, KnowledgeChunk,
               Room, RoomMember, RoomAgent, RoomMessage
schemas/       Pydantic I/O: auth.py, chat.py, memory.py, admin.py, mcp.py,
               system_prompt.py, device.py, notification.py, scheduled_action.py,
               usage.py, room.py, knowledge_base.py
services/      chat_service.py, conversation_service.py, user_service.py
               llm_provider.py (abstract base + ProviderRegistry)
               ollama_provider.py (concrete impl)
               stt_service.py, tts_service.py
               memory_service.py, memory_extraction.py
               system_prompt_service.py, mcp_service.py
               knowledge_base_service.py, embedding_provider.py
               room_service.py, room_chat_service.py, room_connection_manager.py
               scheduled_action_service.py, usage_service.py
               fcm_service.py, device_service.py, notification_service.py
db/            base.py, session.py (AsyncSession, init_db)
jobs/          extract_memories_job.py (daily at 2 AM)
               scheduled_action_job.py (user-defined cron/one-shot actions)
scheduler.py   APScheduler lifecycle + action registration
```

- `main.py` startup sequence:
  1. `init_db()` — create missing tables
  2. `_ensure_test_user()` — create test user (if `TEST_USER_EMAIL` + `TEST_USER_PASSWORD` configured)
  3. `_promote_admin_emails()` — promote matching emails to `is_admin=True`
  4. `seed_builtin_templates_task()` — seed built-in system prompt templates
  5. `TTSService.start_loading()` — background, non-blocking
  6. `STTService.start_loading()` — background, non-blocking (skips if `stt_mode=remote`)
  7. `start_scheduler()` — APScheduler for memory extraction + scheduled actions
  8. `init_firebase()` — FCM push notifications (no-op if credentials missing)
- Serves Flutter web from `backend/web/` in production.
- All endpoints are under `/api/v1/`. Auth uses `get_current_user` dependency that validates `Authorization: Bearer <token>`.
- Adding a new LLM provider: implement `LLMProvider` ABC in `services/` and register it in `ProviderRegistry`.
- No Alembic/migrations — uses `Base.metadata.create_all()` for auto-schema creation on startup.

### API Endpoints

| Group | Endpoints |
|-------|-----------|
| **Auth** | `POST /auth/login`, `POST /auth/register`, `GET /auth/me` |
| **Admin** | `GET /admin/users`, `PATCH /admin/users/{email}`, `GET /admin/mcp-servers`, `POST /admin/mcp-servers`, `PATCH /admin/mcp-servers/{id}`, `DELETE /admin/mcp-servers/{id}`, `POST /admin/mcp-servers/{id}/test-connection` |
| **Chat** | `GET/POST /chat/conversations`, `GET /chat/conversations/search`, `GET /chat/conversations/{id}`, `PATCH /chat/conversations/{id}`, `DELETE /chat/conversations/{id}`, `POST /chat/conversations/{id}/chat` (SSE stream), `POST /chat/conversations/{id}/messages/{mid}/regenerate`, `POST /chat/conversations/{id}/messages/{mid}/edit`, `POST /chat/conversations/{id}/messages/{mid}/branch`, `DELETE /chat/conversations/{id}/chat` (cancel stream), `GET /chat/models`, `GET /chat/health/llm` |
| **System Prompts** | `GET /system-prompts/templates`, `POST /system-prompts/templates`, `PATCH /system-prompts/templates/{id}`, `DELETE /system-prompts/templates/{id}`, `GET /system-prompts/user-default`, `PUT /system-prompts/user-default` |
| **STT** | `POST /stt/transcribe`, `GET /stt/health` |
| **TTS** | `POST /tts/speak`, `POST /tts/speak/stream`, `GET /tts/voices`, `GET /tts/health` |
| **Memories** | `POST /memories`, `GET /memories`, `GET /memories/{id}`, `PATCH /memories/{id}`, `DELETE /memories/{id}` |
| **Knowledge Base** | `POST /kb/documents`, `GET /kb/documents`, `GET /kb/documents/{id}`, `DELETE /kb/documents/{id}`, `GET /kb/search` |
| **Rooms** | `POST /rooms`, `GET /rooms`, `GET /rooms/search`, `GET /rooms/{id}`, `PATCH /rooms/{id}`, `DELETE /rooms/{id}`, `GET /rooms/{id}/members`, `POST /rooms/{id}/members`, `DELETE /rooms/{id}/members/{email}`, `GET /rooms/{id}/agents`, `POST /rooms/{id}/agents`, `PATCH /rooms/{id}/agents/{id}`, `DELETE /rooms/{id}/agents/{id}`, `GET /rooms/{id}/messages`, `POST /rooms/{id}/chat`, `GET /rooms/{id}/export`, `WS /rooms/{id}` |
| **MCP (Tools)** | `GET /mcp/tools` |
| **Notifications** | `GET /notifications`, `GET /notifications/unread-count`, `POST /notifications/read-all`, `PATCH /notifications/{id}/read`, `DELETE /notifications/{id}`, `GET /notifications/preferences`, `PATCH /notifications/preferences` |
| **Devices** | `POST /devices/register`, `DELETE /devices/register` |
| **Scheduled Actions** | `POST /scheduled-actions`, `GET /scheduled-actions`, `GET /scheduled-actions/{id}`, `PATCH /scheduled-actions/{id}`, `DELETE /scheduled-actions/{id}` |
| **Usage** | `GET /usage/summary` |
| **Health** | `GET /health` |

All prefixed with `/api/v1/`.

### Frontend Layout (`lib/`)

```
main.dart            AuthGate: checks token → routes to Login or ChatPage
                     PushService.init() at startup; registers device on login
core/
  api_client.dart    Singleton HTTP client ( dio ); resolves base URL;
                     stores token in SharedPreferences
  auth_service.dart  Singleton; login/register/logout; caches current user
  responsive.dart    Breakpoint helpers for desktop / tablet / mobile UI
features/chat/
  models/            ChatMessage, Conversation, ChatAttachment, ModelInfo,
                     ChatResponseChunk, SystemPromptTemplate, SearchResult
                     ( all use freezed + json_serializable )
  providers/         ChatProvider, ModelProvider, SearchProvider,
                     SystemPromptProvider
  services/          chat_service.dart (CRUD + SSE streaming),
                     audio_service.dart (STT/TTS)
  utils/             text_cleaner.dart (strips markdown/emojis before TTS)
  widgets/           ChatPage, ChatInputWidget, ChatMessageWidget,
                     ConversationListWidget, ModelSelectorWidget,
                     SearchWidget, SearchResultsWidget, SystemPromptBanner,
                     SystemPromptEditorDialog, ContextWindowIndicator,
                     ContextSummaryWidget, MemoryToggleWidget,
                     RememberThisButton, EmptyChatState, ImageViewer,
                     MermaidDiagram, MarkdownWidget,
                     message/ ThinkingContent, BranchButton, EditButton,
                     RegenerateButton, SpeakButton, CopyButton,
                     MessageMetadata, MessageContent, AttachmentDisplay
features/memory/
  providers/         MemoryProvider
  pages/             MemoryPage (CRUD UI for user memories)
features/settings/
  providers/         SettingsProvider (voice, theme, auto-play toggles)
features/knowledge_base/
  pages/             KnowledgeBasePage
  providers/         KnowledgeBaseProvider
  services/          knowledge_base_service.dart
features/notifications/
  pages/             NotificationsPage
  providers/         NotificationProvider
  services/          notification_api_service.dart, push_service.dart
  models/            AppNotification
  widgets/           NotificationBell
features/usage/
  pages/             UsagePage
  providers/         UsageProvider
  services/          usage_service.dart
  models/            UsageSummary
features/rooms/
  pages/             RoomsPage, RoomChatPage
  providers/         RoomProvider
  services/          room_service.dart, room_socket_service.dart (WebSocket)
  models/            RoomModels
  widgets/           RoomsSidebar, RoomsListView, CreateRoomDialog,
                     AddAgentDialog, RoomComposeBar, RoomMessageBubble
features/admin/
  pages/             AdminPage
  providers/         AdminProvider
  services/          admin_service.dart
  models/            AdminUser, MCPServer
  widgets/           UsersTab, MCPServersTab, MCPServerDialog
features/tools/
  pages/             SkillsLibraryPage
  providers/         ToolProvider
  models/            MCPTool
pages/               LoginPage, RegisterPage
```

### Chat Message Flow

1. `ChatProvider.sendMessage()` optimistically adds the user message, then calls `ChatService.streamChatResponse()`
2. `ChatService` POSTs to `/api/v1/chat/conversations/{id}/chat` with `Accept: text/event-stream`
3. Backend `ChatService` builds message history, calls `LLMProvider.stream_chat()`, yields SSE chunks
4. **Chunk types:**
   - `chunk` — text content
   - `thinking` — reasoning / thought blocks
   - `tool_call` — MCP tool invocation requested by the assistant
   - `tool_result` — result returned from an MCP tool call
   - `done` — terminal event with metadata
   - `error` — failure metadata
5. `ChatProvider` accumulates content, upserts the assistant message live, renders tool call UI inline, then reloads conversation on `done`
6. **Regenerate** — `POST /chat/conversations/{id}/messages/{mid}/regenerate` re-streams the last assistant message
7. **Edit** — `POST /chat/conversations/{id}/messages/{mid}/edit` updates a user message and truncates all later messages, then re-streams
8. **Branch** — `POST /chat/conversations/{id}/messages/{mid}/branch` creates a new conversation from a given message ID

### WebSocket Rooms (Multi-Agent)

1. `RoomSocketService` opens a WebSocket to `ws://host/rooms/{room_id}` ( authenticated via `?token=<jwt>` query param )
2. Messages are broadcast as JSON: `{ "id", "sender_user_id", "sender_agent_id", "content", "created_at", "type" }`
3. Agent responses stream over the same socket with `type="chunk"`; terminal messages have `role="assistant"`
4. REST fallback at `POST /rooms/{id}/chat` exists for smoke-testing but returns non-streaming JSON

### State Management

Two main providers per `ChatPage` tree:
- **`ModelProvider`** — available models + selected model. Kept separate so model selection survives conversation switches.
- **`ChatProvider`** — conversations list, current conversation + messages, streaming state. Receives `onModelChanged` callback from `ModelProvider`.

Additional providers:
- **`MemoryProvider`** — user memories CRUD
- **`SettingsProvider`** — voice, theme, auto-play toggles; persisted via `SharedPreferences`
- **`SearchProvider`** — conversation search results
- **`SystemPromptProvider`** — system prompt template library + user default
- **`NotificationProvider`** — in-app notifications + unread count
- **`RoomProvider`** — room list, room details, room messages
- **`AdminProvider`** — user admin portal (users list, MCP server management)
- **`KnowledgeBaseProvider`** — document uploads + semantic search
- **`UsageProvider`** — token usage summary
- **`ToolProvider`** — available MCP tools

### SSE Streaming Protocol

Each server event: `data: {"type":"chunk","content":"...","metadata":null}\n\n`
Terminal event: `data: {"type":"done","content":null,"metadata":{...}}\n\n`
Client parses lines, strips `data: ` prefix, skips `[DONE]` sentinel.

On client disconnect mid-stream, the backend accumulates content and sends an FCM push notification with a truncated preview.

### Database Notes

- `User` uses `email` as the primary key. Fields: `email`, `hashed_password`, `full_name`, `is_admin`, `is_disabled`, `default_system_prompt`, `default_model`, `created_at`.
- `Conversation.model` defaults to `"llama3.2"` — must match a model ID returned by `GET /api/v1/chat/models`.
- `Conversation.use_memory` (boolean) controls whether user memories are injected into LLM context.
- `Conversation.use_knowledge_base` (boolean) controls whether KB chunks are injected.
- `Conversation.is_pinned` (boolean) surfaces conversations in the sidebar.
- `Conversation.context_summary` stores a rolling summary to save context-window space.
- `Conversation.enabled_tools` (JSONB) stores per-conversation MCP tool whitelists: `null` = all enabled, `[]` = none, `["srv:tool"]` = subset.
- `Message.meta` is JSONB and stores token counts, generation timing, thinking block content.
- `Message.role` can be: `user`, `assistant`, `system`, `tool_call`, `tool_result`.
- `UserMemory` stores extracted/manual user memories with `content`, `source_conversation_id`, `is_active`.
- `KnowledgeDocument` / `KnowledgeChunk` store uploaded documents and vector embeddings for RAG.
- `Room`, `RoomMember`, `RoomAgent`, `RoomMessage` support multi-person/agent chat rooms.
- `ScheduledAction` stores user-defined cron or one-shot prompts.
- `Notification` / `NotificationPreferences` support in-app + FCM push notifications.
- `DeviceToken` stores FCM tokens per user per platform.
- `MCPServer` stores registered MCP server configs (managed by admin).
- `SystemPromptTemplate` stores built-in and user-created prompt templates.
- Conversations use soft delete (`is_deleted=True`), not hard delete.
- PostgreSQL uses `pgvector` extension for embedding storage.

### Auth Token Storage

Flutter stores the JWT in `SharedPreferences` under key `auth_token`. `ApiClient` reads it for every authenticated request. `AuthService` caches the current user (including `is_admin`) in memory after login.

### API Base URL Resolution (Flutter)

1. Compile-time `--dart-define=API_BASE_URL=...` (takes priority)
2. Debug mode → `http://localhost:8000`
3. Web release → relative to current origin

For `just dev` on Android: automatically resolves to host LAN IP for real devices or `10.0.2.2:8000` for emulators.

### Docker Services

Dev (`docker-compose.yml`, project `garbanzo-ai`):
- **PostgreSQL** (`garbanzo_ai_postgres`) — port 5432, image `pgvector/pgvector:pg16`, credentials `garbanzo:garbanzo_dev`, database `garbanzo_ai`
- **Faster Whisper Server** (`garbanzo_ai_whisper`) — port 8010, CPU-based STT via `fedirz/faster-whisper-server:latest-cpu` (only used when `STT_MODE=remote`)

Prod (`deploy/docker-compose.yml`, project `garbanzo-prod` — fully separate DB/volumes/network):
- **postgres** — `pgvector/pgvector:pg16`, database `garbanzo_ai_prod`, no host port
- **backend** — image `garbanzo-backend:latest` built by `just deploy`, 127.0.0.1:8001
- **ngrok** — tunnels the static domain to `backend:8000`, auto-restarting

> Kokoro TTS runs **in-process** in the backend (not a Docker service). STT can also run in-process (`stt_mode=local`, the default) bypassing the Docker container entirely.

### Environment Variables (backend `.env`)

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

## E2E Testing

See `/e2e-testing` skill (`/e2e-testing` slash command). Uses Dart MCP to launch the app and Marionette MCP to drive UI interactions via the Flutter VM service URI.

- Always use `just be-dev` to start the backend before E2E tests.
- Flutter web integration tests (`-d chrome`) are not supported. Use `-d linux` (desktop).
- For E2E with a fixed port web server use `just fe-run-test-server`.

## Flutter Code Generation

The project uses `freezed` and `json_serializable` for immutable data models and JSON serialization.

After modifying any model file (`.dart` files with `@freezed` annotations), run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Or, for continuous generation during development:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

> Always commit the generated `.freezed.dart` and `.g.dart` files.
