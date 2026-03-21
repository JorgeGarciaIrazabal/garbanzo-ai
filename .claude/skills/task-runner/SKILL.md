---
name: task-runner
description: Pick and implement tasks from TASKS.md in an organized way. Reads the backlog, selects the next task (or a user-specified one), plans the implementation, delegates to the team skill, and marks the task done on completion.
argument-hint: "[task name or section filter, e.g. 'Memory' or 'Message editing']"
---

# Task Runner

Your job is to work through `TASKS.md` in an organized, incremental way.

Arguments (if any): **$ARGUMENTS**

---

## Step 1 — Read the Backlog

Read `TASKS.md` in full. Build a mental picture of:
- All sections and their tasks
- Which tasks are checked `[x]` (done) vs unchecked `[ ]` (pending)
- Dependencies between tasks (e.g. DB model must come before UI)

---

## Step 2 — Select the Task

### If `$ARGUMENTS` is provided:
- Find the task in `TASKS.md` whose name or section best matches the argument.
- If multiple matches exist, list them and ask the user to confirm which one.

### If no argument is provided:
Apply this priority order to pick **one** unchecked task:

1. **Foundation-first**: Prefer infrastructure tasks that unblock others (DB models before UI, backend endpoints before frontend widgets, auth before features that need it).
2. **Section order**: Work through sections roughly top-to-bottom as they appear in `TASKS.md`.
3. **Skip blockers**: If a task explicitly depends on something not yet done (e.g. "pgvector integration" before "Embedding generation"), skip it and pick the next ready one.

Present the selected task to the user and ask for confirmation before proceeding:

> **Selected task:** `[Section] Task name — description`
>
> Proceed? (yes / pick a different one / list all pending)

Wait for confirmation. If the user says "list all pending", print every unchecked `[ ]` item grouped by section, then ask them to choose.

---

## Step 3 — Scope Analysis

Before planning, read the relevant parts of the codebase to understand what already exists:

1. Search for any existing code related to the task (grep for key terms).
2. Read `CLAUDE.md` for architectural constraints.
3. Identify:
   - **Backend changes**: new endpoints, DB models, migrations, services, schemas
   - **Frontend changes**: new screens, widgets, providers, services, models
   - **Infrastructure changes**: new packages, env vars, Docker services
   - **Tests needed**: unit, integration, e2e

Summarize the scope in a short bullet list before proceeding to implementation.

---

## Step 4 — Implementation

### For tasks that touch both backend and frontend (most feature tasks):
Invoke the `/team` skill with a detailed brief:

```
/team [Task name]: [1-sentence goal]

Acceptance criteria:
- [criterion 1]
- [criterion 2]
- [criterion 3]

Backend scope:
- [specific files/endpoints to create or modify]

Frontend scope:
- [specific widgets/providers/services to create or modify]

Constraints from CLAUDE.md:
- Always use `just` commands, never run flutter/uvicorn/uv directly
- PostgreSQL via Docker only (`just docker-up`)
- Follow existing patterns: FastAPI async endpoints, SQLAlchemy ORM, Provider state management
- New LLM providers implement the LLMProvider ABC and register in ProviderRegistry
```

### For backend-only tasks (DB models, endpoints, services):
Implement directly, following the backend layout in `CLAUDE.md`:
- DB models in `backend/app/models/`
- Pydantic schemas in `backend/app/schemas/`
- Business logic in `backend/app/services/`
- Endpoints in `backend/app/api/v1/endpoints/`
- Register new routers in `backend/app/api/v1/router.py`
- Run `just be-lint` and `just be-test` when done

### For frontend-only tasks (UI, widgets, rendering):
Implement directly, following the frontend layout in `CLAUDE.md`:
- New features under `lib/features/<feature>/`
- New pages under `lib/pages/`
- State via ChangeNotifier providers
- HTTP calls via `ApiClient` singleton
- Run `just fe-lint` and `just fe-test` when done

### For infrastructure tasks (Redis, Docker, CI):
Make targeted changes to `docker-compose.yml`, `justfile`, config files, or `.github/workflows/`. No need for team unless the scope is large.

---

## Step 5 — Verify

After implementation is complete:

1. Run the relevant linter and tests:
   ```bash
   just be-lint && just be-test    # if backend was changed
   just fe-lint && just fe-test    # if frontend was changed
   ```
2. If the task has visible UI, run the app and do a quick smoke test:
   ```bash
   just be-dev   # in one terminal
   just fe-run   # in another
   ```
3. Fix any lint errors or test failures before proceeding.

---

## Step 6 — Mark Done

Once the task is verified, update `TASKS.md`:
- Change `- [ ]` to `- [x]` for the completed task.
- Do **not** modify any other tasks or formatting.

Example edit:
```
- [x] **Memory store DB model** — `UserMemory` table: ...
```

---

## Step 7 — Summary & Next

Report to the user:

```
✅ Completed: [Task name]

What was done:
- [bullet 1]
- [bullet 2]

Files changed:
- [file 1]
- [file 2]

---
Next suggested task: [Task name from Step 2 logic]
Run `/task-runner` to continue, or `/task-runner <task name>` to pick a specific one.
```

---

## Conventions to Always Follow

| Rule | Detail |
|------|--------|
| `just` commands only | Never run `flutter`, `uvicorn`, `uv`, `pytest`, or `docker compose` directly |
| PostgreSQL via Docker | `just docker-up` — never host Postgres |
| Migrations | Add new SQLAlchemy models; `init_db()` handles table creation on startup (no Alembic yet) |
| Auth | All new endpoints use `get_current_user` dependency |
| Admin endpoints | Check `user.is_admin` — requires `is_admin` column migration first |
| No over-engineering | Implement exactly what the task says; don't add unrequested extras |
| One task at a time | Complete and verify before moving to the next |
