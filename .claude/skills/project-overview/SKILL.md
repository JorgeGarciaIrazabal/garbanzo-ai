---
name: project-overview
description: Quick orientation for Garbanzo AI — what the project is, where things live, and which doc to read for detail. Use when starting work in an unfamiliar area or when unsure where code or documentation belongs.
---

# Garbanzo AI — Project Overview

Self-hosted AI chat app: async **FastAPI** backend (SQLAlchemy/AsyncPG +
PostgreSQL/pgvector, JWT auth, SSE streaming, Ollama LLMs, in-process Kokoro
TTS + Faster Whisper STT) and a **Flutter** frontend (web/desktop/Android,
Provider + Freezed). Features: chat with tools (MCP + native), user memories,
knowledge base (RAG), multi-agent rooms (WebSocket), scheduled actions, FCM
push notifications, micro-apps workspace, Talk Mode.

## Ground rules

- All dev tasks go through `just` — never `flutter`, `uv`, `pytest`, `uvicorn`,
  or `docker compose` directly. `just` with no args lists every recipe.
- PostgreSQL runs only via Docker (`just docker-up-db`).
- `just check` before committing.

## Where things live

- `backend/app/` — endpoints (`api/v1/endpoints/`), ORM (`models/`), Pydantic
  I/O (`schemas/`), business logic (`services/`), SQL migrations
  (`backend/migrations/NNN_*.sql`, idempotent, auto-applied at startup).
- `lib/features/<feature>/` — `models/`, `providers/`, `services/`, `widgets/`,
  `pages/` per feature; cross-feature singletons in `lib/core/`.
- `deploy/` — prod Docker Compose stack + ops guide.

## Where to read more

| Topic | File |
|-------|------|
| Backend conventions & gotchas | `backend/CLAUDE.md` |
| Frontend conventions & gotchas | `lib/CLAUDE.md` |
| Deployment ops | `deploy/CLAUDE.md`, `deploy/README.md` |
| Full architecture, layouts, chat/SSE flow, rooms | `docs/architecture.md` |
| API endpoint table | `docs/api.md` |
| DB models & migrations | `docs/database.md` |
| Env vars | `docs/environment.md` |

Keep these docs current as you work — the policy is in root `CLAUDE.md`
("Maintaining agent docs").
