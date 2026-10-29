# Rooms Feature — Agent Context

Scoped guide for `lib/features/rooms/`. Read alongside `lib/AGENTS.md`.

## Architecture & Invariants

1. **Hosted Inside `ChatPage` (No Standalone Page):** `/rooms/:roomId` renders
   `ChatPage(roomId: id)`, which keeps `ChatSidebar` mounted and swaps the main
   content pane to `RoomChatView` (`widgets/room_chat_view.dart`). While
   `roomId != null`, `ChatPage` suspends conversation→URL auto-sync so background
   chat updates never yank the route away from `/rooms/:roomId`.
2. **WebSocket + Per-Agent Stream Coalescing (`RoomProvider`):**
   - `RoomProvider` (`providers/room_provider.dart`) connects via
     `RoomSocketService` (`services/room_socket_service.dart`) and mixes in
     `GuardedStateMixin` for REST room/member/agent CRUD (`RoomService`).
   - Multiple agents can stream concurrently in a room. Each active agent turn
     allocates its own `ThrottledMessageNotifier<RoomMessage>` in
     `_streamingNotifiers[messageId]` (80ms coalescing window) exposed via
     `streamingNotifierFor(messageId)` so token chunks repaint only that agent's
     bubble (`RoomMessageBubble`), not the room transcript.
   - Always call `_disposeStreamingNotifiers()` when switching rooms, leaving a
     room, or disposing `RoomProvider`.
3. **Shared Chat Primitives:** `RoomChatView` and `RoomMessageBubble` intentionally
   reuse composer and message building blocks from `features/chat/widgets/input/`
   and `features/chat/widgets/message/` (explicitly allowlisted in
   `scripts/fe_lint_arch.py`). Keep those sub-widgets free of `ChatProvider`
   assumptions when editing them so they work identically in rooms.

## Focused Verification

```bash
just fe-test test/rooms/room_provider_test.dart
just fe-test test/rooms/room_socket_service_test.dart
just fe-test test/rooms/add_agent_dialog_test.dart
just fe-test test/rooms/room_connection_banner_test.dart
just fe-test test/rooms/room_mute_test.dart
```
