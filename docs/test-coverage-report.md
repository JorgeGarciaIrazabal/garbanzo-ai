# Test Suite Review & Coverage Report

*Generated 2026-07-12. Snapshot: ~50 backend test files (~450 test functions, ~9,200 lines), 30 Flutter test files (~4,000 lines), no committed integration tests.*

> **Status update (2026-07-19).** Most of the plan below has landed. Backend
> P1/P2 endpoint gaps are covered (`test_chat_message_actions_endpoints.py`,
> `test_chat_sse_endpoint.py`, `test_room_attachments.py`,
> `test_rooms_endpoints.py`, `test_conversation_pagination_endpoints.py`).
> Frontend: `chat_provider_actions_test.dart`, `memory_provider_test.dart`,
> `notification_provider_test.dart`, `room_socket_service_test.dart`, plus new
> `knowledge_base_provider_test.dart`, `model_provider_test.dart`,
> `search_provider_test.dart`, `usage_provider_test.dart`. The
> `conversation_list_mutation_test.dart` deletion and the dead
> `fe-integration-test` recipe are both done. **Remaining:** `audio_service`
> (thin `ApiClient.instance` wrapper — needs an injection point to unit-test;
> backend side already covered), and the Part 1 `test_schemas.py` trim.

## TL;DR

The suite is **strong at the service layer and weak at the user-story layer**. Very few tests deserve deletion — the real problem is that several core user flows (regenerate / edit / branch a message, room file attachments, whole frontend features like Memory, Knowledge Base, Notifications, Search) have **zero coverage**. Recommendation: trim ~350 lines of framework-testing noise, and invest in the P1/P2 gaps below.

---

## Part 1 — Tests that are not needed (or barely)

### Backend

| File | Verdict | Detail |
|------|---------|--------|
| `test_schemas.py` (309 lines, 42 tests) | **Trim ~80%** | Most tests assert Pydantic framework behavior: field assignment (`req.email == "user@example.com"`), default values, `ge/le` bounds. These can't fail unless Pydantic itself breaks. **Keep** the genuine regressions: `test_accepts_tool_roles` (documented 500-error regression), `test_password_exceeds_72_bytes` (bcrypt limit), `test_invalid_role` / `test_invalid_type` literal guards. |
| `test_scheduled_action_schemas.py` (9 tests) | **Review** | Same category. Keep anything exercising custom validators (cron expression validation); drop plain field-assignment assertions. |

Everything else backend-side earns its keep — service tests hit real logic (soft delete, user isolation, pagination, tool loop, context budgets).

### Frontend

| File | Verdict | Detail |
|------|---------|--------|
| `test/conversation_list_mutation_test.dart` (27 lines) | **Delete** | Tests that `removeWhere` on an unmodifiable Dart list throws and `where().toList()` doesn't. This tests the Dart SDK, not app code. If it was pinning a past bug, the fix belongs in a `ConversationListController` test instead. |
| `test/models/*.dart` (~580 lines: `model_info`, `usage_summary`, `chat_message`, `conversation`, `chat_attachment`) | **Trim ~50%** | These test freezed/json_serializable **generated** code. The `fromJson` cases that pin snake_case wire-contract mapping (`context_length` → `contextLength`) are cheap and useful — keep one parse test per model. Drop "handles null optional fields", equality, and copyWith-style cases: generated code, zero signal. |
| `test/core/auth_result_test.dart` (24 lines) | **Review** | Tiny; likely trivial data-class assertions. Keep only if it pins behavior a refactor could break. |

**Estimated cleanup: ~350–450 lines removed, zero loss of real coverage.**

### Broken/dead test infrastructure

- `just fe-integration-test` runs `flutter test integration_test/app_test.dart -d linux`, but **`integration_test/` does not exist** in the repo. The recipe (and `fe-test-all`, which depends on it) fails today. Either restore the suite or remove the recipe. CLAUDE.md also documents it as if it exists.

---

## Part 2 — User-story coverage gaps (the important part)

### P1 — Core flows with zero tests

1. **Chat message actions (backend)** — no test anywhere touches:
   - `POST /chat/conversations/{id}/messages/{mid}/regenerate`
   - `POST /chat/conversations/{id}/messages/{mid}/edit` — including the critical "truncates all later messages" contract
   - `POST /chat/conversations/{id}/messages/{mid}/branch` — new conversation from a message
   - `DELETE /chat/conversations/{id}/chat` (cancel) is tested only at service level (`TestCancelStream`), not the endpoint.

   These are headline user stories in the chat UI. Suggested tests: happy path, wrong-user 404, edit-truncation verified via message list, branch copies history up to the branch point.

