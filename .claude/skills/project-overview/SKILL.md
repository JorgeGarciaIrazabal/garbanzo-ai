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
├── lib/                    # Flutter app
│   ├── core/
│   │   ├── api_client.dart # HTTP client, token storage
│   │   └── auth_service.dart
│   └── pages/
│       ├── login_page.dart
│       ├── register_page.dart
│       └── home_page.dart
├── integration_test/       # Flutter E2E tests (desktop only)
├── backend/                # FastAPI app
│   └── app/
│       ├── main.py
│       └── core/security.py
├── justfile                # All dev commands
└── docker-compose.yml      # PostgreSQL
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
