# CLAUDE.md

Guidance for AI agents working in this repository. This file is deliberately
lean — it holds only what every session needs, plus a map to the rest. Detailed
reference lives in scoped context files (auto-loaded when you work in that
directory) and `docs/` (read on demand). **Consult the map below before working
in an area; don't guess.**

> **New machine?** See [`setup.md`](./setup.md) for prerequisites (Flutter, uv,
> Docker, GStreamer, lld, Ollama, Android SDK, etc.).

## What this is

**Garbanzo AI** — a self-hosted AI chat app. Async **FastAPI** backend
(SQLAlchemy/AsyncPG + PostgreSQL/pgvector, JWT auth, SSE streaming, Ollama LLMs
via a pluggable provider, in-process Kokoro TTS + Faster Whisper STT) and a
**Flutter** frontend (web/desktop/Android, Provider + Freezed). Features: chat
with tools (MCP + native), user memories, knowledge base (RAG), multi-agent
rooms (WebSocket), scheduled actions, FCM push notifications, micro-apps
workspace, and hands-free Talk Mode.

## Non-negotiable rules

- **Always use `just` commands.** Never run `flutter`, `uvicorn`, `uv`,
  `pytest`, or `docker compose` directly — the justfile is the single source of
  truth. Run `just` with no arguments to list all recipes.
- **PostgreSQL runs only via Docker** (`just docker-up` / `just docker-up-db`).
  Never start or connect to a host-installed instance. If Docker isn't running:
  `sudo service docker start` (WSL2).
- **Run `just check`** (auto-format + lint both stacks) before committing.

## Essential commands

```bash
just check           # format + lint both stacks — run before committing
just dev             # Docker + backend + frontend on Linux desktop
                     # (variants: dev-web → Chrome, dev-apk → Android)
just be-dev          # backend only, hot reload (port 8000)
just fe-run          # frontend only, Linux desktop
just test            # all unit tests (individually: be-test / fe-test)
just docker-up       # Postgres + Whisper (docker-up-db: Postgres only)
just deploy          # ship local main → web + backend image + prod stack + APK
```

Single tests: `cd backend; uv run pytest tests/path/test_file.py::test_name`
and `flutter test test/path/widget_test.dart`.

## Documentation map

| When you need | Read |
|---------------|------|
| Backend conventions, where code goes, migrations pattern | [`backend/CLAUDE.md`](backend/CLAUDE.md) *(auto-loads when working in `backend/`)* |
| Frontend conventions, where code goes, Freezed codegen | [`lib/CLAUDE.md`](lib/CLAUDE.md) *(auto-loads when working in `lib/`)* |
| Deployment ops, prod stack, secrets layout | [`deploy/CLAUDE.md`](deploy/CLAUDE.md); procedures in [`deploy/README.md`](deploy/README.md) |
| Full architecture: layouts, chat/SSE flow, rooms WebSocket, providers, Docker services | [`docs/architecture.md`](docs/architecture.md) |
| API endpoint reference | [`docs/api.md`](docs/api.md) |
| DB models, column semantics, migration mechanics | [`docs/database.md`](docs/database.md) |
| Backend environment variables | [`docs/environment.md`](docs/environment.md) |
| E2E testing (manual, Dart MCP + Marionette) | `/e2e-testing` skill |
| New machine setup | [`setup.md`](setup.md) |

Every `CLAUDE.md` has an `AGENTS.md → CLAUDE.md` symlink beside it so Claude
Code, opencode, Cursor, and other tools all read the same file.

## Skills

Skills (`.claude/skills/<name>/SKILL.md`) capture workflows that took research
or trial-and-error to figure out.

| Skill | Trigger |
|-------|---------|
| `vibe-coding` | Writing code, fixing bugs, refactoring — the default workflow; includes doc maintenance and skill creation |
| `e2e-testing` | E2E testing the Flutter app with Dart MCP + Marionette |
| `project-overview` | Quick orientation: structure, conventions, doc map |
| `task-runner` | Picking and implementing tasks from TASKS.md using the team workflow |
| `subagent-task-runner` | Picking and implementing tasks from TASKS.md using subagents |
| `team` | Orchestrating a full-stack development team (lead, backend, frontend, tester) |
| `user-reports` | Reading user bug reports / feature requests from the prod DB and acting on them |

## Maintaining agent docs (part of every task)

These docs only work if they stay current. When your change touches any of the
following, update the owning doc **in the same commit**:

| Change | Update |
|--------|--------|
| Endpoint added/changed/removed | `docs/api.md` |
| Model or column with non-obvious semantics | `docs/database.md` (+ SQL migration) |
| New env var | `docs/environment.md` (+ `deploy/.env.example` if prod) |
| Service, provider, flow, or layout change | `docs/architecture.md` |
| User-facing feature added/changed/removed | its guide in `backend/app/docs/help/` (the in-app `app_help` tool answers from these) |
| New package-level convention or gotcha | that package's `CLAUDE.md` |
| Non-obvious workflow that took trial and error | new skill in `.claude/skills/` |
| New essential dev command | this file's commands block (recipes are otherwise self-documenting via `just`) |

Additionally:

- **If you hit a gap** — a wrong assumption these docs led you to, missing
  context you had to dig for, or a mistake you'd repeat — document the
  correction in the closest file above so the next agent doesn't repeat it.
- **Keep this root file lean** (~120 lines): it loads into every session.
  Details belong in scoped `CLAUDE.md` files or `docs/`, which load on demand.
- **Delete stale content on sight** — wrong docs are worse than missing docs.
