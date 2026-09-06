# Dynamic Context + Unified Chat — Acceptance Matrix

Status legend: `Pending` is not yet implemented or cannot yet be exercised;
`Pass` requires focused automated evidence (and E2E where indicated). The
validation report records deferred flows and quality-gate failures separately.

| Area | Acceptance criterion | Required evidence | Status |
|---|---|---|---|
| Primary surface | One primary conversation is durable across restart/devices and is created idempotently; legacy conversations remain threads. | Concurrent ensure-primary API/service test; thread-list regression; E2E. | Pass — concurrency/thread tests pass; configured Linux sign-out/login returns to the primary landing with no stale 403/auth state. Process launch is separately deferred because no launch/stop tool was exposed. |
| Evidence grounding | Every promoted fact, decision, preference, constraint, deadline, and open loop cites active, owned source evidence; assistant-only claims remain proposals. | Service/compiler tests for authority, ownership, source span, and validation rejection. | Pass |
| Corrections and discarded state | New explicit corrections supersede earlier claims; explicit rejections become minimal guardrails; forget removes the material entirely; ambiguous rejection stays uncertain. | Assertion/exclusion tests, including reversal and no rejected-item rediscovery. | Pass |
| Edit/delete lifecycle | Message edits/deletes, conversation delete/restore, memory deactivation, and KB deletion revoke affected material before the next request. | Transaction/event and compiler hard-filter tests. | Pass |
| Live context | A committed turn writes a durable event and produces a validated live delta within seconds without delaying the reply. | Ingestion idempotency/watermark tests; SSE test; E2E. | Pending — service/SSE-ingestion evidence passes; device live-SSE E2E is deferred. |
| Hourly cache | Only dirty users are leased; retries and replicas are safe; a failure retains the previous immutable pack and watermark. | Scheduler/consolidation tests for lease, idempotency, atomic promotion, and retry. | Pass |
| Rebuild integrity | Evidence-first rebuilds do not compound summaries or resurrect invalid/rejected material. | Multi-version rebuild regression test. | Pass |
| Context compiler | Compiles prepared pack + live delta + pins + exclusions under budget, isolates siblings, and falls back safely for cold/failed preparation. | Compiler unit tests, metadata assertion, and generation integration test. | Pass |
| Privacy isolation | All topic/context reads and evidence references are user-scoped; local-only mode never calls a cloud curator. | Cross-user endpoint/service tests and provider-config test. | Pass |
| Topic discovery | Personal topics derive from history; parents are directly startable; promoted children show `Subtopic in <parent>`; phone is vertical and desktop/tablet horizontal without overlap. | Provider/model and widget tests at 320, 390, tablet, desktop; E2E. | Pending — responsive/widget evidence passes; history-derived Personal E2E is deferred. |
| Threads | Threads retains search, pin, mute, delete/undo, settings, exact history, branching, scheduled action links, and a distinct New thread. | Existing conversation regression tests plus widget/E2E coverage. | Pending — focused search/pin/mute/delete/undo/branch/proposal coverage passes; action E2E is deferred. |
| Active context | Visible, explainable, editable included/pinned sources; Fresh start clears context without deleting history; no Activity tab/endpoint. | Endpoint tests, panel widget tests, source-code/API audit, E2E. | Pass — Linux split-pane panel smoke completed without overflow/runtime errors after the final UI fixes. |
| Composer controls | New topic preserves timeline; response style exposes model, instructions, and effort; model changes preserve/select valid effort. | Conversation/style tests and composer widget tests. | Pass — Linux bottom-composer smoke and `Tutoring` style persistence across `Off → High` completed. |
| Normalized effort | Fixed Off/Low/Medium/High positions always render; unsupported choices are disabled, cannot cycle/select/persist, and map deterministically to native provider values. | Model/schema/provider mapping tests and widget tests. | Pass |
| Quality gate | Relevant focused tests, full backend/frontend suites, lint/analysis, E2E, and health checks pass with no warnings. | `just` command output recorded in validation report. | Pending — automated gate and configured login E2E pass; launch, history-derived Personal topics, full Threads actions, and committed-turn/live-SSE E2E remain deferred. |

## Planned automated test coverage

- Backend: primary conversation API/service, model capability validation, evidence authority/exclusions, event ingestion, consolidation, context compiler, and context endpoints.
- Flutter: new Freezed fields, topic/context providers, primary landing, sidebar threads, Active context, and composer effort controls.
- E2E: primary/chat/topic/context/thread/style flows on Linux once implementation is runnable.

## Latest QA checkpoint (2026-08-31)

- Recovery-focused backend dynamic-context gate: **72/72 passed**. This now
  includes real concurrent primary creation, request-time memory/KB/thread
  revocation and restoration, default local-only consolidation, and committed
  turn/SSE-ingestion evidence.
- Focused UI acceptance suite: **47/47 passed**; system-prompt/banner suite:
  **15/15 passed**. The constrained-width banner regression is covered.
- Full current-tree `just test`: **1114 backend + 699 Flutter tests passed**;
  no warnings or failures (`1114 passed in 196.47s`; latest Flutter total
  `699/699`).
- Expanded Flutter acceptance gate: **73/73 passed**, including 320px, 390px,
  768px tablet, and desktop topic layouts; super-topic/visible-child selection;
  landing-to-chat replacement; and legacy search, pin, mute, delete/undo,
  branch, scheduled-action provider, and proposal-link regressions.
- Latest `just check`: **PASS**; formatting, Ruff, Pylint/import lint, Flutter
  generation/analyze, and the final `All checks passed — ready to commit.`
  message all completed successfully. `git diff --check` is also clean.
- Connected Linux final smoke: Topics/Threads/Rooms navigation, primary topic
  activation, split Active context, bottom composer, named style/effort
  preservation, and configured sign-out/login all pass; DTD runtime errors are
  clear after the settled flows. No top style/model selector is present. The
  app-launch and committed-turn/live-SSE flows remain unverified and are not
  treated as passes.
- Matrix status: **11 Pass / 4 Pending**; all Pending rows retain an explicit
  E2E or environment-backed evidence gap.
