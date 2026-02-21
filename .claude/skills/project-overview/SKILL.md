---
name: project-overview
description: Project structure and development conventions for Garbanzo AI
---

# Garbanzo AI — Project Overview

## Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (web + desktop) |
| Backend | FastAPI (Python), SQLAlchemy, PostgreSQL |
| Package manager (BE) | `uv` |
| Task runner | `just` (justfile) |
| Dev database | Docker Compose (PostgreSQL) |

## Directory Layout

```
garbanzo_ai/
├── lib/                              # Flutter app
│   ├── main.dart                     # App entry, AuthGate
│   ├── core/
│   │   ├── api_client.dart           # Centralized HTTP client (get/post/patch/delete/send)
│   │   ├── auth_service.dart         # Register, login, logout, token management
│   │   └── widgets/
│   │       └── auth_form_layout.dart # Shared auth form scaffold, error banner, submit button
│   ├── pages/
│   │   ├── login_page.dart
│   │   └── register_page.dart
│   └── features/
│       └── chat/
│           ├── models/
│           │   ├── chat_message.dart      # ChatMessage, ChatResponseChunk
│           │   ├── conversation.dart      # Conversation, ConversationList
│           │   └── model_info.dart        # ModelInfo, ModelList
│           ├── providers/
│           │   ├── chat_provider.dart     # Conversation + message state
│           │   └── model_provider.dart    # LLM model selection state
│           ├── services/
│           │   └── chat_service.dart      # HTTP calls (via ApiClient)
│           └── widgets/
│               ├── chat_page.dart             # Main page (wires providers)
│               ├── chat_input_widget.dart     # Text input + send/stop
│               ├── chat_message_widget.dart   # Single message bubble
│               ├── conversation_list_widget.dart # Sidebar list
│               ├── empty_chat_state.dart      # Empty state + suggestions
│               ├── mobile_drawer.dart         # Bottom-sheet conversation list
│               └── model_selector_widget.dart # Model dropdown
├── integration_test/                 # Flutter E2E tests (desktop only)
├── backend/                          # FastAPI app
│   └── app/
│       ├── main.py
│       ├── core/
│       │   ├── config.py             # Settings (DB, CORS, LLM provider)
│       │   └── security.py           # JWT, password hashing
│       ├── api/v1/endpoints/
│       │   ├── auth.py               # Register, login, /me
│       │   ├── chat.py               # Conversation CRUD, streaming, models
│       │   └── health.py
│       ├── models/                   # SQLAlchemy ORM
│       │   ├── user.py
│       │   ├── conversation.py
│       │   └── message.py
│       ├── schemas/                  # Pydantic request/response
│       │   ├── auth.py
│       │   ├── user.py
│       │   └── chat.py
│       └── services/
│           ├── user_service.py           # User lookup/creation
│           ├── conversation_service.py   # Conversation CRUD
│           ├── chat_service.py           # Messaging + LLM streaming
│           ├── llm_provider.py           # Abstract LLM provider + registry
│           └── ollama_provider.py        # Ollama implementation
├── justfile                          # All dev commands
└── docker-compose.yml                # PostgreSQL
```

## Common Commands

```powershell
just be-dev             # Start FastAPI with hot-reload (port 8000)
just fe-run             # Run Flutter on Chrome (dev, not for MCP testing)
just fe-run-test-server # Run Flutter web-server on port 8080 (for MCP E2E)
just fe-integration-test # flutter test integration_test/ -d windows
just docker-up          # Start PostgreSQL via Docker
just fe-lint            # flutter analyze
just be-lint            # ruff check backend/
```

## Auth Flow

1. Register: `POST /api/v1/auth/register`
2. Login: `POST /api/v1/auth/login` → returns JWT
3. JWT stored in `SharedPreferences` via `ApiClient`
4. Authenticated requests send `Authorization: Bearer <token>`

## Flutter Web Quirks

- In debug mode the app targets `http://localhost:8000` for all API calls (see `lib/core/api_client.dart`).
- Override with `--dart-define=API_BASE_URL=https://...`.
- Flutter renders into a `<flutter-view>` shadow DOM — standard CSS/JS selectors don't reach widgets.
