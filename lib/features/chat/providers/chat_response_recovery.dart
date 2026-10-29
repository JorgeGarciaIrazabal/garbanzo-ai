import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:garbanzo_ai/features/chat/models/chat_message.dart';

enum ChatResponseRecoveryState { waitingForConnection, syncing }

/// Polls the server after a dropped SSE stream or detached server turn until
/// the durable assistant reply (or visual presentation) lands in history.
class ChatResponseRecoveryController {
  ChatResponseRecoveryController({
    required this.pollInterval,
    required this.currentConversationId,
    required this.reloadCurrentConversation,
    required this.onStateChanged,
  });

  final Duration pollInterval;
  final String? Function() currentConversationId;
  final Future<bool> Function() reloadCurrentConversation;
  final VoidCallback onStateChanged;

  ChatResponseRecoveryState? _state;
  ChatResponseRecoveryState? get state => _state;
  bool get isRecovering => _state != null;

  Timer? _timer;
  String? _conversationId;
  Set<String> _replyIdsBeforeRecovery = const {};

  void begin({
    required String conversationId,
    required List<ChatMessage> currentMessages,
    ChatResponseRecoveryState initialState =
        ChatResponseRecoveryState.waitingForConnection,
  }) {
    _timer?.cancel();
    _conversationId = conversationId;
    _replyIdsBeforeRecovery = {
      for (final message in currentMessages)
        if (_isSavedReply(message)) message.id,
    };
    _state = initialState;
    _schedule(Duration.zero);
  }

  void completeIfArrived(List<ChatMessage> messages) {
    if (!isRecovering || currentConversationId() != _conversationId) {
      return;
    }
    final hasNewReply = messages.any(
      (message) =>
          _isSavedReply(message) &&
          !_replyIdsBeforeRecovery.contains(message.id),
    );
    if (hasNewReply) cancel();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _state = null;
    _conversationId = null;
    _replyIdsBeforeRecovery = const {};
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_poll()));
  }

  Future<void> _poll() async {
    if (!isRecovering || currentConversationId() != _conversationId) {
      return;
    }
    final reachedServer = await reloadCurrentConversation();
    if (!isRecovering) return;
    if (reachedServer && _state != ChatResponseRecoveryState.syncing) {
      _state = ChatResponseRecoveryState.syncing;
      onStateChanged();
    }
    _schedule(pollInterval);
  }

  /// A visual-only answer has no assistant text message. Recovery and visual
  /// follow-ups must recognize its saved result as a completed reply too.
  static bool _isSavedReply(ChatMessage message) =>
      !message.id.startsWith('temp-') &&
      (message.isAssistant || message.visualPresentation != null);

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