2. **Chat message actions (frontend)** — `ChatProvider` has `regenerateLastAssistant()`, `editUserMessage()`, `branchFromMessage()`, `togglePin()`, `addAttachments()`/`clearPendingAttachments()`, and the `sendMessage()` happy/error paths — **none tested**. `chat_provider_streaming_test.dart` covers only chunk accumulation, stop, undo-delete, tool-execution updates, and throttling. Suggested: extend the existing fake-service harness in that file to cover each action (optimistic updates, state after error, pending-attachment lifecycle).

3. **Room file attachments (just shipped, commit `f98430b`)** — 57 new lines in `room_chat_service.py` plus schema/WS changes and the whole frontend path (`room_provider`, `room_socket_service`, `room_chat_view`, `room_message_bubble`) landed with **zero tests**. Backend: attachment accepted via WS + REST, injected into agent context, persisted on `RoomMessage`. Frontend: attachment payload serialization in `room_socket_service_test.dart` (harness already exists via `fake_room_channel.dart`).

### P2 — Features/endpoints with no coverage

4. **Rooms REST endpoints** — `test_rooms_service.py` covers the service, but there are no HTTP-level tests: room CRUD, member add/remove, agent CRUD, **`GET /rooms/{id}/export` (untested anywhere)**, and authorization (non-member accessing a room → 403/404).
5. **SSE chat endpoint contract** — `test_chat_tool_loop.py` (591 lines) thoroughly tests the service loop, but no test exercises `POST /chat/conversations/{id}/chat` over HTTP: SSE framing (`data: {...}\n\n`), chunk/done/error event types, auth. One endpoint test with a stubbed provider would pin the wire contract both the Flutter `sse_parser` and push-notification-on-disconnect logic depend on.
6. **Conversation pinning** — `is_pinned` has no backend coverage (PATCH toggling, sidebar ordering) and no frontend coverage (`togglePin`).
7. **`GET /mcp/tools` endpoint** — service tested (`test_mcp_service.py`), endpoint not.
8. **Frontend features with zero test files:**
   - **Memory** (`MemoryProvider`, MemoryPage CRUD, memory toggle in chat)
   - **Knowledge Base** (`KnowledgeBaseProvider`, upload/search service)
   - **Notifications** (`NotificationProvider`, unread count, mark-read, `push_service`)
   - **Search** (`SearchProvider`, `search_service`) — backend search is well tested; the UI story isn't
   - **ModelProvider** — model selection surviving conversation switches is a documented design point, untested
   - **UsageProvider** (only the JSON model is tested)
   - **`audio_service.dart`** (STT/TTS client flows; backend `test_audio_endpoints.py` is solid)

   Highest value first: Memory and Notifications (user-facing CRUD with error states), then KB, Search, ModelProvider.

### P3 — Hygiene

9. Restore or delete the `fe-integration-test` recipe; if E2E stays manual via the `/e2e-testing` skill, say so in CLAUDE.md and drop the dead just recipes.
10. Current uncommitted WIP (`attach_menu_button.dart`, `file_picker_helper.dart`, `chat_input_widget.dart`) will need tests when it lands — the attach-menu flow currently has none. (Left out of scope here since it's in-progress work.)

---

## Suggested execution order

| # | Task | Layer | Status |
|---|------|-------|--------|
| 1 | Endpoint tests for regenerate / edit / branch / cancel | Backend | ✅ done |
| 2 | ChatProvider action tests (send/edit/regen/branch/pin/attachments) | Frontend | ✅ done |
| 3 | Room attachment tests (service + WS + socket serialization) | Both | ✅ done |
| 4 | Rooms REST endpoint tests incl. export + authz | Backend | ✅ done |
| 5 | SSE endpoint contract test | Backend | ✅ done |
| 6 | MemoryProvider + NotificationProvider tests | Frontend | ✅ done |
| 6b | KnowledgeBase / Model / Search / Usage provider tests | Frontend | ✅ done |
| 7 | Trim `test_schemas.py`, prune model roundtrip tests (`conversation_list_mutation_test.dart` already deleted) | Both | ⬜ remaining |
| 8 | Fix/remove `fe-integration-test` recipe | Infra | ✅ done |
