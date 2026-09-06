# Dynamic Context + Unified Chat Validation Report

Date: 2026-08-31

Owner: Final QA

Scope: recursive backend/frontend test gate, implementation audit, and Linux
Flutter smoke validation. QA did not manually modify implementation code.

## Verdict

**PASS for the automated gate and exercised Linux smoke.** The focused suites,
formatting, lint/analysis, clean-diff check, health checks, sidebar/topic
navigation, style/effort preservation, Active context split pane, and the
configured test-user sign-out/login flow pass. Overall acceptance remains
**DEFERRED** only for history-derived Personal-topic coverage, full Threads
action E2E, and committed-turn/live-SSE E2E.

## Automated command evidence

| Command | Result | Evidence / warnings |
|---|---|---|
| Recovery-focused backend (`just be-test tests/test_dynamic_context.py tests/test_dynamic_context_contracts.py tests/test_dynamic_context_endpoints.py tests/test_topic_context_pipeline.py tests/test_topic_models.py tests/test_conversation_thinking_level.py tests/test_context_budgets.py`) | **PASS** | `72 passed in 12.71s`; no warnings. Added concurrent primary creation, mutable-source hard-filter, default local-only, and committed-turn/SSE-ingestion regressions. |
| Focused UI acceptance suite (sidebar, topic/context, composer, style, and effort surfaces) | **PASS** | `47/47` tests passed; no warnings. |
| System-prompt/banner suite | **PASS** | `15/15` tests passed; the constrained-width banner regression is covered. |
| Expanded Flutter acceptance (`just fe-test test/widgets/dynamic_context_widgets_test.dart test/chat/conversation_mute_test.dart test/chat_provider_streaming_test.dart test/chat_provider_actions_test.dart test/providers/search_provider_test.dart test/widgets/action_proposal_card_test.dart test/scheduled_actions/scheduled_actions_provider_test.dart`) | **PASS** | `00:01 +73: All tests passed!`; covers 320px/390px/768px tablet/desktop layouts, super-topic and promoted-child selection, full landing replacement after activation, search, pin, mute, delete/undo, branching, scheduled-action provider behavior, and proposal deep links. |
| `just test` (full current-tree baseline) | **PASS** | Backend: `1114 passed in 196.47s (0:03:16)`; latest Flutter: `699/699` passed; no warnings or failures. |
| `just check` (final current-tree rerun) | **PASS** | Ruff format: `245 files left unchanged`; Dart format: `247 files (0 changed)`; Ruff check passed; Pylint/import lint passed with `10.00/10`; Flutter analyze: `No issues found! (ran in 6.2s)`; final output: `All checks passed — ready to commit.` |
| Final `be-lint-imports` stage in `just check` | **PASS** | No C0415 findings; the architectural cycle fix and new `topic_normalization` leaf removed the last import-lint blocker. |
| `git diff --check` (final current-tree rerun) | **PASS** | No whitespace errors or output. |
| `just fe-lint` (latest recovery run) | **PASS** | `flutter gen-l10n` emitted its normal `l10n.yaml` informational note; `flutter analyze`: `No issues found! (ran in 6.2s)`. |
| English/Spanish ARB key parity | **PASS** | Both `lib/l10n/app_en.arb` and `lib/l10n/app_es.arb` contain 889 non-metadata keys; `comm` found no difference. |

No current automated quality-gate blocker remains. The final check was run
against the shared tree after the topic-normalization cycle fix and banner
regression fix. The latest full Flutter total is **699/699**; the earlier
post-recovery baseline recorded above was **689** before the final UI tests
landed.

The matrix currently contains **11 Pass / 4 Pending** rows. The remaining
Pending rows are not automated test failures: they require history-derived
Personal-topic, full Threads-action, or device-level live-SSE E2E evidence.

## Health and Linux E2E smoke

The existing backend was already running; PostgreSQL was confirmed with
`just docker-up-db`. Both read-only health checks returned HTTP 200:

```text
GET /api/v1/health       {"status":"ok","message":"Garbanzo AI backend is running","version":"0.0.0-dev"}
GET /api/v1/chat/health/llm  {"ollama":true}
```

