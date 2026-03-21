---
name: subagent-task-runner
description: Pick and implement tasks from TASKS.md using specialized subagents instead of team-agents. Reads the backlog, selects the next task (or a user-specified one), and delegates to focused subagents for backend, frontend, or full-stack work.
argument-hint: "[task name or section filter, e.g. 'Memory' or 'Message editing']"
---

# Subagent Task Runner

Your job is to work through `TASKS.md` in an organized, incremental way using **specialized subagents** instead of a collaborative team.

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

Before spawning subagents, read the relevant parts of the codebase to understand what already exists:

1. Search for any existing code related to the task (grep for key terms).
2. Read `CLAUDE.md` for architectural constraints.
3. Identify:
   - **Backend changes**: new endpoints, DB models, migrations, services, schemas
   - **Frontend changes**: new screens, widgets, providers, services, models
   - **Infrastructure changes**: new packages, env vars, Docker services
   - **Tests needed**: unit, integration, e2e

Summarize the scope in a short bullet list before proceeding to implementation.

---

## Step 4 — Dispatch to Subagents

Choose the right subagent(s) based on the task type:

### For backend-focused tasks:
Use the `/backend-agent` subagent:

```
/backend-agent [Task name]

Implementation goal: [1-sentence description]

Scope:
- Files to create/modify: [list specific paths]
- API endpoints: [method + path]
- DB models: [new/modified]
- Services: [business logic]

Acceptance criteria:
- [criterion 1]
- [criterion 2]

Constraints:
- Use `just` commands only (just be-dev, just be-test, just be-lint)
- PostgreSQL via Docker only (just docker-up)
- Follow existing patterns in CLAUDE.md
- Async FastAPI endpoints with proper error handling
- Pydantic schemas for I/O validation
```

### For frontend-focused tasks:
Use the `/frontend-agent` subagent:

```
/frontend-agent [Task name]

Implementation goal: [1-sentence description]

Scope:
- Files to create/modify: [list specific paths]
- Widgets/components: [UI elements]
- Providers: [state management]
- Services: [API calls, business logic]

Acceptance criteria:
- [criterion 1]
- [criterion 2]

Constraints:
- Use `just` commands only (just fe-run, just fe-test, just fe-lint)
- Flutter web/desktop on Linux by default
- ChangeNotifier providers for state
- api_client.dart singleton for HTTP
- Follow existing patterns in CLAUDE.md
```

### For full-stack features (both backend + frontend):
Spawn subagents in parallel using a single message with multiple Agent tool calls:

```
Parallel subagents:
1. backend-agent — implement backend portion
2. frontend-agent — implement frontend portion
3. test-agent — write and run tests

After all complete, verify integration manually if UI is involved.
```

### For infrastructure/DevOps tasks:
Use the `/infra-agent` subagent:

```
/infra-agent [Task name]

Goal: [1-sentence description]

Scope:
- Files to modify: [docker-compose.yml, justfile, workflows, .env]
- Services: [new/modified Docker services]
- Commands: [new just recipes]

Acceptance criteria:
- [criterion 1]
- [criterion 2]
```

### For testing/QA tasks:
Use the `/test-agent` subagent:

```
/test-agent [Task name]

Goal: [1-sentence description]

Scope:
- Test files to create/modify
- Test types: unit, integration, e2e
- Coverage targets

Acceptance criteria:
- All tests pass
- Lint clean
- E2E smoke test green (if applicable)
```

---

## Step 5 — Wait & Verify

After subagents complete:

1. **Review their outputs** — check that all acceptance criteria are addressed.
2. **Run verification commands**:
   ```bash
   just be-lint && just be-test    # if backend was changed
   just fe-lint && just fe-test    # if frontend was changed
   ```
3. **If UI is involved**, do a quick smoke test:
   ```bash
   just be-dev   # in one terminal
   just fe-run   # in another
   ```
4. **If tests fail**, spawn the test-agent again with the specific failures to fix.

---

## Step 6 — Mark Done

Once verified, update `TASKS.md`:
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

Subagents used:
- [agent name]: [what it did]

---
Next suggested task: [Task name from Step 2 logic]
Run `/subagent-task-runner` to continue, or `/subagent-task-runner <task name>` to pick a specific one.
```

---

## Conventions to Always Follow

| Rule | Detail |
|------|--------|
| `just` commands only | Never run `flutter`, `uvicorn`, `uv`, or `docker compose` directly |
| PostgreSQL via Docker | `just docker-up` — never host Postgres |
| Migrations | Add new SQLAlchemy models; `init_db()` handles table creation on startup |
| Auth | All new endpoints use `get_current_user` dependency |
| Admin endpoints | Check `user.is_admin` — requires `is_admin` column migration first |
| No over-engineering | Implement exactly what the task says; don't add unrequested extras |
| One task at a time | Complete and verify before moving to the next |
| Subagent-first | Delegate implementation to subagents; your job is coordination |
