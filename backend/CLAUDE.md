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
- Streaming: SSE chunks (`chunk`/`thinking`/`tool_call`/`tool_result`/`tool_execution`/`action_proposal`/`client_tool_request`/`done`/`error`).
- Async everywhere: `AsyncSession`, `await` DB calls.
- New LLM provider: implement the `LLMProvider` ABC, register in `ProviderRegistry`.

## Migrations (no Alembic)

Add idempotent SQL to `migrations/NNN_description.sql`, always `ADD COLUMN IF NOT
EXISTS`. Applied once each at startup (`db/migrations.py`), tracked in
`schema_migrations`. A failing migration crashes startup by design.

## Gotchas

- Work that must outlive the HTTP request (delegated workflows) is started with
  `asyncio.create_task` from the endpoint and **never awaited there** — awaiting
  re-couples it to the client's connection, which is the exact bug the feature
  exists to avoid. Such a task opens its own session via a *late* `from app.db
  import session as db_session` + `db_session.async_session_maker()` so tests
  pick up conftest's swapped maker (see the note above). Anything it needs to
  report goes to the DB (+ FCM), not the response.
- Spawning opencode? Use `opencode_process.py` (setsid + `PR_SET_PDEATHSIG`,
  port picking, readiness probe) and `opencode_config.py` — shared by micro-apps
  and workflows, so the child-never-outlives-us guarantee holds in one place.

- Micro-apps worktrees must stay in sync with `main` or the panel 404s.
  `MicroappWorkspaceManager.ensure_sync` rebases a *clean* worktree onto
  `origin/main` before starting the dev server (the orchestrator scans
  `apps/*` once at startup and never re-scans, so an app added to `main`
  after a worktree was created never appears — the dev-server's `pickApp()`
  returns null → `404 'not found'` in the panel). The periodic
  `microapps_sync_job` only runs when `MICROAPPS_GIT_URL` is set (prod); dev
  relies on the in-`ensure` rebase. "Clean" uses `git status -uno` so the
  gitignored `opencode.json` (seeded in every workspace) doesn't block it,
  but uncommitted tracked edits do (the user has work in flight —
  `publish`/`revert` resolve it interactively). When the app set changes on
  a rebase the dev server is restarted so the new app is registered.

- PostgreSQL runs only via Docker (`just docker-up-db`) — never a host instance.
- Startup ordering lives in `main.py` (`init_db` → test user → admin promotion →
  template seed → TTS/STT background load → scheduler → firebase).
- Tests run against an in-memory SQLite DB — never the real Postgres. conftest
  swaps `app.db.session.engine` and `async_session_maker` per test, so code
  paths that bypass `get_db` (`get_current_admin_user`, background jobs, etc.)
  also hit SQLite. Modules that did `from app.db.session import
  async_session_maker` at top level keep the old (Postgres) reference — those
  callers must be patched per-test, or call into `app.db.session` lazily (like
  `get_current_admin_user` does) to pick up the swap.