Dart DTD and Marionette were available and connected to the existing Linux
debug app. No launch/stop tool was exposed, so process launch itself remains
deferred; the configured test account was available for the in-app auth flow.
Marionette application logs were unavailable because `get_logs` returned an
MCP server error, so runtime-error checks and the visible widget tree are the
authoritative E2E evidence below.

### Final isolated Linux checkpoint (2026-08-31)

The connected app was hot-restarted before the final acceptance sequence. The
final settled tree was a 984px-wide Linux desktop view. After the parent QA
pass covered topic activation, the split Active context pane, composer input,
named style/effort transition, and all sidebar tabs, Final QA independently
completed Settings → Sign out → login with the configured `test@garbanzo.dev`
account. The post-login tree returned to the primary landing and contained no
stale authorization error. Password material is intentionally omitted from
this report.

| Flow | Result | Observed evidence |
|---|---|---|
| Launch | **DEFERRED** | No launch/stop capability was exposed; QA used the already-running Linux debug app and performed a full hot restart before the final flow. |
| Sign out → login | **PASS** | Fresh Settings → Sign out; `email_field` and `password_field` accepted the configured test account; `login_button` returned to the primary landing after a 3.5-second settle. No stale `403`, `Not authenticated`, or `Failed to load` text appeared, and the final DTD runtime query returned `No runtime errors found.` |
| Primary/topic landing | **PASS (smoke)** | Primary landing rendered `topic_landing`, Personal/Explore selector, `message_input`, `new_topic_button`, normalized effort chip, and Active context control both before and after login; `Learn something, active now` was visible. |
| Sidebar Topics / Threads / Rooms | **PASS (navigation smoke)** | Fresh interactive trees exposed `sidebar_tab_topics`, `sidebar_tab_threads`, and `sidebar_tab_rooms` with full single-line labels. Each tab was tapped and its semantics selected state changed correctly; no runtime errors were reported. Full Threads actions remain deferred, so the matrix row remains Pending. |
| Top app bar | **PASS** | `Primary chat` and Settings rendered in the top bar; no top style/model selector was present. The sole `style_picker_button` was in the bottom composer. |
| Topic activation / Active context | **PASS (panel smoke)** | `Learn something` activation replaced the landing; the Active context panel rendered at the split-pane width (`active_context_panel`, 340px wide) with topic, pinned/selected controls, source explanation, add-source, and close affordances. Parent QA observed no overflow or runtime errors after the banner/composer fixes. |
| Composer and style/effort | **PASS (input/style smoke)** | Bottom `message_composer_surface` rendered with `message_input` and controls. Parent QA entered unsent text, applied named style `Tutoring`, changed effort `Off → High`, and confirmed the `Tutoring` label persisted. No message was sent, so committed-turn/live-SSE behavior remains deferred. |
| Runtime errors after final flows | **PASS** | Final hot-restarted app and settled sign-out/login flow both returned `No runtime errors found.` The prior constrained-width `system_prompt_banner` overflow was fixed; the banner regression suite is `15/15` green. |

The pre-recovery smoke had reported:

```text
ListTile background color or ink splashes may be invisible.
lib/features/chat/widgets/chat_sidebar.dart:212
```

The recovery added the local `Material` surface. The banner/composer fixes
also removed the constrained-width overflow reproduced during an earlier
topic activation. The historical assertions are retained here for traceability
and are not current failures.

## Acceptance audit

The acceptance matrix was updated only for rows supported by the evidence.

