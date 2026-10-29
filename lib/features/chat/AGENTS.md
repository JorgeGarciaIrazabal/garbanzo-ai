# Chat Feature — Agent Context

Scoped guide for `lib/features/chat/`. Read alongside `lib/AGENTS.md`.

## Architecture & Collaborators

`ChatProvider` (`providers/chat_provider.dart`) orchestrates conversation state
and delegates specialized concerns to focused controllers:

- `ChatStreamController` (`providers/chat_stream_controller.dart`) — wraps an
  active SSE subscription + `ThrottledMessageNotifier<ChatMessage>` (80ms window)
  so token chunks only rebuild the active bubble listening to
  `chatProvider.streamingMessage`, never the full transcript list.
- `AgentLivenessController` (`providers/agent_liveness_controller.dart`) —
  publishes heartbeat/tool-execution progress on `chatProvider.agentLiveness`
  without rebuilding the transcript.
- `ChatResponseRecoveryController` (`providers/chat_response_recovery.dart`) —
  polls `_reloadCurrentConversation` after a dropped SSE connection or detached
  visual submission (`followServerResponse`) until the durable reply lands.
- `MessageStarController` (`providers/chat_message_list_helpers.dart`) — tracks
  in-flight bookmark PATCHes via `_epoch` so concurrent conversation reloads
  cannot overwrite a newer confirmed star or clobber server message text.
- `ConversationListController` (`providers/conversation_list_controller.dart`) —
  sidebar list, pin, mute, and optimistic delete with 3-second undo window.
- `ClientFolderController` (`providers/client_folder_controller.dart`) — serves
  desktop `client_tool_request` folder reads locally (`dart:io` only; web throws).

## Critical Invariants

1. **Epoch Race Guards (`_actionEpoch` & `_stars.epoch`):** Every user mutation
   (send, edit, regenerate, stop, delete, topic switch, navigation) increments
   `_actionEpoch`. Background reloads (`_reloadCurrentConversation`) capture
   `_actionEpoch` and `_stars.epoch` before awaiting and discard their response
   if either changed mid-flight.
2. **SSE `done` vs Stream `onDone`:** The backend emits a `done` chunk **per LLM
   iteration** (once for tool calls, once for the final answer). Never flip
   `_isSending = false` or reload from the server on `chunk.isDone` — wait for
   the SSE stream's `onDone` callback, calling `_syncStreamingIntoList()` before
   any structural list mutation (tool call/result insertion, error, stop, done).
3. **Single Anchored Assistant Placeholder:** During streaming, one `temp-...`
   assistant placeholder stays at the end of `_messages`; tool calls and tool
   results insert **before** it (`insertMessagesBeforeAnchor`) so layout matches
   the persisted server order with zero visual jump on reload.
4. **Primary Landing vs Regular Thread (`submitChatComposerMessage`):** When
   `currentConversation.isPrimary == true` AND `TopicDiscoveryProvider.showLanding`
   is true, sending a message creates a clean regular thread (`createConversation`)
   instead of appending to the primary conversation's history. Key this strictly
   on `showLanding`, never on `selectedTopic`.
5. **UI Structure (`widgets/`):**
   - `chat_page.dart` — route↔provider URL sync, shell layout, and room host
     (`/rooms/:roomId` swaps the center pane to `RoomChatView`).
   - `chat_transcript_view.dart` — transcript list, tool-group folding
     (excluding `actionProposal` and `visualPresentation` messages), and empty
     states.
   - `chat_drop_zone.dart` — desktop OS `DropTarget`, in-app `DragTarget`, and
     `ResizableMicroAppPane`.
   - `styles/` — decomposed style picker (`style_picker_panel.dart`,
     `style_cards_segment.dart`, `style_customize_controls.dart`,
     `style_editor.dart`, re-exported by `style_picker.dart`).

## Focused Verification

```bash
just fe-test test/chat_provider_streaming_test.dart
just fe-test test/chat_provider_actions_test.dart
just fe-test test/chat_provider_sync_test.dart
just fe-test test/chat/topic_widgets_test.dart
just fe-test test/widgets/style_picker_test.dart
```
