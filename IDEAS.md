# Ideas — Expanded Backlog

Difficulty legend (pick the model per task, not per feature):

| Tag | Meaning | Suggested model |
|-----|---------|-----------------|
| `easy` | Mechanical, well-trodden pattern in this repo, low ambiguity | Haiku / small model |
| `easy-med` | Mostly mechanical but touches 2+ layers or needs a migration | Sonnet |
| `medium` | New endpoint/widget with some design decisions, single feature area | Opus |
| `med-hard` | Cross-cutting, stateful UI, or careful prompt/tool design | Fable |
| `hard` | Novel UX, tricky Flutter internals, multi-step agentic behavior | Fable |

Work task by task in order, use subagent with right model to execute on each of the subtasks and commit/push after each task is completed

---

## Open / pending

- [ ]  ONLY DO IF IT IS EASY `medium` **11. Onboarding tour powered by the help docs** — First-login checklist/coach-marks generated from the same app-guide docs as idea 4, so there's one source of truth for "how the app works".

## 20. Revert a delegated workflow's changes (native action)

Now that idea 18 auto-applies a finished run's diff straight to the user's
folder (no review gate), the missing half is **undo**. A run leaves a clean
record of what it changed — the `/changes` response carries each file's
`base_sha256` (the pre-run hash) and the baseline commit lives in the
server-side snapshot until `/applied` releases it — so the agent can put the
folder back the way it was without the user fishing through git by hand.

