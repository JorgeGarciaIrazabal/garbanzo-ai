---
name: vibe-coding
description: Vibe-coding workflow for writing clean code, auto-improving the project, maintaining AGENTS.md/CLAUDE.md, and generating skills. Use when writing code, fixing bugs, refactoring, adding tests/observability, or improving developer experience.
---

# Vibe Coding Protocol

## Philosophy

You are a smart agent working on a real codebase. The codebase already has conventions, tooling, and documentation. Your job is to write clean code that fits, verify it properly, and leave the project healthier than you found it.

Trust the existing patterns. Trust the tooling (`just` commands, linters, test runners). Trust CLAUDE.md as the architectural reference. Don't reinvent what's already there. Don't over-document what the code already says.

## Code Quality Goals

- **Small files.** Split by responsibility. If a file does two unrelated things, it should be two files.
- **Small functions.** If a function needs scrolling to read, extract. Each function does one thing.
- **Self-documenting code.** Names communicate intent. Types communicate constraints. Comments are only for things the code can't express — non-obvious "why", never "what".
- **No dead code.** No unused imports, no commented-out blocks, no speculative parameters or config flags.
- **No over-engineering.** Build the thing requested. No abstract factories for one implementation. No config for values that are always the same. No premature extraction — only DRY when something is repeated 3+ times with variation.
- **Follow the stack.** Read the neighboring files. Match their style, imports, naming, error handling. The codebase's conventions are the spec.

## Workflow

### Understand Before Writing

Read the project's reference material. CLAUDE.md has the architecture, directory layout, API endpoints, database models, and conventions. The `justfile` has every available command. Use grep/glob to find existing patterns for what you're about to build — someone likely solved a similar problem already.

Identify which package or module your change belongs to. Backend code goes in `backend/app/` following the model/schema/service/endpoint split. Frontend code goes in `lib/features/<feature>/` following the models/providers/services/widgets split. Migrations go in `backend/migrations/`. Don't scatter related code across unrelated directories.

### Implement

Write the minimal clean code that satisfies the task. Follow the existing conventions in CLAUDE.md — it documents where models, schemas, services, endpoints, widgets, providers, and migrations go. It documents the auth pattern (`get_current_user`), the streaming protocol (SSE chunks), the migration pattern (idempotent SQL, `ADD COLUMN IF NOT EXISTS`), and the LLM provider pattern (implement `LLMProvider` ABC, register in `ProviderRegistry`).

Use the right tools for the job: grep and glob to find where things live, read to understand existing patterns, edit to make targeted changes, bash to run `just` commands for lint/test/build.

### Verify

The project has a quality bar. Use these tools:

- `just check` — format and lint both stacks. Run this first.
- `just be-lint` + `just be-test` — backend lint and tests (508 pytest tests).
- `just fe-lint` + `just fe-test` — frontend analysis and tests (234 Flutter tests).

**Zero warnings is the bar.** Not "mostly clean" — zero. When you see a warning:
- Deprecated API → migrate to the replacement (e.g. `datetime.utcnow()` → `datetime.now(UTC)`).
- Leaked resource in a fixture → dispose properly in teardown (e.g. `await engine.dispose()` before the event loop closes).
- Misapplied test mark → fix the mark, don't suppress it (e.g. remove `pytestmark = pytest.mark.asyncio` from files with sync tests, decorate only the async ones).
- Suppression directive (`filterwarnings`, `// ignore:`, `noqa`) → remove it and fix the root cause.

Never claim "done" without running the relevant lint and test commands and seeing them pass clean.

### Auto-Improve

After completing the immediate task, don't stop. Look for adjacent improvements:

