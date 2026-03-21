# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Backend (FastAPI)
```bash
just be-dev          # Dev server with hot reload (port 8000)
just be-test         # Run pytest
just be-lint         # ruff check
just be-format       # ruff format
cd backend; uv run pytest tests/path/test_file.py::test_name  # Single test
```

### Frontend (Flutter)
```bash
just fe-run          # Run on Chrome (manual dev)
just fe-test         # Unit/widget tests
just fe-lint         # flutter analyze
flutter test test/path/widget_test.dart  # Single test file
just fe-build        # Build web → backend/web/ (for prod)
```

### Infrastructure
```bash
just docker-up       # Start PostgreSQL (via Docker — always use this, never run postgres from the host)
just install         # Install all deps (backend + frontend)
```

> **IMPORTANT:** PostgreSQL must always be started via Docker (`just docker-up`). Never attempt to start or connect to a host-installed PostgreSQL instance. If `just docker-up` fails because Docker isn't running, start Docker first (`sudo service docker start` in WSL2).

## Architecture

### Stack
- **Backend:** FastAPI (async) + SQLAlchemy/AsyncPG + PostgreSQL + JWT auth
- **Frontend:** Flutter (web/desktop) + Provider state management
- **LLM:** Ollama (default) via a pluggable provider pattern
- **Streaming:** Server-Sent Events (SSE) from backend to frontend

### Backend Layout (`backend/app/`)

```
core/       config.py (pydantic-settings), security.py (JWT/bcrypt)
api/v1/     endpoints/ auth.py, chat.py, health.py  →  router.py
models/     SQLAlchemy ORM: User (email PK), Conversation, Message
schemas/    Pydantic I/O: auth.py, chat.py
services/   chat_service.py, conversation_service.py, user_service.py
            llm_provider.py (abstract base + ProviderRegistry)
            ollama_provider.py (concrete impl)
db/         session.py (AsyncSession, init_db)
```

- `main.py` runs `init_db()` on startup, serves Flutter web from `backend/web/`, and auto-creates a test user if `TEST_USER_EMAIL`/`TEST_USER_PASSWORD` are in `.env`.
- All endpoints are under `/api/v1/`. Auth uses `get_current_user` dependency that validates `Authorization: Bearer <token>`.
- Adding a new LLM provider: implement `LLMProvider` ABC in `services/` and register it in `ProviderRegistry`.

### Frontend Layout (`lib/`)

```
main.dart           AuthGate: checks stored token → routes to Login or ChatPage
core/
  api_client.dart   Singleton HTTP client; resolves base URL; stores token in SharedPreferences
  auth_service.dart Singleton; login/register/logout; returns AuthResult
features/chat/
  models/           ChatMessage, Conversation, ChatAttachment, ModelInfo, ChatResponseChunk
  providers/        ChatProvider (ChangeNotifier), ModelProvider (ChangeNotifier)
  services/         chat_service.dart — CRUD + SSE streaming
  widgets/          ChatPage, ChatInputWidget, ChatMessageWidget, ConversationListWidget, …
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

### SSE Streaming Protocol

Each server event: `data: {"type":"chunk","content":"...","metadata":null}\n\n`
Terminal event: `data: {"type":"done","content":null,"metadata":{...}}\n\n`
Client parses lines, strips `data: ` prefix, skips `[DONE]` sentinel.

### Database Notes

- `Conversation.model` defaults to `"llama3.2"` — must match a model ID returned by `GET /api/v1/chat/models`.
- `Message.meta` is JSONB and stores token counts, generation timing, and thinking block content.
- Conversations use soft delete (`is_deleted=True`), not hard delete.

### Auth Token Storage

Flutter stores the JWT in `SharedPreferences` under key `auth_token`. `ApiClient` reads it for every authenticated request.

### API Base URL Resolution (Flutter)

1. Compile-time `--dart-define=API_BASE_URL=...` (takes priority)
2. Debug mode → `http://localhost:8000`
3. Web release → relative to current origin

### Environment Variables (backend `.env`)

```
SECRET_KEY=           # Required — JWT signing key
DATABASE_URL=postgresql+asyncpg://garbanzo:garbanzo_dev@localhost:5432/garbanzo_ai
LLM_PROVIDER=ollama
OLLAMA_BASE_URL=http://localhost:11434   # host.docker.internal when in Docker
TEST_USER_EMAIL=      # Optional — auto-creates test user on startup
TEST_USER_PASSWORD=
ACCESS_TOKEN_EXPIRE_MINUTES=30
```

## E2E Testing

See `/e2e-testing` skill (`/e2e-testing` slash command). Uses Dart MCP to launch the app and Marionette MCP to drive UI interactions via the Flutter VM service URI.

Flutter web integration tests (`-d chrome`) are not supported by Flutter. Use `-d linux` (desktop) for integration test runs.