| Area | Status | Evidence / remaining gap |
|---|---|---|
| Primary surface | **Pass** | Concurrent and sequential idempotent ensure plus thread filtering pass; Linux sign-out/login with the configured test account returned to the primary landing with no stale 403/auth state. Process launch itself was not exercised because no launch/stop tool was exposed. |
| Evidence grounding | **Pass** | Compiler hard-filters deleted, excluded, cross-user, and unowned sources; consolidation rejects unknown/unowned evidence. Covered by `test_compiler_combines_pack_live_delta_pins_and_hard_exclusions` and `test_consolidation_rejects_unknown_and_cross_user_evidence`. |
| Corrections and discarded state | **Pass** | Explicit rejection, privacy forget, ambiguous rejection, edit invalidation, and evidence relations covered by `test_ingestion_rejection_forget_and_ambiguous_rejection_semantics`. |
| Edit/delete lifecycle | **Pass** | Message edit/delete and conversation-delete invalidation pass. Request-time compiler coverage now proves inactive memories, failed/deleted KB documents, and deleted threads are removed before the next compile, while source restoration before that compile is immediately visible. |
| Live context | **Pending** | A real primary `ChatService` turn now proves schema-v1 topic/context metadata is emitted before provider work and that user/assistant mutation events commit, watermark, and deduplicate. No message was sent in Linux QA; device E2E validating visible live delta timing remains deferred. |
| Hourly cache | **Pass** | Dirty-only lease, expiry/retry, immutable promotion, and failure retention covered by consolidation tests. |
| Rebuild integrity | **Pass** | Multi-version evidence-first rebuild and failed-pack pointer retention pass. |
| Context compiler | **Pass** | Pack + live delta + pins + exclusions, budget trimming, cold fallback, primary-vs-legacy isolation, generation wiring, and metadata contracts pass. |
| Privacy isolation | **Pass** | Cross-user endpoint/compiler ownership checks pass. Default settings are `local_only` with no curator model; configured `glm-5.3-flash:cloud` is also blocked before provider resolution in `local_only`. With explicit `cloud_allowed`, curator output is limited to the filtered manifest and same-user topic candidates, then exact-content, ownership, schema, and hierarchy validation gates promotion. |
| Topic discovery | **Pending** | Provider/model plus 320px/390px/768px tablet/desktop widget checks, direct super-topic and promoted-child selection, landing replacement after activation, and Linux Explore activation pass. History-derived Personal-topic E2E remains deferred. |
| Threads | **Pending** | Search provider, pin, mute, delete/undo, branch, scheduled-action provider, and proposal/deep-link regressions pass; navigation smoke passes. Full action E2E and exact-history E2E remain deferred. |
| Active context | **Pass** | Endpoint optimistic-version/Fresh start tests, panel explainability/no-Activity widget test, source/API audit, and Linux split-pane panel smoke pass with no overflow/runtime errors after the final UI fixes. |
| Composer controls | **Pass** | Style picker model/instruction/effort tests, model transition tests, topic reset/provider tests, and Linux bottom-composer smoke pass; named `Tutoring` remained visible after `Off → High`. |
| Normalized effort | **Pass** | Backend enum/provider mapping/schema tests and Flutter fixed-position/unsupported-model widget tests pass. |
| Quality gate | **Pending / E2E incomplete** | `just check`, focused UI/banner suites, full `just test`, clean-diff check, health, and configured login E2E pass. Process launch, history-derived Personal topics, full Threads actions, and committed-turn/live-SSE E2E remain deferred. |

## Implementation wiring audit

- **Compiler path:** `ChatService._stream_assistant_turn` invokes
  `TopicContextCompiler` only for a primary conversation when the feature flag
  is enabled; legacy threads continue through the existing full-history and
  summarization path. Generation metadata carries the compiled snapshot and
  context version.
- **Ingestion/invalidation:** durable create/edit/delete and conversation
  events are ordered, deduplicated, watermarked, and revoke derived message
  evidence before replacement processing. Dedicated request-time tests prove
  deactivated memories, unavailable/deleted knowledge sources, and deleted
  threads cannot cross the compiler boundary.
- **Consolidation:** dirty-user leasing uses conditional ownership/expiry,
  failures set retry backoff, and immutable validated packs promote their
  pointer transactionally; failed validation leaves the prior pack/pointer.
- **SSE schema v1:** dynamic `topic_update`, `context_preparing`, and
  `context_update` events carry schema version 1 metadata before the answer;
  the exact-payload contract test passes.
- **Thinking effort:** backend and Flutter use only normalized
  `off/low/medium/high`; provider-native values are not exposed in public
  model responses and unsupported UI positions are disabled.
- **Navigation/UI:** sidebar exposes Topics, Threads, and Rooms only; no
  Activity endpoint or tab was found. Active context has pinned/selected
  sections and “why included” controls. English and Spanish localization keys
  are in parity.

## Required follow-up

1. Add history-derived Personal-topic, full Threads-action, and device-level
   committed-turn live-SSE E2E before changing the remaining Pending rows to
   Pass.
