import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_attachment.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/chat_service.dart';

const _uuid = Uuid();

/// Provider for managing chat conversation and message state.
///
/// Model selection is handled by [ModelProvider]. This provider reads the
/// currently-selected model from its [selectedModelId] callback so the two
/// stay decoupled.
class ChatProvider extends ChangeNotifier {
  ChatProvider({
    required String? Function() selectedModelId,
    ChatService? chatService,
  })  : _selectedModelId = selectedModelId,
        _chatService = chatService ?? ChatService.instance {
    _loadConversations();
  }

  final ChatService _chatService;
  final String? Function() _selectedModelId;

  // ==========================================================================
  // State
  // ==========================================================================

  Conversation? _currentConversation;
  Conversation? get currentConversation => _currentConversation;

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool _isSending = false;
  bool get isSending => _isSending;

  List<Conversation> _conversations = [];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  bool _isLoadingConversations = false;
  bool get isLoadingConversations => _isLoadingConversations;

  String? _error;
  String? get error => _error;

  StreamSubscription<ChatResponseChunk>? _streamSubscription;

  // ==========================================================================
  // Streaming message channel
  // ==========================================================================
  //
  // Per-chunk content updates go through this ValueNotifier instead of
  // notifyListeners(), so only the streaming bubble rebuilds — not the whole
  // message list (which would also re-parse every visible message's
  // markdown). The list itself only changes on structural events: stream
  // start, tool calls/results, per-iteration done, and end of stream.

  /// Live view of the assistant message currently being streamed.
  final ValueNotifier<ChatMessage?> streamingMessage = ValueNotifier(null);

  /// ID of the in-flight assistant placeholder, if a stream is active.
  String? get streamingMessageId => _streamingMessageId;
  String? _streamingMessageId;

  // Notifier pushes are throttled: token chunks can arrive 50–100×/s and
  // each push re-parses the growing message's markdown. ~12 updates/s is
  // visually indistinguishable for streaming text at a fraction of the cost.
  static const _streamPushInterval = Duration(milliseconds: 80);
  DateTime _lastStreamPush = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _streamFlushTimer;
  ChatMessage? _pendingStreamMessage;

  void _pushStreamingUpdate(ChatMessage message, {bool force = false}) {
    _pendingStreamMessage = message;
    final now = DateTime.now();
    if (force || now.difference(_lastStreamPush) >= _streamPushInterval) {
      _streamFlushTimer?.cancel();
      _streamFlushTimer = null;
      _lastStreamPush = now;
      streamingMessage.value = message;
    } else {
      _streamFlushTimer ??= Timer(_streamPushInterval, () {
        _streamFlushTimer = null;
        _lastStreamPush = DateTime.now();
        final pending = _pendingStreamMessage;
        if (pending != null && pending.id == _streamingMessageId) {
          streamingMessage.value = pending;
        }
      });
    }
  }

  /// Commit the latest streamed content into [_messages] before a structural
  /// change (tool insert, stop, end of stream), so list state never lags
  /// behind what the user already saw in the live bubble.
  void _syncStreamingIntoList() {
    final pending = _pendingStreamMessage ?? streamingMessage.value;
    if (pending != null && pending.id == _streamingMessageId) {
      _upsertIntoList(pending);
    }
  }

  void _clearStreamingState() {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    _pendingStreamMessage = null;
    _streamingMessageId = null;
    streamingMessage.value = null;
  }

  // ==========================================================================
  // Conversations
  // ==========================================================================

  Future<void> _loadConversations() async {
    _isLoadingConversations = true;
    _error = null;
    notifyListeners();

    try {
      final list = await _chatService.listConversations();
      _conversations = list.items;
    } catch (e) {
      _error = 'Failed to load conversations: $e';
      if (kDebugMode) print(_error);
    } finally {
      _isLoadingConversations = false;
      notifyListeners();
    }
  }

  Future<void> refreshConversations() async => _loadConversations();

