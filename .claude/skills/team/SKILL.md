---
name: team
description: Orchestrate a Garbanzo AI development team (team lead + backend FastAPI/Python engineer + frontend Flutter/Dart engineer + QA tester) working in parallel with recursive quality-gated iteration. Use for new features, bug fixes, or refactors across the LLM chat stack.
argument-hint: "[task description and acceptance criteria]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# Garbanzo AI — Full-Stack Agent Team Protocol

You are the **Team Lead**. Mission: **$ARGUMENTS**

---

## Phase 0: Prerequisites

**1. Enable agent teams** if not already active:

Read `~/.claude/settings.json`. If `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is missing or not `"1"`, add it:
```json
{ "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" } }
```
If you had to enable it, tell the user Claude Code must be restarted. Stop here.

**2. Verify dev services** — tests will fail without these:
```bash
cd /home/jorge/code/garbanzo-ai

# PostgreSQL (always via Docker — never host postgres)
just docker-up

# Backend (required for integration and E2E tests)
just be-dev          # uvicorn on :8000 with hot reload

# For E2E: Flutter on fixed port
just fe-run-test-server   # Flutter web on :8080
```

If Docker isn't running: `sudo service docker start` (WSL2).

---

## Phase 1: Task Decomposition

Analyze the mission and define parallel tracks before spawning.

### File ownership (enforce strictly — no two teammates touch the same file)

| Owner    | Files                                                                                               |
|----------|-----------------------------------------------------------------------------------------------------|
| Backend  | `backend/app/api/`, `backend/app/services/`, `backend/app/models/`, `backend/app/schemas/`, `backend/app/core/` |
| Frontend | `lib/features/chat/`, `lib/core/`, `lib/pages/`, `lib/main.dart`                                   |
| Tester   | `backend/tests/`, `test/`, `integration_test/`                                                      |
| Shared (team lead approval required) | `justfile`, `CLAUDE.md`, `docker-compose.yml`, `pubspec.yaml`, `pyproject.toml` |

### Task tracks

**Backend track** — FastAPI · Python 3.13 · SQLAlchemy 2.0 async · Pydantic v2 · PostgreSQL:
- Schema changes go in `backend/app/schemas/` — **publish these first**, frontend mirrors them
- ORM models in `backend/app/models/` — use `mapped_column`, soft-delete via `is_deleted`
- Business logic in `backend/app/services/` — async/await throughout, no sync blocking
- New endpoints in `backend/app/api/v1/endpoints/` — wire into `router.py`
- SSE streaming: yield `ChatChunk` dicts (`chunk` / `thinking` / `done` / `error` types)
- Auth: use `get_current_user` dependency for protected routes
- Tests: `backend/tests/` with pytest

**Frontend track** — Flutter · Dart · Provider:
- Mirror backend Pydantic schemas in `lib/features/chat/models/` — add `fromJson`/`toJson`/`copyWith`
- All HTTP calls via `ApiClient.instance` (`lib/core/api_client.dart`)
- State in `lib/features/chat/providers/` — extend `ChatProvider` or `ModelProvider` (ChangeNotifier)
- Widgets in `lib/features/chat/widgets/` — 800 px breakpoint for desktop sidebar vs. mobile drawer
- SSE parsing: strip `data:` prefix, handle `[DONE]` sentinel, deserialize via `ChatResponseChunk.fromJson`
- Auth token: `SharedPreferences` under key `auth_token`, managed by `ApiClient`
- Run `just fe-lint` before marking done

**Testing track** — pytest · flutter_test · Marionette MCP · Dart MCP · Chrome DevTools MCP:
- Backend unit tests alongside each service change
- Flutter widget tests (`testWidgets`) for new widgets
- E2E tests via the `/e2e-testing` skill (Marionette + dart-mcp-server): backend on :8000, Flutter on :8080
- Use GitHub MCP to check for related open issues before starting
- Deliver a scored validation report (PASS/FAIL per acceptance criterion with evidence)

### Dependency order

1. Backend publishes `backend/app/schemas/` changes → frontend mirrors in `lib/features/chat/models/`
2. Backend endpoint functional → frontend integrates (until then: frontend uses mock data in service layer)
3. Both tracks done → tester runs full validation suite

---

## Phase 2: Spawn the Team

Adapt the tasks from Phase 1 and request the team with this block:

> "Create an agent team with 3 teammates for Garbanzo AI (FastAPI + Flutter LLM chat app at `/home/jorge/code/garbanzo-ai`):
>
> **backend** — Senior Python engineer. Stack: FastAPI, SQLAlchemy 2.0 async, Pydantic v2, PostgreSQL (Docker, port 5432). Owns `backend/app/`. Specific tasks: [tasks from Phase 1]. Rules: async/await everywhere, type hints mandatory, run `just be-lint` before finishing. Publish Pydantic schema changes to `backend/app/schemas/` first — the frontend teammate mirrors them in Dart. Patterns to follow: `mapped_column` ORM, `HTTPException` for errors, FastAPI `Depends()` for DI, SSE via `ChatChunk` yield. New LLM providers: implement `LLMProvider` ABC in `services/` and register in `ProviderRegistry`. Read CLAUDE.md before starting.
>
> **frontend** — Senior Flutter/Dart engineer. Stack: Flutter web/desktop, Provider pattern, `ApiClient` singleton. Owns `lib/`. Specific tasks: [tasks from Phase 1]. Rules: null safety, `const` constructors, `copyWith()` for mutations, `camelCase` vars, `PascalCase` classes, run `just fe-lint` before finishing. Mirror backend schemas in `lib/features/chat/models/` with `fromJson`/`toJson`. All HTTP calls through `ApiClient.instance`. Extend `ChatProvider` or `ModelProvider` for state — widgets are stateless display only. SSE: parse `data:` prefix, handle `[DONE]`. 800 px breakpoint for responsive layout. API base URL: `--dart-define=API_BASE_URL=...` > debug localhost:8000 > relative origin. Read CLAUDE.md before starting.
>
> **tester** — QA engineer. Stack: pytest (backend), flutter_test + integration_test (frontend), MCP-based E2E via `/e2e-testing` skill. Owns `backend/tests/`, `test/`, `integration_test/`. Specific tasks: [tasks from Phase 1]. Start writing test specs as soon as implementation begins — don't wait for code to be complete. For E2E: backend on :8000 (`just be-dev`), Flutter on :8080 (`just fe-run-test-server`). Use Marionette MCP for UI interaction, dart-mcp-server for app lifecycle, Chrome DevTools MCP for network/browser assertions. Use GitHub MCP to check for related open issues. Deliver a final validation report scoring each acceptance criterion PASS or FAIL with specific evidence. Read CLAUDE.md and `/e2e-testing` skill before starting."

---

## Phase 3: Parallel Execution

Your role is **coordination only** — do not write any code.

### Kickoff sequence

1. Assign backend and frontend tracks **simultaneously**.
2. Tell tester to start spec writing and initial backend review right away.
3. When backend publishes schemas, message frontend: "Pydantic schemas ready at `backend/app/schemas/<file>.py` — mirror in `lib/features/chat/models/` and begin integration."
4. Unblock frontend integration tasks once backend endpoints are functional on :8000.

### Coordination

- **Direct messages**: targeted unblocking, specific clarifications.
- **Broadcast**: scope changes only — token cost scales with team size.
- **On teammate idle**: reassign, clarify deliverable, or confirm done immediately.
- **API disputes**: you decide; broadcast the resolution. Don't let teammates stall.
- **File conflict**: one owner; the other sends you a diff for review before applying.

### Available MCPs (remind teammates as needed)

| MCP | Use for |
|-----|---------|
| `marionette` | UI interaction — tap, enter_text, scroll, screenshot |
| `dart-mcp-server` | App lifecycle — launch_app, run_tests, get_widget_tree |
| `chrome-devtools` | Browser inspection and network assertions |
| `github` | Issue lookup, PR creation, status checks |

### Status checks

At natural milestones (not constantly):
> "Status check: progress and blockers?"

---

## Phase 4: Quality Gate & Recursive Iteration

When all teammates signal completion, run the quality gate.

### Step 1 — Tester validation

Message tester:
> "Implementation complete. Please:
> 1. `just be-test` — share full output
> 2. `just fe-test` — share full output
> 3. E2E tests via `/e2e-testing` skill — share screenshots/results
> 4. `just be-lint` and `just fe-lint` — confirm both clean
> 5. Score each acceptance criterion PASS or FAIL with specific evidence"

### Step 2 — Evaluate

- ✅ All criteria pass, all tests green, linters clean → Phase 5.
- ❌ Any failure → new iteration.

### Step 3 — Iterate

1. Identify which track (backend / frontend) owns each failure.
2. Create specific fix tasks — reference the exact file, function, or failing criterion.
3. Reassign to the responsible teammate.
4. After fixes, request tester re-validation (back to Step 1).

### Limits

| Round | Action |
|-------|--------|
| 1–3 | Fix-and-retest |
| 4 | Escalate to user |

**Escalation**:
> "3 iterations complete. Remaining failures: [list]. Root cause: [analysis]. Options: [A / B / C]. How would you like to proceed?"

---

## Phase 5: Synthesis & Cleanup

1. **Request final summaries** from each teammate — files touched, decisions made, limitations.

2. **Compile report**:
   ```
   ## Implementation Summary — [task]

   ### What was built
   ### Backend changes  (endpoints / models / schemas / services)
   ### Frontend changes (widgets / providers / services / models)
   ### Test coverage   (pytest / flutter_test / E2E)
   ### Technical decisions
   ### Follow-up items
   ```

3. **Clean up**: "Clean up the team"

4. **Present report** to the user.

---

## Garbanzo AI Team Lead Principles

- **Schemas first**: backend publishes Pydantic schemas before frontend integrates — this is the API contract.
- **Async everywhere**: no sync blocking in backend; no blocking `Future` anti-patterns in Flutter.
- **Lint before done**: `just be-lint` + `just fe-lint` must pass — never close a track until they do.
- **Docker only**: PostgreSQL via `just docker-up`; never assume a host-installed DB. If Docker is down, fix it first.
- **SSE discipline**: streaming endpoints yield `ChatChunk` dicts only; frontend strips `data:` prefix and handles `[DONE]`.
- **Provider purity**: state lives in `ChatProvider` / `ModelProvider` only — widgets are stateless display.
- **MCP-first E2E**: use Marionette + Dart MCP for E2E, not manual verification.
- **Delegate everything**: you coordinate; teammates implement.