Surfaced as a native action the LLM can call ("revert the last thing you did
to my folder"), and as a button on the finished-run line for a mouse click.
Also reachable from a scheduled action, so "every morning at 6am, revert
anything the agent did overnight" is a one-liner.

- [ ] `easy-med` **Backend: `revert_workflow` native tool** — New proposal tool in `native_tools.py` that, given a `workflow_run_id` (default: the user's most recent `done` run on the current conversation), calls `workflow_service.compute_changes` against the still-baseliend snapshot, inverts it (added → delete, modified → restore base, deleted → restore base), and hands the inverted diff back to the client. **The snapshot is NOT released until revert is no longer possible** — change `/applied` to keep the snapshot for a retention window (or until the user explicitly dismisses the run), otherwise this idea can't work after the first run.
- [ ] `medium` **Frontend: "Revert" on the finished run line** — A button next to the applied-result line on `WorkflowRunTile`. Calls `WorkflowProvider.revert(runId)`, which posts to a new `/workflows/{id}/revert` endpoint (or applies the inverted client-side diff the tool returns), then surfaces the same kind of result line ("N files reverted"). Per-run idempotent like apply.
- [ ] `easy-med` **Scheduled-action parity** — `scheduled_action_job.py` already re-hydrates the conversation a scheduled action fires in; allow a scheduled action's prompt to call `revert_workflow` so "revert what the agent did" can run on a schedule.
- [ ] `easy` **Docs** — Help doc entry ("How do I undo what the agent did?"), `docs/api.md`, `docs/architecture.md`.

## 21. Manual conversation compaction (Claude Code `/compact`)

Let the user trigger compaction on demand so a long conversation stays usable
without waiting for the 80%-of-context-window auto-trigger. Claude Code's
`/compact` summarizes the conversation so far into rolling context notes and
continues from there; this app already has the machinery — it just isn't
user-triggered.

**What exists today (the foundation):**
- `ChatService._maybe_summarize_context` (`backend/app/services/chat_service.py:127`)
  runs at the top of every turn (`:462`) and, when the prompt token count
  exceeds **80% of the effective context window** (`:150`), summarizes
  everything before the last 10 messages into rolling prose notes. It writes
  the result to `conversation.context_summary` and tracks the boundary in
  `conversation.context_summary_until_id` (`Conversation` model,
  `backend/app/models/conversation.py:47-48`).
- `ChatContextBuilder.build_history_with_system_prompt`
  (`backend/app/services/chat_context.py:141`) drops every message up to
  `context_summary_until_id` and injects the summary as a second system
  message (`:192-198`), so subsequent turns only pay for unsummarized
  messages + the summary.
- Context-window resolution: `resolve_context_length`
  (`backend/app/services/llm_provider.py:171`) = `max(512, min(model_max,
  settings.llm_context_window))`. The token counter is
  `get_token_counter()` (`token_counter.py:85`, tiktoken `cl100k_base` with
  a word/char fallback).
- The frontend already renders the auto-summary
  (`lib/features/chat/widgets/context_summary_widget.dart`) and a
  context-usage indicator
  (`lib/features/chat/widgets/context_window_indicator.dart`) — so the UI
  surface a compact-now affordance slots into already exists.
- **Rooms have no compaction at all** — `RoomChatService._load_history`
  (`backend/app/services/room_chat_service.py:196`) is last-N only (`limit=50`
  for turn selection, `limit=100` after a reply). A `/compact` parity for
  rooms is a larger follow-up; out of scope for the first cut.

**The slash-command pattern to copy — `/agent`:**
- Backend: `_forced_agent_instruction` (`chat_service.py:77-82`) detects a
  leading `/agent` token in `send_message` (`:282`) / `edit_and_resend`
  (`:410`) and diverts the turn into `_stream_forced_workflow` (`:546-616`)
  instead of the normal LLM path — a deterministic execution that never
  asks the model "should I?".
- Frontend: a `MentionCandidate` with `insertText: '/agent'` is the first
  entry in `_templateCandidates()` (`chat_input_widget.dart:107-126`),
  surfaced by the `MentionAutocomplete` overlay when the user types `/`.
  Selecting it inserts the literal `/agent` token; the user types the rest.

A `/compact` command follows the same three layers.

- [ ] `easy-med` **Backend: `/compact` command** — Detect a leading `/compact`
  (mirror `_forced_agent_instruction` at `chat_service.py:77-82`) in
  `send_message` / `edit_and_resend`. Instead of streaming an LLM reply, run
  the summarization core of `_maybe_summarize_context` (`:127`) **forced over
  the entire unsummarized history** (not gated at 80%, and keep fewer — or
  zero — recent messages intact, since the user is explicitly asking to
  compact). Write `context_summary` + `context_summary_until_id` on the
  conversation. Yield a short confirmation chunk (e.g. a `tool_result`-style
  info message "Compacted N messages into rolling context notes") so the
  frontend renders a breadcrumb in the message list and the
  `context_summary_widget` updates. Reuse the existing summary prompt at
  `:183-192` ("Condense the following conversation excerpt…"). Optional: a
  `/compact keep-last K` variant where K is configurable.
- [ ] `easy` **Backend: `/compact` parity for `edit_and_resend`** — When the
  user edits a message to `/compact`, compact up to *that* message rather
  than the latest. Cheap once the core command exists.
- [ ] `easy` **Frontend: `/compact` mention candidate** — Add a
  `MentionCandidate` in `_templateCandidates()` (`chat_input_widget.dart:107`)
  beside `/agent`, with `insertText: '/compact'` and a short
  label/description (e.g. "Summarize this conversation so far"). No new
  widget — the autocomplete machinery (`mention_autocomplete.dart:22`,
  sources `{'+', '/', '#'}`) already handles the trigger + insertion.
- [ ] `easy-med` **Frontend: compaction breadcrumb + manual trigger button** —
  Render a one-line "Compacted N messages" system-style message in the chat
  list when a turn's `context_summary` changed (the existing
  `context_summary_widget.dart` + `context_window_indicator.dart` are the
  surface). Add an explicit "Compact now" entry alongside the
  context-indicator (icon button) so the feature is discoverable without
  knowing the `/compact` token — it dispatches the same `/compact` send.
- [ ] `medium` **Frontend: undo last compaction** — Because compaction writes
  `context_summary_until_id`, an undo can clear the summary columns and
  reload the full message window. Cheap on the backend (a
  `DELETE /conversations/{id}/summary` or a `PATCH` clearing the two
  columns); frontend adds a "Restore full history" affordance on the
  compaction breadcrumb. Decide if this is worth the surface area.
- [ ] `medium` **Rooms parity (follow-up, larger)** — `RoomChatService` has
  no summarization. A room `/compact` would need a per-room or per-agent
  summary store (new columns on `Room` / `RoomMember`, or on the agent's
  view) and a summary-injection point in `_build_llm_history`
  (`room_chat_service.py:798`) analogous to `chat_context.py:192-198`.
  Defer unless long rooms become a pain.
- [ ] `easy` **Tests** — Backend: `/compact` command on a 30-message
  conversation compacts all-but-last-K and sets both columns; subsequent
  `_stream_assistant_turn` sends only the summary + tail (assert via the
  message list passed to `run_agent_turn`); `/compact` on an already-summarized
  conversation extends (not replaces) the summary (the auto path appends at
  `:213-217`). Frontend: widget test that the context indicator shows a
  reduced window after a compact.
- [ ] `easy` **Docs** — `docs/architecture.md` (manual compaction flow, how
  it reuses the auto-summarizer), `docs/api.md` (any new endpoint), and a
  help entry in `backend/app/docs/help/chat.md` ("How do I shorten a long
  conversation?") so the `app_help` tool can answer it.

## 22. Auto-file errors as user bug reports

When something breaks on either stack, file it as a `Report` automatically
(the admin-visible triage table from idea 14) — with enough metadata
(conversation id, message id, timestamp, stack trace, platform, model, last
user turn) that triaging can reproduce it. Today errors become either a
log line on the backend (`logging` to stdout, no persistence) or a
user-facing error string in a Flutter provider, and neither reaches the
`Report` table unless the user manually opens "Report a bug".

**What exists today (the foundation):**
- `Report` model (`backend/app/models/report.py:16`, migration
  `026_reports.sql`): `id`, `user_id` (FK `users.email`, cascade), `type`
  (`bug`|`feature`), `title` (≤200), `description` (Text), `status`
  (`open` default), timestamps. **No structured-metadata column exists** —
  `conversation_id` / `message_id` / `stack_trace` / `platform` would
  either be packed into `description` or added via a new migration
  (`metadata JSONB`, `conversation_id`, `severity`).
- `ReportService` (`backend/app/services/report_service.py:23`)
  `create(user_id, type_, title, description)` + `notify_admins` (best-effort
  FCM/in-app to admins, failures suppressed). Endpoint
  `POST /api/v1/reports` (`endpoints/reports.py:29`) derives the user from
  the JWT (`current_user["email"]`).
- Frontend `ReportsService.instance.create(type, title, description)`
  (`lib/features/reports/services/reports_service.dart:14`) — the exact call
  an auto-file helper would use with `type: 'bug'`. The JWT in `ApiClient`
  identifies the user, so no user_id arg is needed.
- **No Sentry / Crashlytics / Bugsnag** on either stack (checked
  `pubspec.yaml` + `pyproject.toml`) — the `Report` table becomes the
  error-tracking store with nothing to reconcile against.
- User identity = email string, derived from the JWT on the backend
  (`current_user["email"]`) and available via `ApiClient` on the frontend.

**The gaps:**
- Frontend (`lib/main.dart:32`): **no global error handler** — no
  `FlutterError.onError`, no `runZonedGuarded`, no
  `PlatformDispatcher.instance.onError`. `runApp` is called directly.
  Uncaught framework/isolate errors aren't captured anywhere.
- Backend (`app/main.py:201`): **only `CORSMiddleware` is registered** — no
  `@app.exception_handler(Exception)`, no `ServerErrorMiddleware`. Unhandled
  endpoint exceptions fall through to FastAPI's default 500 + a uvicorn
  traceback to stdout.
- API client (`lib/core/api_client.dart:37`): `validateStatus: (s) => true`
  means non-2xx never raise `DioException`; the `onResponse` interceptor
  handles **only 401** (`:170-208`). Network/timeout `DioException`s
  propagate to providers, which catch them into a `String` error and stop
  there — no reporting.

- [ ] `easy-med` **Backend: `Report` metadata migration** — Add a
  `metadata JSONB` column (and an indexed `conversation_id` FK-ish String,
  plus `severity` / `source` literals: `frontend` | `backend`) to `reports`
  via an idempotent `NNN_reports_metadata.sql` migration mirroring
  `026_reports.sql`. Extend `ReportService.create` to accept optional
  `metadata`/`conversation_id`/`severity`/`source`, and `ReportCreate` +
  `ReportOut` schemas accordingly. Keep `type=bug` for auto-filed errors.
  *(This is strictly additive — existing manual reports keep working.)*
- [ ] `med-hard` **Backend: global exception handler** — Register
  `@app.exception_handler(Exception)` (or `ServerErrorMiddleware`) in
  `main.py` that, for any unhandled exception in an authenticated request,
  opens a **fresh** session via `async_session_maker()` (late import — the
  request's session is likely poisoned post-exception; follow the
  background-task pattern in `_make_push_callback` at `chat.py:453`) and
  calls `ReportService.create(type='bug', source='backend', title=<Exception
  class + one-liner>, description=<full traceback>, metadata={
  path, method, query, user_id if derivable, conversation_id if in path },
  severity='error')`. Re-raise after filing so FastAPI still returns the
  500. Rate-limit per (user, exception_fingerprint) so a tight retry loop
  doesn't flood the table (e.g. one per fingerprint per 5 min, in-memory
  or via a small DB unique-ish guard). 401/403/404 and other 4xx should
  **not** auto-file (only 5xx / uncaught).
- [ ] `easy-med` **Backend: stream-error capture in the chat path** — The
  streaming chat endpoints catch errors and yield `error` `ChatChunk`s
  (`agent_turn.py:360`, `chat_service.py:221`, `ollama_provider.py:290-318`).
  Add a thin `report_chat_error(...)` helper that files a Report with
  `conversation_id`, the in-flight `message_id`/tool_call id, the model,
  and the last user turn's text (truncated) in `metadata` — called from
  the spots that already `logger.exception(...)` in the chat/agent path.
  Keep it best-effort (`contextlib.suppress`) so error reporting never
  breaks the turn.
- [ ] `med-hard` **Frontend: global error capture** — In `main.dart`, wrap
  `runApp` in `runZonedGuarded` and install `FlutterError.onError` +
  `PlatformDispatcher.instance.onError`. On any uncaught framework or
  isolate error, call a new `ErrorReporter.report(error, stack,
  {conversationId, messageId, context})` that posts to
  `ReportsService.instance.create(type: 'bug', title: <Error one-liner>,
  description: <stack + platform + app version + context JSON>,
  metadata: {...})` (requires the metadata migration's endpoint to accept
  the extra fields). Guard against the report call itself throwing
  (try/catch + swallow). Debounce on the client too (same fingerprint →
  one report per session) so a render-loop error doesn't spam. Include
  `package_info_plus` app version + `Platform.operatingSystem` + the
  `PlatformInfo` desktop/web/Android classification already used by the
  updater (idea 19).
- [ ] `easy-med` **Frontend: API/network error capture** — Add a Dio
  `onError` interceptor in `api_client.dart` (and/or a wrapper around the
  convenience methods) that, for unexpected `DioException`s (timeouts,
  connection errors, 5xx responses that still raise), files a Report with
  `{method, url, statusCode, responseBody}` in metadata, *excluding* 401
  (already handled) and user-initiated cancel. Keep it consistent with the
  backend handler's rate-limit semantics. Be careful not to recurse: the
  report call goes through the same `ApiClient`, so gate it with an
  `isReporting` flag / use a raw `Dio` for the report POST.
- [ ] `medium` **Frontend: context capture** — The error handler needs
  `conversationId` / `messageId` that live on `ChatProvider`. Since the
  global handler can't reach a provider, expose the *last active context*
  via a lightweight singleton (`ErrorReporter.setContext({conversationId,
  messageId, ...})` updated by `ChatProvider` / `RoomProvider` on
  navigation). On error, the reporter reads the singleton. This is the
  same "cheap to re-pick per session" pattern the spoken-language pref
  (idea 13) uses — no backend column, just in-memory.
- [ ] `easy-med` **Admin triage: surface metadata** — The existing
  `ReportsTab` (`lib/features/admin/...`, idea 14) shows title/description/
  status. Extend it to render the `metadata` JSON (conversation id → deep
  link to the conversation, stack trace in an expandable, platform/severity
  badges) so an admin triaging an auto-filed bug can jump straight to the
  failing conversation and reproduce. Keep manual bug reports (no metadata)
  looking identical.
- [ ] `easy` **Tests** — Backend: exception handler files a Report with a
  traceback into `metadata` and re-raises; rate-limit dedupes identical
  exceptions within the window; 4xx don't file. Chat-path helper files with
  `conversation_id` + `message_id`. Frontend: `ErrorReporter` debounces by
  fingerprint within a session; the report POST is excluded from the
  interceptor (no recursion); `setContext` is read at report time.
- [ ] `easy` **Docs** — `docs/api.md` (new `metadata`/`conversation_id`/
  `severity`/`source` fields on `ReportCreate`/`ReportOut`, note that
  `POST /reports` now accepts them), `docs/database.md` (`reports` new
  columns), `docs/architecture.md` (error→Report pipeline on both stacks),
  and a help entry ("How do I report a bug?" already exists from idea 14 —
  add a note that errors are auto-reported unless you opt out). Add an env
  var / settings toggle to disable auto-filing (e.g. `auto_error_reports:
  bool = true`) in `docs/environment.md` for self-hosters who don't want
  their server filing reports to itself.

