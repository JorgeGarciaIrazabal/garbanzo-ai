# AGENTS.md

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
                     # focused: just be-test tests/path/test_file.py::test_name
                     #          just fe-test test/path/widget_test.dart
just docker-up       # Postgres + Whisper (docker-up-db: Postgres only)
just deploy          # ship local main → web + backend image + prod stack + APK
just ai-setup --install --migrate # install/check the Codex development tools
just ai              # guided development with startup triage and capacity evidence
just ai-doctor       # validate models, tools, skills, indexes, and adapters
```

Use focused tests while iterating; run `just test` as the full pre-deploy gate.

## Documentation map

| When you need | Read |
|---------------|------|
| Backend conventions, where code goes, migrations pattern | [`backend/AGENTS.md`](backend/AGENTS.md) *(auto-loads when working in `backend/`)* |
| Frontend conventions, where code goes, Freezed codegen | [`lib/AGENTS.md`](lib/AGENTS.md) *(auto-loads when working in `lib/`)* |
| Deployment ops, prod stack, secrets layout | [`deploy/AGENTS.md`](deploy/AGENTS.md); procedures in [`deploy/README.md`](deploy/README.md) |
| Full architecture: layouts, chat/SSE flow, rooms WebSocket, providers, Docker services | [`docs/architecture.md`](docs/architecture.md) |
| API endpoint reference | [`docs/api.md`](docs/api.md) |
| DB models, column semantics, migration mechanics | [`docs/database.md`](docs/database.md) |
| Backend environment variables | [`docs/environment.md`](docs/environment.md) |
| E2E testing (manual, Dart MCP + Marionette) | `/e2e-testing` skill |
| Test coverage gaps, priorities, conventions | [`docs/coverage-strategy.md`](docs/coverage-strategy.md) |
| New machine setup | [`setup.md`](setup.md) |

Root `AGENTS.md` and `.agents/skills/` are authoritative. `CLAUDE.md` and
`.claude/skills` are compatibility links. Scoped package docs use `AGENTS.md`;
their `CLAUDE.md` names are compatibility links.

## Codex development

- Start with `just ai` (guided conversation) or `just ai-startup` in an existing session.
- Use Beads through `just ai-task`; `TASKS.md` is generated. Keep requirements,
  dependencies, acceptance and testing feedback associated with task IDs.
- Astra handles architecture/design; Sol complex code/review; Terra routine
  work; Luna narrow exploration. Discover account access with `just ai-models`;
  never silently downgrade architecture. Pin each assignment's resolved model.
- At most three isolated workers plus the coordinator. Only the coordinator
  integrates and commits verified changes directly on `main`. No dev branches/PRs.
- Preserve unrelated edits. Record independent review for substantive changes;
  run `just check` before committing and `just test` before pushing/deploying.
- Distinguish automatically verified, ready for user testing, and accepted.
  Link feedback to the exact stable `just ai-preview` snapshot.
- Collect production evidence at session startup, on request, and overnight;
  failures are collection failures, never “no issues.” No continuous daytime monitor.
- Deploy/restart/rollback/data changes only on user request. Report status sync
  follows the authorized task lifecycle; close only after fix deployment and
  report-specific verification. Keep raw evidence private in `.ai/local/`.
- Answer investigation/review questions directly; do not infer implementation.

Setup, commands, recovery and acceptance: [`docs/ai-development.md`](docs/ai-development.md).
Focused skills live in `.agents/skills/`: guided-development, coordination,
production-triage, code-navigation, knowledge-retrieval, testing, releases.
`vibe-coding`, `task-runner`, `subagent-task-runner`, `team`, and `user-reports`
remain compatibility entry points. E2E runtime guidance: `e2e-testing`.

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
| New package-level convention or gotcha | that package's `AGENTS.md` |
| Non-obvious workflow that took trial and error | new skill in `.agents/skills/` |
| New essential dev command | this file's commands block (recipes are otherwise self-documenting via `just`) |

Additionally:

- **If you hit a gap** — a wrong assumption these docs led you to, missing
  context you had to dig for, or a mistake you'd repeat — document the
  correction in the closest file above so the next agent doesn't repeat it.
- **Keep this root file lean** (~120 lines): it loads into every session.
  Details belong in scoped `AGENTS.md` files or `docs/`, which load on demand.
- **Delete stale content on sight** — wrong docs are worse than missing docs.
