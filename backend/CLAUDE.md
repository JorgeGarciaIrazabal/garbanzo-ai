# Backend — Agent Context

Async FastAPI backend (SQLAlchemy/AsyncPG + PostgreSQL/pgvector, JWT auth).
This file is the package-local quick reference. Detailed reference is read on
demand: `../docs/architecture.md` (layout, flows, startup), `../docs/api.md`
(endpoint table), `../docs/database.md` (model notes), `../docs/environment.md`
(env vars).

## Commands (always via `just`, never `uv`/`pytest`/`uvicorn` directly)

- `just be-dev` — dev server, hot reload (port 8000)
- `just be-test` — pytest suite
- `just be-lint` / `just be-format` — ruff check / format
- Single test: `cd backend; uv run pytest tests/path/test_file.py::test_name`

## Where code goes

- `app/api/v1/endpoints/*.py` — one router per resource, wired in `router.py`.
- `app/models/` — SQLAlchemy ORM. `app/schemas/` — Pydantic I/O.
- `app/services/` — business logic; endpoints stay thin.
- `app/core/` — `config.py` (pydantic-settings), `security.py` (JWT/bcrypt).

## Conventions

- Auth: depend on `get_current_user` (validates `Authorization: Bearer <token>`).
- Streaming: SSE chunks (`chunk`/`thinking`/`tool_call`/`tool_result`/`tool_execution`/`action_proposal`/`done`/`error`).
- Async everywhere: `AsyncSession`, `await` DB calls.
- New LLM provider: implement the `LLMProvider` ABC, register in `ProviderRegistry`.

## Migrations (no Alembic)

Add idempotent SQL to `migrations/NNN_description.sql`, always `ADD COLUMN IF NOT
EXISTS`. Applied once each at startup (`db/migrations.py`), tracked in
`schema_migrations`. A failing migration crashes startup by design.

## Gotchas

- PostgreSQL runs only via Docker (`just docker-up-db`) — never a host instance.
- Startup ordering lives in `main.py` (`init_db` → test user → admin promotion →
  template seed → TTS/STT background load → scheduler → firebase).
