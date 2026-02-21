import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/chat_service.dart';

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
      _messages = conversation.messages ?? [];
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
      );

      _currentConversation = conversation;
      _messages = [];

      if (initialMessage != null && initialMessage.isNotEmpty) {
        await sendMessage(initialMessage);
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

  Future<void> updateConversation({String? title, String? model}) async {
    if (_currentConversation == null) return;

    _error = null;
    notifyListeners();

    try {
      final updated = await _chatService.updateConversation(
        _currentConversation!.id,
        title: title,
        model: model,
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

  // ==========================================================================
  // Messaging
  // ==========================================================================

  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    _error = null;
    _isSending = true;

    if (_currentConversation == null) {
      await createConversation(
        model: _selectedModelId() ?? 'llama3.2',
        initialMessage: content,
      );
      return;
    }

    final userMessage = ChatMessage(
      id: 'temp-${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: content,
      createdAt: DateTime.now(),
    );
    _messages = [..._messages, userMessage];
    notifyListeners();

    final assistantMessageId =
        'temp-${DateTime.now().millisecondsSinceEpoch + 1}';
    String accumulatedContent = '';

    try {
      final stream = _chatService.streamChatResponse(
        _currentConversation!.id,
        content,
      );

      _streamSubscription = stream.listen(
        (chunk) {
          if (chunk.isChunk && chunk.content != null) {
            accumulatedContent += chunk.content!;

            final existingIndex = _messages.indexWhere(
              (m) => m.id == assistantMessageId,
            );

            final assistantMessage = ChatMessage(
              id: assistantMessageId,
              role: 'assistant',
              content: accumulatedContent,
              createdAt: DateTime.now(),
              metadata: chunk.metadata,
            );

            if (existingIndex >= 0) {
              final newMessages = List<ChatMessage>.from(_messages);
              newMessages[existingIndex] = assistantMessage;
              _messages = newMessages;
            } else {
              _messages = [..._messages, assistantMessage];
            }

            notifyListeners();
          } else if (chunk.isDone) {
            _isSending = false;

            if (_currentConversation != null) {
              _currentConversation = _currentConversation!.copyWith(
                messageCount: _messages.length,
              );
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

  Future<void> _reloadCurrentConversation() async {
    if (_currentConversation == null) return;
    try {
      await loadConversation(_currentConversation!.id);
    } catch (e) {
      if (kDebugMode) print('Failed to reload conversation: $e');
    }
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