- **Did tests produce warnings during your run?** Fix them now — same session, same context, it's cheapest.
- **Did you add new code without tests?** Add tests following the existing patterns in `backend/tests/` or `test/`.
- **Is CLAUDE.md out of date?** If you added an endpoint, model, service, command, or env var, update the relevant section. CLAUDE.md is the reference agents use — keeping it current is part of the work.
- **Did you figure out a non-obvious workflow?** Capture it as a skill (see below).
- **Did you notice dead code, broken imports, or stale comments?** Clean them up.
- **Is there a fixture or helper that 3+ callers duplicate?** Extract it.

The goal is not to refactor the whole project after every task. It's to fix what's right in front of you, cheaply, while the context is loaded.

## AGENTS.md / CLAUDE.md

`CLAUDE.md` is the project's single source of truth. The root `AGENTS.md` is a symlink to it (`AGENTS.md → CLAUDE.md`). Both names resolve to the same content, so agents that look for either filename find the same reference.

### Keeping CLAUDE.md Current

CLAUDE.md documents: stack, architecture, all `just` commands, backend layout, frontend layout, API endpoint reference, database notes, auth/storage/streaming patterns, environment variables, deployment, and testing strategy.

When you change the project, update the corresponding section:
- New endpoint → API table
- New model/service → directory layout
- New `just` recipe → commands section
- New env var → env var list
- Architecture change → architecture section

Keep it concise. It's a reference for a smart agent, not a tutorial. A few lines in the right table are worth more than paragraphs of prose. Remove things that no longer exist.

### Package-Level AGENTS.md

A package with its own build/test workflow or conventions (e.g. `backend/`, `lib/`, `deploy/`) gets its own agent context. Write a concise, **agent-oriented** `CLAUDE.md` in that directory — purpose, `just` commands, where code goes, conventions, gotchas — and defer to the root `../CLAUDE.md` for full architecture rather than duplicating it. This is context *for agents*, distinct from a `README.md`, which is for humans; don't point one at the other.

Then symlink `AGENTS.md → CLAUDE.md` beside it (matching the root, where `AGENTS.md → CLAUDE.md`). The real content lives in `CLAUDE.md`; the symlink lets Claude Code, Cursor, opencode, and other agent tools all read the same file under whichever name they look for.

## Auto-Creating Skills

A skill captures hard-won knowledge: workflows that took research, experimentation, or debugging to figure out, and will be needed again.

### When to Create a Skill

- You searched docs, read source code, or experimented before succeeding — the next agent would repeat that effort.
- The workflow has gotchas that aren't obvious from reading the code or CLAUDE.md.
- The workflow will recur (testing, observability, deployment, tooling integration, debugging a specific subsystem).

### How to Create a Skill

Skills live in `.claude/skills/<name>/SKILL.md`. The frontmatter needs `name` and `description` — the description should cover both what the skill does and when to trigger it, with concrete keywords.

Write the skill body goal-oriented: what to achieve, what tools to use, what to watch out for. Not step-by-step recipes — the reader is a capable LLM that reads CLAUDE.md and figures out commands. It needs to know the goal, the tools available, and the traps to avoid.

Include gotchas — that's where the value is. The things that wasted your time will waste the next agent's time too. Document them once.

Create skills **after** you've done the work. A skill written from guessing is worse than no skill — it misleads. A skill written from experience, even brief, saves real time.

### Skill Ideas by Domain

- **Testing** — pytest fixture patterns, Flutter widget test patterns, E2E with Marionette/Dart MCP, test warning root-cause fixes
- **Observability** — adding logging, health endpoints, request tracing, structured error reporting
- **Migrations** — idempotent SQL pattern, migration ordering, what happens at startup
- **MCP Integration** — adding a new MCP server, tool loop in chat, tool result rendering
- **Deployment** — first-time setup, ngrok, prod operations, rollback, data recovery
- **Audio Pipeline** — Kokoro TTS setup, Faster Whisper STT, remote vs local modes
- **Knowledge Base** — pgvector, embedding, RAG injection, chunking strategy
- **Rooms** — WebSocket multi-agent flow, connection management, agent turns

Don't create all of these upfront. Create a skill when you've just done the work and the gotchas are fresh in your mind.