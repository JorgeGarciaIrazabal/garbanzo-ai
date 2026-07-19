# Test Coverage Strategy

> Goal: raise meaningful coverage on the parts that matter, without chasing
> 100% on generated code, UI plumbing, or hard-to-test integrations.

Current baseline (measured locally with `just be-test-cov` / `just fe-test-cov`,
2026-07-19):

| Stack    | Coverage | Tests  |
|----------|----------|--------|
| Backend  | 77%      | 841    |
| Frontend | ~30%     | —      |

Combined + per-flag views on Codecov (`codecov.io/gh/JorgeGarciaIrazabal/garbanzo-ai`).
Status checks gate PRs through `codecov.yml` (see **CI gating** below).

> ℹ️ **Coverage concurrency config (2026-07-19).** `coverage.py` loses
> tracking across `await` points that go through async SQLAlchemy, because
> SQLAlchemy's async layer is built on **greenlet**. Without
> `concurrency = ["thread", "greenlet"]` in `[tool.coverage.run]`
> (backend/pyproject.toml), async endpoint/service function bodies that
> touch the DB are reported as missed even when executed — see
> [coveragepy/coveragepy#1082](https://github.com/coveragepy/coveragepy/issues/1082).
> The fix is already applied. Numbers below were re-measured with it on;
> pre-fix backend was 73% (auth.py 40% → 79%, rooms.py 49% → 88%,
> usage_service 43% → 97%, total 73% → 77%). Files that don't go through
> async SQLAlchemy (`ollama_provider`, `native_tools`, `tts_service`,
> `stt_service`) genuinely have the gaps shown — the fix doesn't inflate
> them. When re-baselining after future changes, keep the concurrency flag
> on or the numbers collapse back to the deflated 73%.

## What "critical" means here

Priority for new tests is driven by **blast radius**, not line count:

1. **Auth & security** — token issue/refresh, admin guards, rate limiting.
   A regression here exposes user data or the admin surface.
2. **Data integrity** — services that write to Postgres (chat, rooms,
   scheduled actions, memories, knowledge base). A bug corrupts history.
3. **Core user flow** — chat send/stream/store, the SSE parser, room
   WebSocket fan-out, Talk Mode. These are the paths users hit constantly.
4. **Money/ops** — usage accounting, FCM delivery, model management. Silent
   failures here cost real money or break notifications at scale.
5. **Nice-to-have** — UI widgets, dialogs, animations, generated `*.g.dart`
   and `app_localizations_*.dart`. Low priority; often not worth unit-testing.

## Backend priorities

Top gaps from `pytest --cov=app --cov-report=term-missing` (with the
greenlet concurrency flag on — see preamble), worst first.
File → current % → why it matters.

### Tier 1 — security & data integrity
| File | % | Why |
|------|---|-----|
| `app/api/v1/endpoints/auth.py` | 79 | Login/register/refresh/verify — the front door. Jumped from 40% after the greenlet fix; remaining 21% is refresh, password change, avatar upload edge cases. |
| `app/core/security.py` | 91 | Token create/decode, password hash. Already good; aim 100. |
| `app/services/friendship_service.py` | 99 | Writes friendship rows; used by share flow. ✅ at target. |
| `app/services/share_service.py` | 99 | Sharing items across users — privacy-sensitive. ✅ at target. |
| `app/services/memory_extraction.py` | 93 | Runs in a background job on user conversations; wrong output poisons memory. |
| `app/jobs/extract_memories_job.py` | 100 | Schedules the above. ✅ covered — drop from gap list if it stays. |
| `app/services/fcm_service.py` | 84 | Push delivery; failures go unnoticed by users. |
| `app/api/v1/endpoints/rooms.py` | 88 | Room CRUD + member management; data integrity. Jumped from 49% after the greenlet fix; remaining 12% is mostly error paths. |

### Tier 2 — core flow
| File | % | Why |
|------|---|-----|
| `app/services/native_tools.py` | 39 | Tool dispatch — tools execute with user permissions. No async SQLAlchemy → the 39% is real, not a measurement artifact. |
| `app/services/ollama_provider.py` | 42 | LLM streaming; bug = broken chat or leaked content. No async SQLAlchemy → real gap. |
| `app/services/chat_service.py` | 66 | Central chat orchestration. |
| `app/services/mcp_service.py` | 68 | MCP tool execution — external code with user perms. |
| `app/scheduler.py` | 52 | Runs scheduled actions & jobs. |
| `app/db/migrations.py` | 0 | Applied at startup; bad migration = won't boot. Needs real asyncpg+Postgres — hard to unit-test without breaking the "no real Postgres in tests" rule. |
| `app/db/session.py` | 33 | Engine/session factory; tested indirectly but not directly. |

### Tier 3 — operational
| File | % | Why |
|------|---|-----|
| `app/services/usage_service.py` | 97 | Accounting for billing/limits. ✅ at target after greenlet fix (was 43%). |
| `app/services/stt_service.py` | 44 | Whisper; optional, low blast radius. |
| `app/services/tts_service.py` | 33 | Kokoro; optional. |
| `app/services/model_management_service.py` | 38 | Model list/availability. |

### Not worth targeting
- `app/main.py` (27%) — startup wiring; covered by integration smoke tests.
- `*.g.dart` / `app_localizations_*.dart` — generated.
- `app/services/geocoding.py` — single-purpose HTTP wrapper; one happy-path test suffices.

## CI gating

`.github/workflows/ci.yml` runs `just be-test-cov` / `just fe-test-cov` on
every push to `main` and every PR, then uploads the reports to Codecov with
`codecov/codecov-action@v5` (one upload per flag: `backend`, `frontend`).
`codecov.yml` at the repo root configures status checks:

- **project** — per-flag floors (`backend` 75%, `frontend` 25%) with a 1pp
  tolerance, plus an `auto` default that compares to the parent commit.
- **patch** — new/changed code must be ≥70% covered (5pp tolerance).

A drop below a floor posts a failing status check on the PR; CI itself does
**not** hard-fail on upload errors (`fail_ci_if_error: false`) so a Codecov
outage doesn't block merges. Bump the floors when the baseline in this file
moves — they track the doc, not the other way around.

> The floors are set just above the current backend baseline (77%) so PRs
> that drop coverage post a failing check without flapping on noise.
> Keep the `concurrency = ["thread", "greenlet"]` flag in
> `backend/pyproject.toml` on, or the backend number collapses back to the
> pre-fix 73% and the floors will start gating on legitimate tests that
> *did* run but coverage missed.

## Frontend priorities

From `coverage/lcov.info`, files ≥20 lines at 0% (tests exist throughout the
`test/` tree, but coverage is concentrated in providers/services and the
Talk Mode controller).

### Tier 1 — services & API (logic, not UI)
| File | Lines | Why |
|------|-------|-----|
| `lib/features/admin/services/admin_service.dart` | 105 | Admin API client. |
| `lib/features/rooms/services/room_service.dart` | 111 | Room CRUD. |
| `lib/features/microapps/widgets/micro_app_panel.dart` | 129 | Micro-app render host. |
| `lib/features/friends/services/friends_service.dart` | 46 | Friend list mgmt. |
| `lib/features/friends/services/shares_service.dart` | 31 | Share API. |
| `lib/features/knowledge_base/services/knowledge_base_service.dart` | 33 | KB API. |
| `lib/features/scheduled_actions/services/scheduled_actions_api_service.dart` | 50 | Scheduler API. |
| `lib/features/memory/services/memory_api_service.dart` | 37 | Memory API. |
| `lib/features/reports/services/reports_service.dart` | 35 | User report submission. |
| `lib/features/settings/services/user_mcp_service.dart` | 56 | User MCP config. |
| `lib/features/usage/services/usage_service.dart` | 11 | Usage fetch. |

### Tier 2 — providers (state)
| File | Lines | Why |
|------|-------|-----|
| `lib/features/knowledge_base/providers/knowledge_base_provider.dart` | 24 | KB state. |
| `lib/features/usage/providers/usage_provider.dart` | 6 | Usage state. |
| `lib/features/admin/models/admin_model.dart` | 21 | Admin models. |
| `lib/features/admin/models/admin_user.dart` | 19 | Admin user model. |

### Tier 3 — widgets (defer unless a regression bites)
| File | Lines | Why |
|------|-------|-----|
| `lib/features/chat/talk/talk_mode_page.dart` | 203 | Talk Mode UI; controller is well-tested, UI is not. |
| `lib/features/chat/widgets/chat_page.dart` | 431 | Main chat screen. |
| `lib/features/rooms/widgets/room_message_bubble.dart` | 273 | Room chat bubble. |
| `lib/features/settings/pages/settings_page.dart` | 315 | Settings. |
| `lib/features/rooms/widgets/add_agent_dialog.dart` | 263 | Add-agent form. |
| `lib/features/chat/widgets/chat_message_widget.dart` | 184 | Message render. |
| `lib/features/chat/widgets/chat_input_widget.dart` | 165 | Input bar. |
| `lib/features/admin/widgets/mcp_server_dialog.dart` | 151 | MCP config form. |

Frontend widgets get low ROI for line coverage — most logic is in providers
and services, which are cheaper to test. Prefer widget tests for the few
widgets with non-trivial interaction (`MessageComposer`, `ChatPage` search,
`AddAgentDialog`) and leave pure-presentation widgets alone.

### Not worth targeting
- `lib/l10n/gen/app_localizations_*.dart` — generated (863 lines Spanish, etc.).
- `*.g.dart` — Freezed/json generated.
- `lib/core/reading_column.dart`, `fade_slide_in.dart`, `pulsing_dot.dart` — pure animations.

## Testing conventions

### Backend
- Use the existing `tests/conftest.py` in-memory SQLite fixtures; never hit Postgres.
- HTTP tests via `httpx.AsyncClient` against the FastAPI app; assert status,
  body, and a side effect on the DB.
- Service tests construct the service with a swapped `async_session_maker`
  (see conftest) and assert on returned data + DB rows.
- Mock external calls (`ollama`, `httpx`, `firebase`) with `unittest.mock` or
  `pytest`'s `monkeypatch`. Never call real Ollama/FCM in CI.
- For jobs, call `apply_migrations()` then run the job function directly —
  don't wait for the scheduler.
- Naming: `tests/<area>/test_<thing>_test.py::test_<scenario>`.
- Run: `cd backend; uv run pytest tests/path/test_x.py::test_name` (or
  `just be-test`).

### Frontend
- Providers/services: `ProviderContainer` + `mockito` fake APIs. Assert
  state transitions and emitted side effects, not widget trees.
- Repositories: fake the HTTP client with a stub returning canned JSON.
- Widget tests: only for widgets with branching logic (search debounce,
  composer keyboard handling, form validation in dialogs). Use
  `testWidgets` + `WidgetTester`; pump and assert on `find.byType`/`byKey`.
- Keep tests deterministic — no real timers. Use `fakeAsync` where needed.
- Naming: `test/<area>/<thing>_test.dart`.
- Run: `flutter test test/path/test_x.dart` (or `just fe-test`).

## Workflow

1. Pick the highest-tier gap from the tables above.
2. Write tests until that file is ≥85% (backend) / ≥75% (frontend) or
   all branches with side-effects are covered — whichever first.
3. Run `just be-test-cov` / `just fe-test-cov`; confirm the local number moves.
   The backend number *will* move for DB-touching code now that the
   greenlet concurrency flag is on (see the preamble note). If a test runs
   a code path but the line still shows missing, check whether the path
   goes through a library that uses its own greenlet/eventlet — those need
   additional `concurrency` entries.
4. Commit tests alongside any refactor needed to make the code testable
   (e.g. injecting the session/engine). If you change behavior, also update
   the relevant `docs/` file per AGENTS.md.
5. Push and watch the Codecov badge. Don't chase a single combined number —
   watch per-file deltas in the Codecov report.

## Targets (12-month)

| Stack    | Now | Target | Stretch |
|---------|-----|--------|---------|
| Backend | 77% | 85%    | 90%     |
| Frontend | ~30% | 50% | 65%      |

Targets stop there deliberately. Past ~90% you're testing generated code,
animations, and integration glue that's better covered by E2E (see the
`e2e-testing` skill) than by unit tests.

## Reconciliation

Re-run this audit quarterly (or after a large feature lands):

```bash
just be-test-cov
just fe-test-cov
# backend: tail of pytest output has the per-file table
# frontend: awk lcov.info as in this file's preamble
```

Update the tables and tiers when the shape of the code changes. Delete
entries that hit target — don't let this file pretend gaps still exist.

If you change anything under `[tool.coverage.run]` in
`backend/pyproject.toml` (especially the `concurrency` setting), re-measure
from scratch — the backend number is sensitive to it. See the preamble note
for what the greenlet flag does and why removing it drops coverage back to
~73% without any code change.