  Future<void> loadConversation(String conversationId) async {
    // Switching away mid-stream: stop the old stream so its chunks can't
    // bleed into the newly loaded conversation's message list.
    if (_streamSubscription != null &&
        _currentConversation?.id != conversationId) {
      await stopStreaming();
    }

    _error = null;
    _actionEpoch++;
    notifyListeners();

    try {
      final conversation = await _chatService.getConversation(conversationId);
      _currentConversation = conversation;
      _messages = _hydrateAttachments(conversation.messages ?? []);
    } catch (e) {
      _error = 'Failed to load conversation: $e';
      if (kDebugMode) print(_error);
    } finally {
      notifyListeners();
    }
  }

  Future<void> createConversation({
    String? title,
    String? model,
    String? initialMessage,
    String? systemPrompt,
    List<ChatAttachment> initialAttachments = const [],
  }) async {
    _error = null;
    notifyListeners();

    try {
      final selectedModel = model ?? _selectedModelId() ?? 'llama3.2';
      final derivedTitle = title ??
          (initialMessage != null && initialMessage.isNotEmpty
              ? initialMessage.substring(
                  0, initialMessage.length > 50 ? 50 : initialMessage.length)
              : null);
      final conversation = await _chatService.createConversation(
        title: derivedTitle,
        model: selectedModel,
        systemPrompt: systemPrompt,
      );

      _currentConversation = conversation;
      _messages = [];

      // Immediately add the new conversation to the list for sidebar visibility
      _conversations = [
        conversation.copyWith(messageCount: 0),
        ..._conversations,
      ];
      notifyListeners();

      if (initialMessage != null && initialMessage.isNotEmpty) {
        await sendMessage(initialMessage, attachments: initialAttachments);
      } else {
        notifyListeners();
      }

      await _loadConversations();
    } catch (e) {
      _error = 'Failed to create conversation: $e';
      _isSending = false;
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }

  Future<void> updateConversation({
    String? title,
    String? model,
    bool? useMemory,
    bool? useKnowledgeBase,
    String? systemPrompt,
    bool clearSystemPrompt = false,
    List<String>? enabledTools,
    bool clearEnabledTools = false,
    bool? isPinned,
  }) async {
    if (_currentConversation == null) return;

    _error = null;
    notifyListeners();

    try {
      final updated = await _chatService.updateConversation(
        _currentConversation!.id,
        title: title,
        model: model,
        useMemory: useMemory,
        useKnowledgeBase: useKnowledgeBase,
        systemPrompt: systemPrompt,
        clearSystemPrompt: clearSystemPrompt,
        enabledTools: enabledTools,
        clearEnabledTools: clearEnabledTools,
        isPinned: isPinned,
      );
      _currentConversation = updated;
      await _loadConversations();
    } catch (e) {
      _error = 'Failed to update conversation: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }

  Future<void> togglePin(String conversationId) async {
    _error = null;
    try {
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx < 0) return;
      final conv = _conversations[idx];
      final updated = await _chatService.updateConversation(
        conversationId,
        isPinned: !conv.isPinned,
      );
      if (_currentConversation?.id == conversationId) {
        _currentConversation = updated;
      }
      await _loadConversations();
    } catch (e) {
      _error = 'Failed to pin conversation: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }

  // Deletion is optimistic with an undo window: the conversation leaves the
  // UI immediately, but the API call fires only after the window expires.
  // Undo within the window cancels the deletion entirely.
  static const _undoWindow = Duration(seconds: 6);
  final Map<String, ({Conversation conversation, int index, Timer timer})>
      _pendingDeletes = {};

  Future<void> deleteConversation(String conversationId) async {
    _error = null;
    _actionEpoch++;

    final index = _conversations.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;
    final conversation = _conversations[index];

    if (_currentConversation?.id == conversationId) {
      _currentConversation = null;
      _messages = [];
    }
    _conversations =
        _conversations.where((c) => c.id != conversationId).toList();
    notifyListeners();

    _pendingDeletes.remove(conversationId)?.timer.cancel();
    _pendingDeletes[conversationId] = (
      conversation: conversation,
      index: index,
      timer: Timer(_undoWindow, () => _commitDelete(conversationId)),
    );
  }

  /// Restore a conversation deleted within the undo window.
  void undoDeleteConversation(String conversationId) {
    final pending = _pendingDeletes.remove(conversationId);
    if (pending == null) return;
    pending.timer.cancel();
    _restoreConversation(pending.conversation, pending.index);
  }

  Future<void> _commitDelete(String conversationId) async {
    final pending = _pendingDeletes.remove(conversationId);
    if (pending == null) return;
    try {
      await _chatService.deleteConversation(conversationId);
    } catch (e) {
      // Server-side deletion failed — bring the conversation back.
      _restoreConversation(pending.conversation, pending.index);
      _error = 'Failed to delete conversation: $e';
      if (kDebugMode) print(_error);
    }
  }

  void _restoreConversation(Conversation conversation, int index) {
    final list = List<Conversation>.from(_conversations);
    list.insert(index.clamp(0, list.length), conversation);
    _conversations = list;
    notifyListeners();
  }

  void clearCurrentConversation() {
    if (_streamSubscription != null) {
      unawaited(stopStreaming());
    }
    _currentConversation = null;
    _messages = [];
    _error = null;
    _actionEpoch++;
    notifyListeners();
  }

  bool get hasActiveConversation => _currentConversation != null;

  /// Add attachments to the current message being composed.
  /// Called when files are dragged onto the chat area.
  void addAttachments(List<ChatAttachment> attachments) {
    // For now, we just store them in a temporary holder.
    // The attachments will be sent with the next message.
    // This mirrors the file picker behavior in ChatInputWidget.
    _pendingAttachments ??= [];
    _pendingAttachments!.addAll(attachments);
    notifyListeners();
  }

  List<ChatAttachment>? _pendingAttachments;
  List<ChatAttachment>? get pendingAttachments => _pendingAttachments;

  void clearPendingAttachments() {
    _pendingAttachments = null;
    notifyListeners();
  }

  // ==========================================================================
  // Helpers
  // ==========================================================================

  /// Updates the current conversation's entry in the conversations list.
  void _updateConversationInList() {
    if (_currentConversation == null) return;
    final index = _conversations.indexWhere(
      (c) => c.id == _currentConversation!.id,
    );
    if (index >= 0) {
      _conversations = [
        ..._conversations.sublist(0, index),
        _currentConversation!,
        ..._conversations.sublist(index + 1),
      ];
      notifyListeners();
    }
  }

  // ==========================================================================
  // Messaging
  // ==========================================================================

  Future<void> sendMessage(
    String content, {
    List<ChatAttachment> attachments = const [],
  }) async {
    if (content.trim().isEmpty && attachments.isEmpty) return;

    // Guard: prevent sending while already streaming.
    if (_isSending) return;

    _error = null;
    _actionEpoch++;

    if (_currentConversation == null) {
      await createConversation(
        model: _selectedModelId() ?? 'llama3.2',
        initialMessage: content,
        initialAttachments: attachments,
      );
      return;
    }

    _isSending = true;

    final userMessage = ChatMessage(
      id: 'temp-${_uuid.v4()}',
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
      attachments: attachments,
    );
    _messages = [..._messages, userMessage];

    // Update current conversation with new message count for sidebar
    if (_currentConversation != null) {
      _currentConversation = _currentConversation!.copyWith(
        messageCount: _messages.length,
      );
      _updateConversationInList();
    }
    notifyListeners();

    try {
      final stream = _chatService.streamChatResponse(
        _currentConversation!.id,
        content,
        attachments: attachments,
      );
      _consumeAssistantStream(stream);
    } catch (e) {
      _error = 'Failed to send message: $e';
      _isSending = false;
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }

  /// Regenerate the last assistant reply in the current conversation.
  Future<void> regenerateLastAssistant() async {
    if (_currentConversation == null || _isSending) return;

    final lastAssistantIdx =
        _messages.lastIndexWhere((m) => m.isAssistant && !m.id.startsWith('temp-'));
    if (lastAssistantIdx < 0) return;
    final messageId = _messages[lastAssistantIdx].id;

    _error = null;
    _actionEpoch++;
    _isSending = true;
    // Trim the old assistant reply and any trailing tool turns we've already
    // rendered locally; the backend does the same deletion for us.
    _messages = _messages.sublist(0, lastAssistantIdx);
    notifyListeners();

    try {
      final stream = _chatService.regenerateMessage(
        _currentConversation!.id,
        messageId,
      );
      _consumeAssistantStream(stream);
    } catch (e) {
      _error = 'Failed to regenerate: $e';
      _isSending = false;
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }

  /// Edit a user message's text and re-run the conversation from that point.
  Future<void> editUserMessage(String messageId, String newContent) async {
    if (_currentConversation == null || _isSending) return;
    if (newContent.trim().isEmpty) return;

    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final target = _messages[idx];
    if (!target.isUser) return;

    _error = null;
    _actionEpoch++;
    _isSending = true;

    // Optimistically update the message text and drop everything after it.
    final edited = target.copyWith(content: newContent);
    _messages = [..._messages.sublist(0, idx), edited];
    notifyListeners();

    try {
      final stream = _chatService.editMessage(
        _currentConversation!.id,
        messageId,
        newContent,
      );
      _consumeAssistantStream(stream);
    } catch (e) {
      _error = 'Failed to edit message: $e';
      _isSending = false;
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }

  /// Fork the conversation from a specific message into a new branch.
  Future<void> branchFromMessage(String messageId) async {
    if (_currentConversation == null) return;

    _error = null;
    notifyListeners();

    try {
      final newConv = await _chatService.branchConversation(
        _currentConversation!.id,
        messageId,
      );
      // Prepend to sidebar list
      _conversations = [newConv, ..._conversations];
      // Navigate to new branch
      await loadConversation(newConv.id);
    } catch (e) {
      _error = 'Failed to branch conversation: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }

  void _consumeAssistantStream(Stream<ChatResponseChunk> stream) {
    final assistantMessageId = 'temp-${_uuid.v4()}';
    var accumulatedContent = '';
    var accumulatedThinking = '';

    ChatMessage current([Map<String, dynamic>? doneMetadata]) =>
        _buildAssistantMessage(
          assistantMessageId,
          accumulatedContent,
          accumulatedThinking,
          doneMetadata,
        );

    // Single assistant placeholder, anchored at the END of the message list
    // throughout the stream. Tool calls / tool results get inserted BEFORE
    // it as they arrive, mirroring the canonical layout the server sends
    // back on reload — so there's no jarring "two placeholders merge into
    // one" jolt when the stream finishes. Thinking from tool-calling
    // iterations accumulates onto the same placeholder; the backend
    // persists it the same way.
    //
    // Per-chunk content flows through [streamingMessage] only; the list
    // (and notifyListeners) is reserved for structural changes.
    _upsertIntoList(current());
    _streamingMessageId = assistantMessageId;
    _pushStreamingUpdate(current(), force: true);
    notifyListeners();

    _streamSubscription = stream.listen(
      (chunk) {
        if (chunk.isThinking && chunk.content != null) {
          accumulatedThinking += chunk.content!;
          _pushStreamingUpdate(current());
        } else if (chunk.isChunk && chunk.content != null) {
          accumulatedContent += chunk.content!;
          _pushStreamingUpdate(current());
        } else if (chunk.isToolCall) {
          _syncStreamingIntoList();
          _insertToolCallMessagesBefore(
            assistantMessageId,
            chunk.toolCalls ?? const [],
          );
          notifyListeners();
        } else if (chunk.isToolResult) {
          _syncStreamingIntoList();
          _insertToolResultMessageBefore(
            assistantMessageId,
            chunk.toolResult,
          );
          notifyListeners();
        } else if (chunk.isDone) {
          // The backend emits a `done` chunk PER LLM ITERATION (one for the
          // tool-call iteration, one for the final-answer iteration). It is
          // NOT the end-of-stream marker — that's the SSE stream's own
          // onDone callback. So here we only commit metadata to whatever
          // assistant message has been accumulating; we do NOT flip
          // _isSending or reload (a reload mid-stream would replace
          // _messages with the partial server state and erase everything we
          // just streamed).
          if (accumulatedContent.isNotEmpty ||
              accumulatedThinking.isNotEmpty) {
            final committed = current(chunk.metadata);
            _upsertIntoList(committed);
            _pushStreamingUpdate(committed, force: true);
            notifyListeners();
          }
        } else if (chunk.isError) {
          _syncStreamingIntoList();
          _error = chunk.error ?? 'An error occurred';
          _isSending = false;
          notifyListeners();
        }
      },
      onError: (e) {
        _syncStreamingIntoList();
        _error = 'Streaming error: $e';
        _isSending = false;
        if (kDebugMode) print('Stream error: $e');
        _clearStreamingState();
        notifyListeners();
      },
      onDone: () {
        // Real end of the SSE stream — finalize and reconcile with server.
        _isSending = false;
        _streamSubscription = null;
        _syncStreamingIntoList();
        _clearStreamingState();
        if (accumulatedContent.isEmpty && accumulatedThinking.isEmpty) {
          // Drop the trailing empty placeholder if iteration N+1 never
          // produced anything (e.g., turn ended right after a tool call).
          _removeMessage(assistantMessageId);
        }
        if (_currentConversation != null) {
          _currentConversation = _currentConversation!.copyWith(
            messageCount: _messages.length,
          );
          _updateConversationInList();
        }
        notifyListeners();
        _reloadCurrentConversation();
        _scheduleTitleRefresh();
      },
    );
  }

  void _removeMessage(String id) {
    final filtered = _messages.where((m) => m.id != id).toList();
    if (filtered.length != _messages.length) {
      _messages = filtered;
    }
  }

  Future<void> stopStreaming() async {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _isSending = false;
    _actionEpoch++;
    // Keep what was already streamed, marked as interrupted so the partial
    // answer isn't mistaken for a complete one.
    final pending = _pendingStreamMessage ?? streamingMessage.value;
    if (pending != null && pending.id == _streamingMessageId) {
      _upsertIntoList(pending.copyWith(
        metadata: {...?pending.metadata, 'stopped': true},
      ));
    }
    _clearStreamingState();
    notifyListeners();

    if (_currentConversation != null) {
      try {
        await _chatService.stopStreaming(_currentConversation!.id);
      } catch (e) {
        if (kDebugMode) print('Failed to stop streaming on backend: $e');
      }
    }
  }

  ChatMessage _buildAssistantMessage(
    String id,
    String content,
    String thinking,
    Map<String, dynamic>? doneMetadata,
  ) {
    final meta = <String, dynamic>{
      if (thinking.isNotEmpty) 'thinking': thinking,
      if (doneMetadata != null) ...doneMetadata,
    };

    return ChatMessage(
      id: id,
      role: 'assistant',
      content: content,
      createdAt: DateTime.now(),
      metadata: meta.isEmpty ? null : meta,
    );
  }

  void _upsertIntoList(ChatMessage message) {
    final existingIndex = _messages.indexWhere((m) => m.id == message.id);
    if (existingIndex >= 0) {
      final newMessages = List<ChatMessage>.from(_messages);
      newMessages[existingIndex] = message;
      _messages = newMessages;
    } else {
      _messages = [..._messages, message];
    }
  }

  /// Inserts display-only `tool_call` messages for each call streamed,
  /// placed immediately BEFORE the assistant placeholder so the placeholder
  /// stays anchored at the end of the conversation.
  void _insertToolCallMessagesBefore(
      String anchorId, List<ToolCall> calls) {
    if (calls.isEmpty) return;
    final additions = <ChatMessage>[];
    for (final call in calls) {
      additions.add(
        ChatMessage(
          id: 'temp-tool-call-${call.id}',
          role: 'tool_call',
          content: call.name,
          createdAt: DateTime.now(),
          metadata: {
            'tool_calls': [
              {
                'id': call.id,
                'name': call.name,
                'arguments': call.arguments ?? const {},
              }
            ],
          },
        ),
      );
    }
    final idx = _messages.indexWhere((m) => m.id == anchorId);
    if (idx < 0) {
      _messages = [..._messages, ...additions];
      return;
    }
    _messages = [
      ..._messages.sublist(0, idx),
      ...additions,
      ..._messages.sublist(idx),
    ];
  }

  /// Inserts a display-only `tool_result` message immediately BEFORE the
  /// assistant placeholder, mirroring the canonical layout the server
  /// returns on reload.
  void _insertToolResultMessageBefore(
      String anchorId, ToolResult? result) {
    if (result == null) return;
    final newMsg = ChatMessage(
      id: 'temp-tool-result-${result.toolCallId}',
      role: 'tool_result',
      content: result.toolName,
      createdAt: DateTime.now(),
      metadata: {
        'tool_result': {
          'tool_call_id': result.toolCallId,
          'tool_name': result.toolName,
          'result': result.result,
        },
      },
    );
    final idx = _messages.indexWhere((m) => m.id == anchorId);
    if (idx < 0) {
      _messages = [..._messages, newMsg];
      return;
    }
    _messages = [
      ..._messages.sublist(0, idx),
      newMsg,
      ..._messages.sublist(idx),
    ];
  }

  /// Bumped on every user action that changes message state (send, edit,
  /// regenerate, stop, switch). In-flight reloads compare epochs and drop
  /// their result if a newer action happened — otherwise the post-stream
  /// server reload could clobber an optimistic edit made while it was
  /// in flight.
  int _actionEpoch = 0;

  Future<void> _reloadCurrentConversation() async {
    final id = _currentConversation?.id;
    if (id == null) return;
    final epoch = _actionEpoch;
    try {
      final conversation = await _chatService.getConversation(id);
      if (epoch != _actionEpoch || _currentConversation?.id != id) {
        return; // stale — a newer action owns the state now
      }
      _currentConversation = conversation;
      _messages = _hydrateAttachments(conversation.messages ?? []);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Failed to reload conversation: $e');
    }
  }

  // The backend auto-titles a conversation in the background after its
  // first exchange; refresh shortly after the stream ends so the generated
  // title replaces the raw-first-message placeholder in the sidebar.
  Timer? _titleRefreshTimer;

  void _scheduleTitleRefresh() {
    _titleRefreshTimer?.cancel();
    _titleRefreshTimer = Timer(const Duration(seconds: 4), () async {
      if (_isSending) return;
      await _loadConversations();
      final id = _currentConversation?.id;
      if (id == null) return;
      final idx = _conversations.indexWhere((c) => c.id == id);
      if (idx >= 0 &&
          _conversations[idx].title != _currentConversation!.title) {
        _currentConversation = _currentConversation!.copyWith(
          title: _conversations[idx].title,
        );
        notifyListeners();
      }
    });
  }

  // ==========================================================================
  // Attachment hydration
  // ==========================================================================

  /// Restore [ChatAttachment] objects from the metadata stored by the backend.
  List<ChatMessage> _hydrateAttachments(List<ChatMessage> messages) {
    return messages.map((msg) {
      final raw = msg.metadata?['attachments'];
      if (raw is! List || raw.isEmpty) return msg;

      final attachments = raw
          .whereType<Map<String, dynamic>>()
          .map((a) => ChatAttachment.fromMetadata(a))
          .toList();

      return msg.copyWith(attachments: attachments);
    }).toList();
  }

  // ==========================================================================
  // Error handling
  // ==========================================================================

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ==========================================================================
  // Cleanup
  // ==========================================================================

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _streamFlushTimer?.cancel();
    _titleRefreshTimer?.cancel();
    // Flush pending deletions so an undo-window deletion isn't silently
    // dropped when the provider goes away (e.g. logout).
    for (final entry in _pendingDeletes.entries) {
      entry.value.timer.cancel();
      unawaited(_chatService.deleteConversation(entry.key));
    }
    _pendingDeletes.clear();
    streamingMessage.dispose();
    super.dispose();
  }
}
