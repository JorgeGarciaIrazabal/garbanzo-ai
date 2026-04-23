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
  ChatProvider({required String? Function() selectedModelId})
      : _selectedModelId = selectedModelId {
    _loadConversations();
  }

  final ChatService _chatService = ChatService.instance;
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
    _error = null;
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

  Future<void> deleteConversation(String conversationId) async {
    _error = null;

    try {
      await _chatService.deleteConversation(conversationId);

      if (_currentConversation?.id == conversationId) {
        _currentConversation = null;
        _messages = [];
      }

      // Replace with a fresh list — `list.items` from the API is unmodifiable.
      _conversations =
          _conversations.where((c) => c.id != conversationId).toList();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to delete conversation: $e';
      if (kDebugMode) print(_error);
      notifyListeners();
    }
  }

  void clearCurrentConversation() {
    _currentConversation = null;
    _messages = [];
    _error = null;
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

    // Single assistant placeholder, anchored at the END of the message list
    // throughout the stream. Tool calls / tool results get inserted BEFORE
    // it as they arrive, mirroring the canonical layout the server sends
    // back on reload — so there's no jarring "two placeholders merge into
    // one" jolt when the stream finishes. Thinking from tool-calling
    // iterations accumulates onto the same placeholder; the backend
    // persists it the same way.
    _upsertAssistantMessage(
      assistantMessageId,
      accumulatedContent,
      accumulatedThinking,
      null,
    );
    notifyListeners();

    _streamSubscription = stream.listen(
      (chunk) {
        if (chunk.isThinking && chunk.content != null) {
          accumulatedThinking += chunk.content!;
          _upsertAssistantMessage(
            assistantMessageId,
            accumulatedContent,
            accumulatedThinking,
            null,
          );
          notifyListeners();
        } else if (chunk.isChunk && chunk.content != null) {
          accumulatedContent += chunk.content!;
          _upsertAssistantMessage(
            assistantMessageId,
            accumulatedContent,
            accumulatedThinking,
            null,
          );
          notifyListeners();
        } else if (chunk.isToolCall) {
          _insertToolCallMessagesBefore(
            assistantMessageId,
            chunk.toolCalls ?? const [],
          );
          notifyListeners();
        } else if (chunk.isToolResult) {
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
            _upsertAssistantMessage(
              assistantMessageId,
              accumulatedContent,
              accumulatedThinking,
              chunk.metadata,
            );
            notifyListeners();
          }
        } else if (chunk.isError) {
          _error = chunk.error ?? 'An error occurred';
          _isSending = false;
          notifyListeners();
        }
      },
      onError: (e) {
        _error = 'Streaming error: $e';
        _isSending = false;
        if (kDebugMode) print('Stream error: $e');
        notifyListeners();
      },
      onDone: () {
        // Real end of the SSE stream — finalize and reconcile with server.
        _isSending = false;
        _streamSubscription = null;
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
    notifyListeners();

    if (_currentConversation != null) {
      try {
        await _chatService.stopStreaming(_currentConversation!.id);
      } catch (e) {
        if (kDebugMode) print('Failed to stop streaming on backend: $e');
      }
    }
  }

  void _upsertAssistantMessage(
    String id,
    String content,
    String thinking,
    Map<String, dynamic>? doneMetadata,
  ) {
    final meta = <String, dynamic>{
      if (thinking.isNotEmpty) 'thinking': thinking,
      if (doneMetadata != null) ...doneMetadata,
    };

    final assistantMessage = ChatMessage(
      id: id,
      role: 'assistant',
      content: content,
      createdAt: DateTime.now(),
      metadata: meta.isEmpty ? null : meta,
    );

    final existingIndex = _messages.indexWhere((m) => m.id == id);
    if (existingIndex >= 0) {
      final newMessages = List<ChatMessage>.from(_messages);
      newMessages[existingIndex] = assistantMessage;
      _messages = newMessages;
    } else {
      _messages = [..._messages, assistantMessage];
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

  Future<void> _reloadCurrentConversation() async {
    if (_currentConversation == null) return;
    try {
      await loadConversation(_currentConversation!.id);
    } catch (e) {
      if (kDebugMode) print('Failed to reload conversation: $e');
    }
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
    super.dispose();
  }
}
