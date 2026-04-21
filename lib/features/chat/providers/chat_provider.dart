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
    String? systemPrompt,
    bool clearSystemPrompt = false,
    List<String>? enabledTools,
    bool clearEnabledTools = false,
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
        systemPrompt: systemPrompt,
        clearSystemPrompt: clearSystemPrompt,
        enabledTools: enabledTools,
        clearEnabledTools: clearEnabledTools,
      );
      _currentConversation = updated;
      await _loadConversations();
    } catch (e) {
      _error = 'Failed to update conversation: $e';
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

      _conversations.removeWhere((c) => c.id == conversationId);
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

    final assistantMessageId = 'temp-${_uuid.v4()}';
    String accumulatedContent = '';
    String accumulatedThinking = '';

    try {
      final stream = _chatService.streamChatResponse(
        _currentConversation!.id,
        content,
        attachments: attachments,
      );

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
            _appendToolCallMessages(chunk.toolCalls ?? const []);
            notifyListeners();
          } else if (chunk.isToolResult) {
            _appendToolResultMessage(chunk.toolResult);
            notifyListeners();
          } else if (chunk.isDone) {
            // Apply final metadata (tokens, timing, etc.) to the message
            _upsertAssistantMessage(
              assistantMessageId,
              accumulatedContent,
              accumulatedThinking,
              chunk.metadata,
            );
            _isSending = false;

            if (_currentConversation != null) {
              _currentConversation = _currentConversation!.copyWith(
                messageCount: _messages.length,
              );
              _updateConversationInList();
            }

            notifyListeners();
            _reloadCurrentConversation();
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
          _isSending = false;
          _streamSubscription = null;
          notifyListeners();
        },
      );
    } catch (e) {
      _error = 'Failed to send message: $e';
      _isSending = false;
      if (kDebugMode) print(_error);
      notifyListeners();
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

  /// Inserts a display-only `tool_call` message for each call streamed.
  /// The backend will persist canonical tool_call messages that replace these
  /// once the stream finishes and the conversation is reloaded.
  void _appendToolCallMessages(List<ToolCall> calls) {
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
    _messages = [..._messages, ...additions];
  }

  /// Inserts a display-only `tool_result` message for the streamed result.
  void _appendToolResultMessage(ToolResult? result) {
    if (result == null) return;
    final summary = result.toolName;
    _messages = [
      ..._messages,
      ChatMessage(
        id: 'temp-tool-result-${result.toolCallId}',
        role: 'tool_result',
        content: summary,
        createdAt: DateTime.now(),
        metadata: {
          'tool_result': {
            'tool_call_id': result.toolCallId,
            'tool_name': result.toolName,
            'result': result.result,
          },
        },
      ),
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
